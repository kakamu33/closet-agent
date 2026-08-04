import 'dart:convert';

import 'package:crypt/crypt.dart';
import 'package:uuid/uuid.dart';

import '../domain/auth_repository.dart';
import '../domain/auth_user.dart';
import 'auth_store.dart';

/// 本地认证实现仅用于开发测试；后续可替换为 SCF HTTP API 实现。
class LocalAuthRepository implements AuthRepository {
  LocalAuthRepository({AuthStore? store}) : _store = store ?? AuthStore();

  static const _accountsKey = 'diexu.auth.accounts.v1';
  static const _currentUserIdKey = 'diexu.auth.current_user_id.v1';
  static const _lastLoginIdentifierKey = 'diexu.auth.last_login_identifier.v1';
  static final _usernamePattern = RegExp(r'^[A-Za-z][A-Za-z0-9_]{4,19}$');

  final AuthStore _store;

  @override
  Future<AuthUser?> currentUser() async {
    final userId = await _store.read(_currentUserIdKey);
    if (userId == null) return null;
    final account = (await _readAccounts())[userId];
    if (account == null) {
      await _store.delete(_currentUserIdKey);
      return null;
    }
    return account.user;
  }

  @override
  Future<String?> lastLoginIdentifier() => _store.read(_lastLoginIdentifierKey);

  @override
  Future<String> sendRegistrationVerificationCode({required String email}) async {
    if (!email.contains('@')) throw const AuthException('请输入有效邮箱');
    // 本地开发模式不发送真实邮件，保留与云端一致的调用顺序。
    return 'local-verification';
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
    _validateRegistration(
      username: normalizedUsername,
      nickname: nickname,
      email: normalizedEmail,
      password: password,
    );

    final accounts = await _readAccounts();
    if (accounts.values.any(
      (account) => account.user.username == normalizedUsername,
    )) {
      throw const AuthException('该用户名已被使用');
    }
    if (accounts.values.any(
      (account) => account.user.email == normalizedEmail,
    )) {
      throw const AuthException('该邮箱已绑定其他账号');
    }

    final user = AuthUser(
      id: const Uuid().v4(),
      username: normalizedUsername,
      nickname: nickname.trim(),
      email: normalizedEmail,
      // 本地原型不发送邮件，显式标识为本地已验证模拟状态。
      emailVerified: true,
      createdAt: DateTime.now().toUtc(),
    );
    accounts[user.id] = _StoredAccount(
      user: user,
      passwordHash: Crypt.sha256(password, rounds: 10000).toString(),
    );
    await _writeAccounts(accounts);
    await _store.write(_currentUserIdKey, user.id);
    await _store.write(_lastLoginIdentifierKey, user.username);
    return user;
  }

  @override
  Future<AuthUser> login({
    required String identifier,
    required String password,
  }) async {
    final value = identifier.trim().toLowerCase();
    final accounts = await _readAccounts();
    final account = accounts.values.where((candidate) {
      return candidate.user.username == value || candidate.user.email == value;
    }).firstOrNull;
    if (account == null) {
      throw const AuthException('用户名或邮箱未注册');
    }
    if (!Crypt(account.passwordHash).match(password)) {
      throw const AuthException('密码错误，请重新输入');
    }
    await _store.write(_currentUserIdKey, account.user.id);
    await _store.write(_lastLoginIdentifierKey, value);
    return account.user;
  }

  @override
  Future<void> requestPasswordReset({required String email}) async {
    final normalizedEmail = email.trim().toLowerCase();
    final exists = (await _readAccounts()).values.any(
      (account) => account.user.email == normalizedEmail,
    );
    if (!exists) throw const AuthException('未找到该邮箱绑定的账号');
    // 云端版本将由 SCF 发送邮箱验证码；本地版只保留流程入口。
  }

  @override
  Future<void> resetPassword({
    required String email,
    required String verificationCode,
    required String newPassword,
  }) async {
    throw const AuthException('本地测试版暂不支持邮件验证码重置，请使用原密码登录');
  }

  @override
  Future<void> logout() => _store.delete(_currentUserIdKey);

  @override
  Future<void> deleteAccount() async {
    final userId = await _store.read(_currentUserIdKey);
    if (userId == null) {
      throw const AuthException('登录状态已失效，请重新登录后再试');
    }
    final accounts = await _readAccounts();
    accounts.remove(userId);
    await _writeAccounts(accounts);
    await _store.delete(_currentUserIdKey);
  }

  Future<Map<String, _StoredAccount>> _readAccounts() async {
    final raw = await _store.read(_accountsKey);
    if (raw == null || raw.isEmpty) return <String, _StoredAccount>{};
    try {
      final values = Map<String, Object?>.from(jsonDecode(raw) as Map);
      return values.map(
        (id, value) => MapEntry(
          id,
          _StoredAccount.fromJson(Map<String, Object?>.from(value as Map)),
        ),
      );
    } on FormatException {
      await _store.delete(_accountsKey);
      return <String, _StoredAccount>{};
    }
  }

  Future<void> _writeAccounts(Map<String, _StoredAccount> accounts) =>
      _store.write(
        _accountsKey,
        jsonEncode(
          accounts.map((id, account) => MapEntry(id, account.toJson())),
        ),
      );

  void _validateRegistration({
    required String username,
    required String nickname,
    required String email,
    required String password,
  }) {
    if (!_usernamePattern.hasMatch(username)) {
      throw const AuthException('用户名需为 5-20 位，首位英文，仅含英文、数字或下划线');
    }
    if (nickname.trim().isEmpty || nickname.trim().length > 20) {
      throw const AuthException('昵称需为 1-20 个字符');
    }
    if (!email.contains('@') || email.length > 254) {
      throw const AuthException('请输入有效邮箱');
    }
    if (password.length < 8) {
      throw const AuthException('密码至少需要 8 位');
    }
  }
}

class _StoredAccount {
  const _StoredAccount({required this.user, required this.passwordHash});

  final AuthUser user;
  final String passwordHash;

  Map<String, Object?> toJson() => {
    'user': user.toJson(),
    'password_hash': passwordHash,
  };

  factory _StoredAccount.fromJson(Map<String, Object?> json) => _StoredAccount(
    user: AuthUser.fromJson(Map<String, Object?>.from(json['user']! as Map)),
    passwordHash: json['password_hash']! as String,
  );
}
