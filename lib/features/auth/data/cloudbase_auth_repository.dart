import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/cloudbase/cloudbase_client.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';
import 'auth_store.dart';

class CloudBaseAuthRepository implements AuthRepository {
  CloudBaseAuthRepository({CloudBaseClient? client, AuthStore? store})
    : _client = client ?? CloudBaseClient(),
      _store = store ?? AuthStore();

  static const _sessionKey = 'diexu.cloudbase.auth.session.v1';
  static const _lastLoginIdentifierKey =
      'diexu.cloudbase.auth.last_login_identifier.v1';
  static const _deviceIdKey = 'diexu.cloudbase.auth.device_id.v1';
  static const _legacyCleanupKey = 'diexu.cloudbase.auth.legacy_cleanup.v1';

  final CloudBaseClient _client;
  final AuthStore _store;

  @override
  Future<AuthUser?> currentUser() async {
    final session = await _readSession();
    if (session == null) return null;
    if (session.expiresAt.isAfter(DateTime.now().toUtc())) {
      await _ensureProfile(session.user, session.accessToken);
      return session.user;
    }
    try {
      final response = await _client.requestObject(
        'POST',
        '/auth/v1/token',
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': session.refreshToken,
        },
        extraHeaders: {'x-device-id': await _deviceId()},
      );
      await _saveSession(response, session.user);
      return session.user;
    } on CloudBaseException {
      await _store.delete(_sessionKey);
      return null;
    }
  }

  /// 清除旧版本地认证原型遗留的数据，仅在首次云端迁移时执行一次。
  Future<bool> clearLegacyLocalAuthArtifacts() async {
    if (await _store.read(_legacyCleanupKey) == 'done') return false;
    for (final key in const [
      'diexu.auth.accounts.v1',
      'diexu.auth.current_user_id.v1',
      _lastLoginIdentifierKey,
      _sessionKey,
    ]) {
      await _store.delete(key);
    }
    await _store.write(_legacyCleanupKey, 'done');
    return true;
  }

  @override
  Future<String?> lastLoginIdentifier() => _store.read(_lastLoginIdentifierKey);

  @override
  Future<String> sendRegistrationVerificationCode({
    required String email,
  }) async {
    try {
      final result = await _client.requestObject(
        'POST',
        '/auth/v1/verification',
        body: {'email': email.trim().toLowerCase(), 'target': 'ANY'},
        extraHeaders: {'x-device-id': await _deviceId()},
      );
      final id = result['verification_id'] ?? result['id'];
      if (id is! String || id.isEmpty) {
        throw const AuthException('未获取到邮箱验证码凭证，请稍后重试');
      }
      return id;
    } on CloudBaseException catch (error) {
      throw AuthException(_friendlyMessage(error));
    }
  }

  @override
  Future<AuthUser> register({
    required String username,
    required String nickname,
    required String email,
    required String password,
    required String verificationId,
    required String verificationCode,
  }) async {
    final normalizedUsername = username.trim().toLowerCase();
    final normalizedEmail = email.trim().toLowerCase();
    try {
      final verified = await _client.requestObject(
        'POST',
        '/auth/v1/verification/verify',
        body: {
          'verification_id': verificationId,
          'verification_code': verificationCode.trim(),
        },
      );
      final verificationToken = verified['verification_token'];
      if (verificationToken is! String || verificationToken.isEmpty) {
        throw const AuthException('验证码验证失败，请重新获取验证码');
      }
      final tokenResponse = await _client.requestObject(
        'POST',
        '/auth/v1/signup',
        body: {
          'email': normalizedEmail,
          'verification_token': verificationToken,
          'username': normalizedUsername,
          'password': password,
          'name': nickname.trim(),
        },
        extraHeaders: {'x-device-id': await _deviceId()},
      );
      final user = AuthUser(
        id: _requiredString(tokenResponse, 'sub'),
        username: normalizedUsername,
        nickname: nickname.trim(),
        email: normalizedEmail,
        emailVerified: true,
        createdAt: DateTime.now().toUtc(),
      );
      await _saveSession(tokenResponse, user);
      await _ensureProfile(
        user,
        _requiredString(tokenResponse, 'access_token'),
      );
      await _store.write(_lastLoginIdentifierKey, normalizedUsername);
      return user;
    } on CloudBaseException catch (error) {
      throw AuthException(_friendlyMessage(error));
    }
  }

  @override
  Future<AuthUser> login({
    required String identifier,
    required String password,
  }) async {
    final normalizedIdentifier = identifier.trim().toLowerCase();
    try {
      final response = await _client.requestObject(
        'POST',
        '/auth/v1/signin',
        body: {'username': normalizedIdentifier, 'password': password},
        extraHeaders: {'x-device-id': await _deviceId()},
      );
      final previous = await _readSession();
      final user = AuthUser(
        id: _requiredString(response, 'sub'),
        username: normalizedIdentifier.contains('@')
            ? previous?.user.username ?? normalizedIdentifier
            : normalizedIdentifier,
        nickname: previous?.user.nickname ?? '叠序用户',
        email: normalizedIdentifier.contains('@')
            ? normalizedIdentifier
            : previous?.user.email ?? '',
        emailVerified: true,
        createdAt: previous?.user.createdAt ?? DateTime.now().toUtc(),
      );
      await _saveSession(response, user);
      await _ensureProfile(user, _requiredString(response, 'access_token'));
      await _store.write(_lastLoginIdentifierKey, normalizedIdentifier);
      return user;
    } on CloudBaseException catch (error) {
      throw AuthException(_friendlyMessage(error));
    }
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    // CloudBase 邮箱验证码已经可发送；重置密码接口将在其 HTTP 契约确认后接入。
    throw const AuthException('密码找回正在接入，请暂时使用原密码登录');
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String verificationCode,
    required String newPassword,
  }) async {
    throw const AuthException('密码重置暂未开放');
  }

  /// 供受 RLS 保护的 CloudBase 数据仓库使用；必要时会自动刷新会话。
  Future<String?> currentAccessToken() async {
    final user = await currentUser();
    if (user == null) return null;
    return (await _readSession())?.accessToken;
  }

  @override
  Future<void> logout() => _store.delete(_sessionKey);

  /// 永久注销当前账号：删除 CloudBase Auth 账号本身（`auth.users` 记录）
  /// 及其全部业务数据（衣物、标签、个人资料），不可恢复。
  ///
  /// **实现方式**：CloudBase 官方 HTTP API 并未开放任何面向客户端的
  /// “自助删除 Auth 账号”接口——删除用户是管理端能力，必须持有管理员
  /// 密钥才能执行。因此这一操作被收敛到云函数 `deleteAccount`
  /// （见 `cloudfunctions/deleteAccount/`）中完成：云函数运行时天然具备
  /// 管理员权限，客户端只需带上自己的 access token 调用它，不会接触到
  /// 任何管理员密钥。云函数内部会先校验这个 token 的真实归属，再以
  /// 管理员身份执行删除，杜绝越权删除他人账号的风险。
  @override
  Future<void> deleteAccount() async {
    final session = await _readSession();
    if (session == null) {
      throw const AuthException('登录状态已失效，请重新登录后再试');
    }
    try {
      // 注意：CloudBase 网关的 `/v1/functions/{name}` 路径调用普通云函数走
      // 的是"云调用"语义——只会把请求体透传为云函数的 event 参数，并不会
      // 转发 Authorization 头。因此 access token 必须放进请求体里，云函数
      // 侧 `deleteAccount` 也是从 `event.accessToken` 读取的，两边需保持一致。
      final result = await _client.requestObject(
        'POST',
        '/v1/functions/deleteAccount',
        accessToken: session.accessToken,
        body: {'accessToken': session.accessToken},
        extraHeaders: {'x-device-id': await _deviceId()},
      );
      if (result['success'] != true) {
        throw AuthException((result['error'] as String?) ?? '注销失败，请稍后重试');
      }
    } on CloudBaseException catch (error) {
      throw AuthException(_friendlyMessage(error));
    } finally {
      // 无论云端删除是否完全成功，都不应让用户停留在一个残缺的已登录状态。
      await _store.delete(_sessionKey);
    }
  }

  /// 创建与 CloudBase Auth 用户一一对应的业务资料行。
  ///
  /// Auth 服务只创建 `auth` schema 的账号；`public.user_profiles` 是本应用
  /// 的业务表，必须由应用在认证成功后单独写入。
  Future<void> _ensureProfile(AuthUser user, String accessToken) async {
    if (user.email.trim().isEmpty) return;
    try {
      await _client.request(
        'POST',
        '/v1/rdb/rest/user_profiles',
        accessToken: accessToken,
        body: {
          'user_id': user.id,
          'username': user.username,
          'email': user.email,
          'nickname': user.nickname,
        },
        extraHeaders: const {
          'Prefer': 'resolution=ignore-duplicates,return=minimal',
        },
      );
    } on CloudBaseException {
      // 资料写入失败不能使已验证的认证会话丢失；随后新增衣物时会再次补建。
    }
  }

  Future<String> _deviceId() async {
    final existing = await _store.read(_deviceIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final deviceId = const Uuid().v4();
    await _store.write(_deviceIdKey, deviceId);
    return deviceId;
  }

  Future<_CloudBaseSession?> _readSession() async {
    final raw = await _store.read(_sessionKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      return _CloudBaseSession.fromJson(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } on FormatException {
      await _store.delete(_sessionKey);
      return null;
    } on TypeError {
      await _store.delete(_sessionKey);
      return null;
    }
  }

  Future<void> _saveSession(
    Map<String, Object?> response,
    AuthUser user,
  ) async {
    final accessToken = _requiredString(response, 'access_token');
    final refreshToken = _requiredString(response, 'refresh_token');
    final expiresIn = response['expires_in'];
    if (expiresIn is! num) {
      throw const AuthException('云端未返回有效的会话有效期');
    }
    final session = _CloudBaseSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: DateTime.now().toUtc().add(
        Duration(seconds: expiresIn.toInt()),
      ),
      user: user,
    );
    await _store.write(_sessionKey, jsonEncode(session.toJson()));
  }

  String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is! String || value.isEmpty) {
      throw AuthException('云端未返回有效的 $key');
    }
    return value;
  }

  String _friendlyMessage(CloudBaseException error) {
    return switch (error.message) {
      'invalid_username_or_password' => '用户名、邮箱或密码不正确',
      _ => error.message,
    };
  }
}

class _CloudBaseSession {
  const _CloudBaseSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final AuthUser user;

  Map<String, Object?> toJson() => {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_at': expiresAt.toIso8601String(),
    'user': user.toJson(),
  };

  factory _CloudBaseSession.fromJson(Map<String, Object?> json) =>
      _CloudBaseSession(
        accessToken: json['access_token']! as String,
        refreshToken: json['refresh_token']! as String,
        expiresAt: DateTime.parse(json['expires_at']! as String),
        user: AuthUser.fromJson(
          Map<String, Object?>.from(json['user']! as Map),
        ),
      );
}
