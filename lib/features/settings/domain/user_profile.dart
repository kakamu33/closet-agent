class UserProfile {
  const UserProfile({
    required this.id,
    required this.nickname,
    required this.signature,
    this.avatarPath,
    this.syncVersion = 0,
  });

  final String id;
  final String nickname;
  final String signature;
  final String? avatarPath;
  final int syncVersion;

  UserProfile withVersion(int version) => UserProfile(
    id: id,
    nickname: nickname,
    signature: signature,
    avatarPath: avatarPath,
    syncVersion: version,
  );
  Map<String, Object?> toSyncMap() => {...toMap(), 'sync_version': syncVersion};

  static const defaults = UserProfile(
    id: 'diexu_local',
    nickname: '叠序用户',
    signature: '记录每一次恰到好处的穿搭。',
  );

  Map<String, Object?> toMap() => {
    'id': id,
    'nickname': nickname,
    'signature': signature,
    'avatar_path': avatarPath,
  };

  factory UserProfile.fromMap(Map<String, Object?> map) => UserProfile(
    id: map['id']! as String,
    nickname: map['nickname']! as String,
    signature: map['signature']! as String,
    avatarPath: map['avatar_path'] as String?,
    syncVersion: (map['sync_version'] as num?)?.toInt() ?? 0,
  );
}
