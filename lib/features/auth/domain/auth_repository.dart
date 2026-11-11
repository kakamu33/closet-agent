import 'auth_user.dart';

abstract interface class AuthRepository {
  Future<AuthUser?> currentUser();
  Future<String?> currentAccessToken();

  /// 仅保存最近使用的用户名或邮箱，绝不保存密码。
  Future<String?> lastLoginIdentifier();

  /// 向邮箱发送注册验证码，返回后续校验所需的 verification_id。
  Future<String> sendRegistrationVerificationCode({required String email});

  Future<AuthUser> register({
    required String username,
    required String nickname,
    required String email,
    required String password,
    required String verificationId,
    required String verificationCode,
  });

  Future<AuthUser> login({
    required String identifier,
    required String password,
  });

  Future<void> requestPasswordReset({required String email});

  Future<void> resetPassword({
    required String email,
    required String verificationCode,
    required String newPassword,
  });

  Future<void> logout();

  /// 永久注销当前账号：删除账号登录凭证及全部业务数据（衣物、标签、
  /// 搭配等），不可恢复。调用后应视为已自动退出登录，且无法再用原密码
  /// 登录。
  ///
  /// 云端实现通过云函数（`cloudfunctions/deleteAccount/`）以管理员权限
  /// 完成，因为 CloudBase 未开放客户端自助删除 Auth 账号的公开接口。
  Future<void> deleteAccount();
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}
