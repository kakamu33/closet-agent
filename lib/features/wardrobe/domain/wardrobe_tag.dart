class WardrobeTag {
  const WardrobeTag({
    required this.id,
    required this.name,
    this.parentId,
    required this.sortOrder,
  });

  static const maxNameLength = 20;
  static const maxPrimaryTagCount = 10;
  static const maxSecondaryTagCount = 15;

  final String id;
  final String name;
  final String? parentId;
  final int sortOrder;

  bool get isPrimary => parentId == null;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'parent_id': parentId,
        'sort_order': sortOrder,
      };

  factory WardrobeTag.fromMap(Map<String, Object?> map) => WardrobeTag(
        id: map['id']! as String,
        name: map['name']! as String,
        parentId: map['parent_id'] as String?,
        sortOrder: map['sort_order']! as int,
      );
}

/// 标准 UUID 格式（如 `3f6a7c1e-1a2b-4c3d-8e4f-000000000001`）的校验正则。
///
/// 用于识别本地缓存中是否残留旧版本代码写入的非法标签 id（例如历史上
/// 默认标签曾用过 `tops`、`outfit_daily` 这类字符串作为 id，而云端
/// `wardrobe_tags`/`outfit_tags` 表的 `id` 字段是 `uuid` 类型）。这类脏
/// 数据留在本地缓存里不会立刻报错，但一旦尝试同步到云端（包括仅仅是
/// 批量保存时把它当作 `existingTags` 之一）就会触发
/// `invalid input syntax for type uuid` 而失败。
final _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool isValidTagId(String id) => _uuidPattern.hasMatch(id);

/// 标签名称不合法或与已有标签冲突：
/// - 一级标签需在同一账号下全局唯一；
/// - 二级标签需在同一 [WardrobeTag.parentId] 下唯一，不同一级标签下可重名。
class TagValidationException implements Exception {
  const TagValidationException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 计算新标签应排在末尾时的 [WardrobeTag.sortOrder]。
///
/// 取 [existingTags] 中与 [parentId] 同级（一级标签比较 `parentId == null`，
/// 二级标签比较 `parentId` 是否相等）的标签里最大的 `sortOrder` 加一；
/// 没有同级标签时从 0 开始。
///
/// **不要用 `DateTime.now().microsecondsSinceEpoch` 之类的时间戳**：数据库
/// `sort_order` 字段是 PostgreSQL `integer`（上限约 21 亿），微秒时间戳
/// 约为 1.7×10^15，写入时会因整数溢出被数据库拒绝，导致新建标签的云端
/// 同步必然失败。
int nextTagSortOrder(List<WardrobeTag> existingTags, {String? parentId}) {
  final siblings = existingTags.where((tag) => tag.parentId == parentId);
  if (siblings.isEmpty) return 0;
  return siblings.map((tag) => tag.sortOrder).reduce((a, b) => a > b ? a : b) +
      1;
}

/// 校验标签名称长度，以及是否与 [existingTags] 中的其他标签重名。
///
/// 在保存（新增或改名）标签前调用；冲突或不合法时抛出
/// [TagValidationException]，调用方应捕获并提示用户，不应继续保存。
void validateTagName(WardrobeTag tag, List<WardrobeTag> existingTags) {
  final trimmed = tag.name.trim();
  if (trimmed.isEmpty) {
    throw const TagValidationException('标签名称不能为空');
  }
  if (trimmed.length > WardrobeTag.maxNameLength) {
    throw TagValidationException('标签名称最多 ${WardrobeTag.maxNameLength} 个字符');
  }
  final conflict = existingTags.any(
    (other) =>
        other.id != tag.id &&
        other.parentId == tag.parentId &&
        other.name.trim() == trimmed,
  );
  if (conflict) {
    throw TagValidationException(
      tag.isPrimary ? '已存在同名一级标签，请换一个名称' : '该标签下已存在同名细分标签，请换一个名称',
    );
  }
}

/// 新账号创建时预置的默认一级标签。
///
/// 这些标签与用户后续自建的标签在功能、权限上完全一致，均可自由改名或删除；
/// 只是为了避免新用户第一次打开衣橱时看到空标签列表而预先写入。
///
/// **必须使用合法的 UUID 字符串作为 id**：CloudBase 侧 `wardrobe_tags.id`
/// 字段是 `uuid` 类型，写入非 UUID 格式的字符串会被数据库直接拒绝，导致
/// 默认标签播种静默失败、新用户看不到任何标签。这里固定写死一批 UUID
/// （而不是每次随机生成），确保同一个逻辑标签在所有设备/多次注册间的
/// id 始终一致，避免重复创建。
const defaultWardrobeTags = <WardrobeTag>[
  WardrobeTag(id: '3f6a7c1e-1a2b-4c3d-8e4f-000000000001', name: '上装', sortOrder: 0),
  WardrobeTag(id: '3f6a7c1e-1a2b-4c3d-8e4f-000000000002', name: '下装', sortOrder: 1),
  WardrobeTag(id: '3f6a7c1e-1a2b-4c3d-8e4f-000000000003', name: '全身', sortOrder: 2),
  WardrobeTag(id: '3f6a7c1e-1a2b-4c3d-8e4f-000000000004', name: '鞋子', sortOrder: 3),
  WardrobeTag(id: '3f6a7c1e-1a2b-4c3d-8e4f-000000000005', name: '配饰', sortOrder: 4),
];

