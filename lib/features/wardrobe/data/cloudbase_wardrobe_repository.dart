import '../../../core/cloudbase/cloudbase_client.dart';
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

  Future<List<WardrobeItem>> fetchItems({required String accessToken}) async {
    final response = await _client.request(
      'GET',
      '/v1/rdb/rest/wardrobe_items',
      accessToken: accessToken,
      queryParameters: const {
        'select': '*',
        'deleted_at': 'is.null',
        'order': 'updated_at.desc',
      },
    );
    if (response is! List) {
      throw const CloudBaseException('云端衣物数据格式不正确');
    }
    return response.map((value) {
      if (value is! Map) {
        throw const CloudBaseException('云端衣物数据格式不正确');
      }
      return _itemFromCloud(Map<String, Object?>.from(value));
    }).toList();
  }

  Future<void> saveItem({
    required AuthUser user,
    required String accessToken,
    required WardrobeItem item,
  }) async {
    await ensureProfile(user: user, accessToken: accessToken);
    await _client.request(
      'POST',
      '/v1/rdb/rest/wardrobe_items',
      accessToken: accessToken,
      body: {
        'id': item.id,
        'user_id': user.id,
        'name': item.name,
        'image_paths_json': item.imagePaths,
        'tag_ids_json': item.tagIds,
        'brand': item.brand,
        'color': item.color,
        'notes': item.notes,
        'currency': item.currency,
        'price': item.price,
        'created_at': item.createdAt.toUtc().toIso8601String(),
        'updated_at': item.updatedAt.toUtc().toIso8601String(),
        'deleted_at': null,
      },
      extraHeaders: const {
        'Prefer': 'resolution=merge-duplicates,return=minimal',
      },
    );
  }

  Future<void> deleteItem({
    required String accessToken,
    required String itemId,
  }) => _client.request(
    'DELETE',
    '/v1/rdb/rest/wardrobe_items',
    accessToken: accessToken,
    queryParameters: {'id': 'eq.$itemId'},
  );

  Future<List<WardrobeTag>> fetchTags({required String accessToken}) async {
    final response = await _client.request(
      'GET',
      '/v1/rdb/rest/wardrobe_tags',
      accessToken: accessToken,
      queryParameters: const {
        'select': '*',
        'order': 'parent_id.asc,sort_order.asc,name.asc',
      },
    );
    if (response is! List) {
      throw const CloudBaseException('云端标签数据格式不正确');
    }
    return response.map((value) {
      if (value is! Map) {
        throw const CloudBaseException('云端标签数据格式不正确');
      }
      final tag = Map<String, Object?>.from(value);
      final sortOrder = tag['sort_order'];
      if (sortOrder is! num) {
        throw const CloudBaseException('云端标签缺少排序信息');
      }
      return WardrobeTag(
        id: _requiredString(tag, 'id'),
        name: _requiredString(tag, 'name'),
        parentId: tag['parent_id'] as String?,
        sortOrder: sortOrder.toInt(),
      );
    }).toList();
  }

  /// 保存（新增或改名）一个标签。
  ///
  /// [existingTags] 是当前账号下已有的全部标签（用于做同名校验）：
  /// - 一级标签：全局唯一，不能与其他一级标签同名；
  /// - 二级标签：同一 [WardrobeTag.parentId] 下唯一，不同父标签可以重名。
  /// 冲突或不合法时抛出 [TagValidationException]，调用方应捕获并提示用户，不应继续保存。
  Future<void> saveTag({
    required AuthUser user,
    required String accessToken,
    required WardrobeTag tag,
    required List<WardrobeTag> existingTags,
  }) async {
    validateTagName(tag, existingTags);
    await ensureProfile(user: user, accessToken: accessToken);
    try {
      await _client.request(
        'POST',
        '/v1/rdb/rest/wardrobe_tags',
        accessToken: accessToken,
        body: {
          'id': tag.id,
          'user_id': user.id,
          'name': tag.name,
          'parent_id': tag.parentId,
          'sort_order': tag.sortOrder,
        },
        extraHeaders: const {
          'Prefer': 'resolution=merge-duplicates,return=minimal',
        },
      );
    } on CloudBaseException catch (error) {
      if (_isUniqueViolation(error)) {
        throw TagValidationException(
          tag.isPrimary ? '已存在同名一级标签' : '该标签下已存在同名细分标签',
        );
      }
      rethrow;
    }
  }

  Future<void> deleteTag({
    required String accessToken,
    required String tagId,
  }) => _client.request(
    'DELETE',
    '/v1/rdb/rest/wardrobe_tags',
    accessToken: accessToken,
    queryParameters: {'id': 'eq.$tagId'},
  );

  bool _isUniqueViolation(CloudBaseException error) =>
      error.statusCode == 409 || error.message.contains('duplicate key');

  WardrobeItem _itemFromCloud(Map<String, Object?> value) {
    final createdAt = value['created_at'];
    if (createdAt is! String) {
      throw const CloudBaseException('云端衣物缺少必要字段');
    }
    return WardrobeItem(
      id: _requiredString(value, 'id'),
      name: _requiredString(value, 'name'),
      imagePaths: _stringList(value['image_paths_json']),
      tagIds: _stringList(value['tag_ids_json']),
      brand: value['brand'] as String?,
      color: value['color'] as String?,
      notes: value['notes'] as String?,
      currency: value['currency'] as String? ?? 'CNY',
      price: (value['price'] as num?)?.toDouble(),
      createdAt: DateTime.parse(createdAt),
      updatedAt:
          DateTime.tryParse(value['updated_at'] as String? ?? '') ??
          DateTime.parse(createdAt),
    );
  }

  String _requiredString(Map<String, Object?> value, String key) {
    final result = value[key];
    if (result is! String || result.isEmpty) {
      throw CloudBaseException('云端衣物缺少 $key');
    }
    return result;
  }

  List<String> _stringList(Object? value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList();
  }
}
