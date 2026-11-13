import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../core/cloudbase/cloudbase_client.dart';
import '../../../core/sync/storage_coordinator.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';
import 'auth_store.dart';

class CloudBaseAuthRepository implements AuthRepository, AuthSessionEvents {
  CloudBaseAuthRepository({CloudBaseClient? client, AuthStore? store})
    : _client = client ?? CloudBaseClient(),
      _store = store ?? AuthStore();

  static const _epochKey = 'diexu.cloudbase.auth.epoch.v1';
  final _authCoordinator = StorageCoordinator('authentication');
  static const _sessionKey = 'diexu.cloudbase.auth.session.v1';
  static const _lastLoginIdentifierKey =
      'diexu.cloudbase.auth.last_login_identifier.v1';
  static const _deviceIdKey = 'diexu.cloudbase.auth.device_id.v1';

  final CloudBaseClient _client;
  final AuthStore _store;

  @override
  Stream<void> get sessionChanges => _store.sessionChanges.map((_) {
    _sessionGeneration++;
    _refreshing = null;
  });
  Future<_CloudBaseSession?>? _refreshing;
  int _sessionGeneration = 0;
  bool _legacySecretsCleared = false;

  Future<(int, String)> _beginIdentityChange() async {
    final generation = ++_sessionGeneration;
    _refreshing = null;
    final epoch = const Uuid().v4();
    await _authCoordinator.local(() async {
      if (generation != _sessionGeneration) {
        throw const AuthException('登录操作已取消');
      }
      await _store.write(_epochKey, epoch);
    });
    return (generation, epoch);
  }

  Future<void> _commitIdentity(
    Map<String, Object?> response,
    AuthUser user,
    (int, String) lease,
  ) => _authCoordinator.local(() async {
    if (lease.$1 != _sessionGeneration ||
        await _store.read(_epochKey) != lease.$2) {
      throw const AuthException('登录操作已取消');
    }
    await _saveSession(response, user);
  });

  @override
  Future<AuthUser?> currentUser() async {
    if (!_legacySecretsCleared) {
      await _store.delete('diexu.auth.accounts.v1');
      await _store.delete('diexu.auth.current_user_id.v1');
      _legacySecretsCleared = true;
    }
    // Startup remains usable offline. Remote operations independently require
    // a fresh access token and never treat a network outage as a logout.
    return (await _readSession())?.user;
  }

  Future<_CloudBaseSession?> _validSession() async {
    final session = await _readSession();
    if (session == null) return null;
    if (session.expiresAt.isAfter(
      DateTime.now().toUtc().add(const Duration(seconds: 30)),
    )) {
      return session;
    }
    if (_refreshing case final active?) return active;
    final generation = _sessionGeneration;
    final request = _refreshSession(session, generation);
    _refreshing = request;
    try {
      return await request;
    } finally {
      if (identical(_refreshing, request)) _refreshing = null;
    }
  }

  Future<_CloudBaseSession?> _refreshSession(
    _CloudBaseSession session,
    int generation,
  ) async {
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
      return _authCoordinator.local(() async {
        if (generation != _sessionGeneration ||
            (await _readSession())?.refreshToken != session.refreshToken) {
          return null;
        }
        await _saveSession(response, session.user);
        return _readSession();
      });
    } on CloudBaseException catch (error) {
      if (generation == _sessionGeneration &&
          (error.statusCode == 401 || error.message == 'invalid_grant')) {
        return _authCoordinator.local(() async {
          if (generation == _sessionGeneration &&
              (await _readSession())?.refreshToken == session.refreshToken) {
            await _store.delete(_sessionKey);
          }
          return null;
        });
      }
      rethrow;
    }
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
    final lease = await _beginIdentityChange();
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
      final accessToken = _requiredString(tokenResponse, 'access_token');
      await _commitIdentity(tokenResponse, user, lease);
      await _ensureProfile(user, accessToken);
      final cloudUser = user;
      await _store.write(_lastLoginIdentifierKey, normalizedUsername);
      return cloudUser;
    } on CloudBaseException catch (error) {
      throw AuthException(_friendlyMessage(error));
    }
  }

  @override
  Future<AuthUser> login({
    required String identifier,
    required String password,
  }) async {
    final lease = await _beginIdentityChange();
    final normalizedIdentifier = identifier.trim().toLowerCase();
    try {
      final response = await _client.requestObject(
        'POST',
        '/auth/v1/signin',
        body: {'username': normalizedIdentifier, 'password': password},
        extraHeaders: {'x-device-id': await _deviceId()},
      );
      final accessToken = _requiredString(response, 'access_token');
      final authenticatedUser = AuthUser(
        id: _requiredString(response, 'sub'),
        // 登录标识只用于认证，资料必须以云端 user_profiles 为准。
        username: normalizedIdentifier,
        nickname: '叠序用户',
        email: normalizedIdentifier.contains('@') ? normalizedIdentifier : '',
        emailVerified: true,
        createdAt: DateTime.now().toUtc(),
      );
      final user = await _loadCloudUser(authenticatedUser, accessToken);
      await _commitIdentity(response, user, lease);
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
  @override
  Future<String?> currentAccessToken() async =>
      (await _validSession())?.accessToken;

  @override
  Future<void> logout() async {
    _sessionGeneration++;
    _refreshing = null;
    await _authCoordinator.local(() async {
      await _store.write(_epochKey, const Uuid().v4());
      await _store.delete(_sessionKey);
    });
  }

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
    final session = await _validSession();
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
        final detail = (result['detail'] as String?)?.trim();
        final message = (result['error'] as String?) ?? '注销失败，请稍后重试';
        throw AuthException(
          detail?.isNotEmpty == true ? '$message：$detail' : message,
        );
      }
    } on CloudBaseException catch (error) {
      throw AuthException(_friendlyMessage(error));
    }
    await _authCoordinator.local(() async {
      if ((await _readSession())?.user.id == session.user.id) {
        _sessionGeneration++;
        _refreshing = null;
        await _store.write(_epochKey, const Uuid().v4());
        await _store.delete(_sessionKey);
      }
    });
  }

  /// 每次建立或恢复会话都以云端资料为唯一来源，避免用户名登录和邮箱登录
  /// 因本地旧会话缓存而展示出不同的用户信息。
  Future<AuthUser> _loadCloudUser(
    AuthUser authenticatedUser,
    String accessToken,
  ) async {
    final response = await _client.request(
      'GET',
      '/v1/rdb/rest/user_profiles',
      accessToken: accessToken,
      queryParameters: {
        'user_id': 'eq.${authenticatedUser.id}',
        'select': 'user_id,username,email,nickname',
        'limit': '1',
      },
    );
    if (response is! List || response.length != 1 || response.single is! Map) {
      throw const AuthException('未找到云端账号资料，请重新登录或联系支持');
    }
    final profile = Map<String, Object?>.from(response.single as Map);
    return AuthUser(
      id: _requiredString(profile, 'user_id'),
      username: _requiredString(profile, 'username'),
      nickname: _requiredString(profile, 'nickname'),
      email: _requiredString(profile, 'email'),
      emailVerified: true,
      createdAt: authenticatedUser.createdAt,
    );
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

  _CloudBaseSession copyWith({AuthUser? user}) => _CloudBaseSession(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: expiresAt,
    user: user ?? this.user,
  );

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
