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

/// 标签名称不合法或与已有标签冲突：
/// - 一级标签需在同一账号下全局唯一；
/// - 二级标签需在同一 [WardrobeTag.parentId] 下唯一，不同一级标签下可重名。
class TagValidationException implements Exception {
  const TagValidationException(this.message);

  final String message;

  @override
  String toString() => message;
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
const defaultWardrobeTags = <WardrobeTag>[
  WardrobeTag(id: 'tops', name: '上装', sortOrder: 0),
  WardrobeTag(id: 'bottoms', name: '下装', sortOrder: 1),
  WardrobeTag(id: 'full_body', name: '全身', sortOrder: 2),
  WardrobeTag(id: 'shoes', name: '鞋子', sortOrder: 3),
  WardrobeTag(id: 'accessories', name: '配饰', sortOrder: 4),
];

