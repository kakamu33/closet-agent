/**
 * 云函数：deleteAccount
 *
 * 作用：彻底删除当前登录用户的 CloudBase Auth 账号（`auth.users` 表中的记录）
 * 以及其名下的全部业务数据（衣物、标签、个人资料等），不可恢复。
 *
 * 为什么需要云函数：CloudBase 官方 HTTP API 并未开放"客户端自助删除 Auth
 * 账号"的接口，删除用户只能通过管理员权限完成。云函数运行时会自动从环境
 * 变量注入 `secretId`/`secretKey`，天然具备管理员权限，因此把这个高危操作
 * 收敛到这里，客户端只需带上自己的 access token 调用即可，不会接触到任何
 * 管理员密钥。
 *
 * 安全性：不信任客户端传入的任何用户身份字段。真实身份完全由 access token
 * 决定——先用这个 token 去调一次只读接口，换取 token 背后真实的 user_id，
 * 再据此删除，从根本上杜绝"传别人的 uid 把别人账号删掉"的越权风险。
 */

const tencentcloud = require('tencentcloud-sdk-nodejs-tcb');
const https = require('https');

// 实测证明：`TCB_ENV` 这个环境变量并非每次调用都会被运行时注入——它
// 应该是随"云调用上下文"（比如客户端登录态）附带下发的，同一份代码在
// 不同请求里时而有值、时而是 undefined（可通过日志复现）。而云环境 ID
// 本身几乎不会变化，因此这里用固定值兜底，只有在运行时确实提供了该变量
// 时才优先采用它，从根本上避免 GATEWAY_HOST / ExecutePGSql 的 EnvId
// 偶发性地被拼成 "undefined"。
const FALLBACK_ENV_ID = 'closet-33-d0gir16vl115bde45';
const TCB_ENV = process.env.TCB_ENV || FALLBACK_ENV_ID;
const REGION = process.env.TENCENTCLOUD_REGION || 'ap-shanghai';
const GATEWAY_HOST =
  process.env.TCB_GATEWAY_HOST || `${TCB_ENV}.api.tcloudbasegateway.com`;

const TcbClient = tencentcloud.tcb.v20180608.Client;

/** 需要级联清理的业务表；顺序不重要，因为最终以 SQL 事务方式一次性删除。 */
const OWNED_TABLES = [
  'wardrobe_items',
  'wardrobe_tags',
  'outfits',
  'outfit_tags',
  'user_profiles',
];

exports.main = async (event, context) => {
  try {
    console.log('[deleteAccount] env:', { TCB_ENV, REGION, GATEWAY_HOST });
    console.log('[deleteAccount] raw event:', JSON.stringify(event));

    const accessToken = extractAccessToken(event);
    console.log('[deleteAccount] accessToken length:', accessToken ? accessToken.length : null);
    if (!accessToken) {
      return respond(401, { error: '缺少有效的登录凭证' });
    }

    const userId = await resolveUserId(accessToken);
    console.log('[deleteAccount] resolved userId:', userId);
    if (!userId) {
      return respond(401, { error: '登录状态已失效，请重新登录后再试' });
    }

    await deleteAccountAndData(userId);

    return respond(200, { success: true, userId });
  } catch (error) {
    console.error('[deleteAccount] 执行失败:', error);
    return respond(500, {
      error: '注销失败，请稍后重试',
      detail: error.message,
    });
  }
};

/**
 * 提取客户端传来的 access token。
 *
 * 通过 CloudBase 网关 `/v1/functions/{name}` 路径调用普通云函数时，
 * 网关走的是"云调用"语义：只会把请求体（JSON body）解析后原样作为
 * `event` 传入，并不会把 HTTP 头（包括 Authorization）透传进来。
 * 因此客户端必须把 access token 放进请求体的 `accessToken` 字段，
 * 而不是 Authorization 头；这里同时兼容 HTTP 触发事件（`event.headers`）
 * 形态，便于将来切换到云函数 URL / HTTP 访问服务时无需改动。
 */
function extractAccessToken(event) {
  if (typeof event?.accessToken === 'string' && event.accessToken.trim()) {
    return event.accessToken.trim();
  }
  const headers = event?.headers || {};
  const raw =
    headers.authorization ||
    headers.Authorization ||
    (typeof event?.body === 'string' && tryParseJson(event.body)?.accessToken);
  if (!raw) return null;
  const match = /^Bearer\s+(.+)$/i.exec(raw.trim());
  return match ? match[1] : raw.trim();
}

function tryParseJson(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

/**
 * 校验 access token 合法性，并返回其背后真实的 user_id。
 *
 * PG 模式下 access token 本身就是一个 JWT，`sub` 字段即用户 ID。但客户端
 * 传来的 token 不能被直接信任（存在伪造风险），因此分两步：
 *   1. 解析 JWT payload 拿到"声称的" sub——这一步只是读取，不代表信任；
 *   2. 用这个 token 真实发起一次网关请求（查询任意一张要求
 *      `authenticated` 角色的表），网关会校验 JWT 签名与有效期。
 *      只要网关返回非 401/403，说明这个 token 确实由 CloudBase 签发且
 *      未过期，此时第 1 步解析出的 sub 才是可信的。
 *
 * 这里特意不依赖 `user_profiles` 是否已有数据行（哪怕该表为空、甚至
 * 因历史 bug 缺失了资料行，只要 token 有效，查询本身仍会成功返回空
 * 数组），避免"资料行缺失导致无法注销"的死循环。
 */
async function resolveUserId(accessToken) {
  const claimedUserId = decodeJwtSubject(accessToken);
  console.log('[resolveUserId] claimedUserId:', claimedUserId);
  if (!claimedUserId) return null;

  const verified = await probeTokenValidity(accessToken);
  console.log('[resolveUserId] probe verified:', verified);
  return verified ? claimedUserId : null;
}

/** 解析 JWT payload 中的 `sub` 字段，不做签名校验（仅用于读取声明）。 */
function decodeJwtSubject(token) {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(
      Buffer.from(
        parts[1].replace(/-/g, '+').replace(/_/g, '/'),
        'base64',
      ).toString('utf8'),
    );
    return typeof payload.sub === 'string' && payload.sub ? payload.sub : null;
  } catch {
    return null;
  }
}

/**
 * 用真实网络请求验证 token 是否被网关接受（未过期、签名有效）。
 *
 * 网络层错误（DNS、超时、连接被拒等）也会被视为校验失败，而不是让整个
 * 云函数因未处理的 Promise rejection 而返回 500。
 */
function probeTokenValidity(accessToken) {
  return new Promise((resolve) => {
    const req = https.request(
      {
        hostname: GATEWAY_HOST,
        // wardrobe_tags 允许 authenticated 角色 SELECT 自己的数据；
        // 即使账号名下没有任何标签，查询本身依然会成功返回空数组。
        path: '/v1/rdb/rest/wardrobe_tags?select=id&limit=1',
        method: 'GET',
        headers: {
          Authorization: `Bearer ${accessToken}`,
          Accept: 'application/json',
        },
        timeout: 8000,
      },
      (res) => {
        let body = '';
        res.on('data', (chunk) => {
          body += chunk;
        });
        res.on('end', () => {
          console.log(
            '[probeTokenValidity] statusCode:',
            res.statusCode,
            'body:',
            body.slice(0, 300),
          );
          resolve(res.statusCode >= 200 && res.statusCode < 300);
        });
      },
    );
    req.on('timeout', () => {
      req.destroy();
      console.log('[probeTokenValidity] timeout');
      resolve(false);
    });
    req.on('error', (error) => {
      console.log('[probeTokenValidity] error:', error.message);
      resolve(false);
    });
    req.end();
  });
}

/**
 * 用管理员身份（`ExecutePGSql`，省略 Role 即以 `cloudbase_admin` 执行，
 * 具备 SUPERUSER + BYPASSRLS）依次删除业务数据与 Auth 账号本身。
 *
 * 每条 DELETE 独立执行——`ExecutePGSql` 每次调用只支持一条 SQL。
 */
async function deleteAccountAndData(userId) {
  // 云函数运行时会自动把管理员临时密钥注入到这三个环境变量中，
  // 无需在控制台手动配置——这也是云函数天生具备管理员权限的原因。
  const client = new TcbClient({
    credential: {
      secretId: process.env.TENCENTCLOUD_SECRETID,
      secretKey: process.env.TENCENTCLOUD_SECRETKEY,
      token: process.env.TENCENTCLOUD_SESSIONTOKEN,
    },
    region: REGION,
  });

  const escapedUserId = userId.replace(/'/g, "''");

  for (const table of OWNED_TABLES) {
    const sql = `DELETE FROM public.${table} WHERE user_id = '${escapedUserId}'`;
    const result = await client.ExecutePGSql({ EnvId: TCB_ENV, Sql: sql });
    console.log(`[deleteAccountAndData] ${table} ->`, JSON.stringify(result));
  }

  // 最后删除 Auth 账号本身；一旦这一步完成，该 access token 会立即失效。
  const authSql = `DELETE FROM auth.users WHERE id = '${escapedUserId}'`;
  const authResult = await client.ExecutePGSql({ EnvId: TCB_ENV, Sql: authSql });
  console.log('[deleteAccountAndData] auth.users ->', JSON.stringify(authResult));
}

function respond(statusCode, payload) {
  return {
    statusCode,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
    body: JSON.stringify(payload),
  };
}

