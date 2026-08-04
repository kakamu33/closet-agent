class AuthUser {
  const AuthUser({
    required this.id,
    required this.username,
    required this.nickname,
    required this.email,
    required this.emailVerified,
    required this.createdAt,
  });

  final String id;
  final String username;
  final String nickname;
  final String email;
  final bool emailVerified;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'username': username,
    'nickname': nickname,
    'email': email,
    'email_verified': emailVerified,
    'created_at': createdAt.toIso8601String(),
  };

  factory AuthUser.fromJson(Map<String, Object?> json) => AuthUser(
    id: json['id']! as String,
    username: json['username']! as String,
    nickname: json['nickname']! as String,
    email: json['email']! as String,
    emailVerified: json['email_verified'] as bool? ?? false,
    createdAt: DateTime.parse(json['created_at']! as String),
  );
}
