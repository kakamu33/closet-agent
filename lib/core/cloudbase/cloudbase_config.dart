import 'package:flutter_dotenv/flutter_dotenv.dart';

class CloudBaseConfig {
  const CloudBaseConfig._();

  static const _defaultEnvironmentId = 'closet-33-d0gir16vl115bde45';

  static String get environmentId =>
      dotenv.env['CLOUDBASE_ENV_ID'] ?? _defaultEnvironmentId;

  /// Publishable Key 仅用于匿名公开能力；登录后的私有请求必须使用用户 access token。
  static String? get publishableKey {
    final value = dotenv.env['CLOUDBASE_PUBLISHABLE_KEY'];
    return value == null || value.trim().isEmpty ? null : value.trim();
  }

  static String get baseUrl =>
      'https://$environmentId.api.tcloudbasegateway.com';
}

