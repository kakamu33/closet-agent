import '../../../core/sync/cloud_sync_protocol.dart';
import '../../../core/sync/sync_collection.dart';
import '../../../core/cloudbase/cloudbase_client.dart';
import '../../../core/cloudbase/json_fields.dart';
import '../../../core/time_utils.dart';
import '../../auth/domain/auth_user.dart';
import '../domain/wardrobe_item.dart';
import '../domain/wardrobe_tag.dart';

/// 通过 PostgREST 访问 CloudBase 的私人衣物表。
///
/// 每个请求都携带登录用户的 access token；数据库 RLS 会再次校验
/// `user_id`，客户端不能借此读取或写入其他用户的数据。
class CloudBaseWardrobeRepository {
  CloudBaseWardrobeRepository({CloudBaseClient? client})
    : _client = client ?? CloudBaseClient();

  final CloudBaseClient _client;

  Future<void> ensureProfile({
    required AuthUser user,
    required String accessToken,
  }) async {
    if (user.email.trim().isEmpty) {
      throw const CloudBaseException('当前会话缺少邮箱信息，请使用邮箱重新登录');
    }
    await _client.request(
      'POST',
      '/v1/rdb/rest/user_profiles',
      accessToken: accessToken,
      body: {
        'user_id': user.id,
        'username': user.username,
        'email': user.email,
        'nickname': user.nickname,
        'email_verified': user.emailVerified,
      },
      extraHeaders: const {
        'Prefer': 'resolution=ignore-duplicates,return=minimal',
      },
    );
  }

  Future<RemoteSnapshot<WardrobeItem>> snapshotItems(String token) =>
      CloudSyncProtocol(_client).snapshot('items', token, _itemFromCloud);
  Future<List<WardrobeItem>> fetchItems({required String accessToken}) async =>
      (await snapshotItems(accessToken)).values;

  Future<RemoteSnapshot<WardrobeTag>> snapshotTags(String token) =>
      CloudSyncProtocol(
        _client,
      ).snapshot('wardrobe_tags', token, WardrobeTag.fromMap);
  Future<List<WardrobeTag>> fetchTags({required String accessToken}) async =>
      (await snapshotTags(accessToken)).values;

  WardrobeItem _itemFromCloud(Map<String, Object?> value) {
    final createdAt = parseTimestamp(value['created_at']);
    if (createdAt == null) {
      throw const CloudBaseException('云端衣物缺少必要字段');
    }
    return WardrobeItem(
      id: _requiredString(value, 'id'),
      syncVersion: (value['sync_version'] as num?)?.toInt() ?? 0,
      name: _requiredString(value, 'name'),
      imagePaths: _stringList(value['image_paths_json']),
      tagIds: _stringList(value['tag_ids_json']),
      brand: value['brand'] as String?,
      color: value['color'] as String?,
      notes: value['notes'] as String?,
      currency: value['currency'] as String? ?? 'CNY',
      price: (value['price'] as num?)?.toDouble(),
      createdAt: createdAt,
      updatedAt: parseTimestamp(value['updated_at']) ?? createdAt,
    );
  }

  String _requiredString(Map<String, Object?> value, String key) {
    final result = value[key];
    if (result is! String || result.isEmpty) {
      throw CloudBaseException('云端衣物缺少 $key');
    }
    return result;
  }

  List<String> _stringList(Object? value) => jsonStringArray(value);
}
