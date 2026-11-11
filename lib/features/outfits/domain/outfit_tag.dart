import '../../wardrobe/domain/wardrobe_tag.dart';

/// 新账号创建时预置的默认搭配标签。
///
/// 只有一级标签（按季节分类），不预置二级标签；用户可以自行新增。
///
/// **必须使用合法的 UUID 字符串作为 id**：CloudBase 侧 `outfit_tags.id`
/// 字段是 `uuid` 类型，写入非 UUID 格式的字符串会被数据库直接拒绝。这里
/// 固定写死一批 UUID（而不是每次随机生成），确保同一个逻辑标签在所有
/// 设备/多次注册间的 id 始终一致，避免重复创建。
const defaultOutfitTags = <WardrobeTag>[
  WardrobeTag(
    id: '3f6a7c1e-2b3c-4d5e-9f60-000000000001',
    name: '春季',
    sortOrder: 0,
  ),
  WardrobeTag(
    id: '3f6a7c1e-2b3c-4d5e-9f60-000000000002',
    name: '夏季',
    sortOrder: 1,
  ),
  WardrobeTag(
    id: '3f6a7c1e-2b3c-4d5e-9f60-000000000003',
    name: '秋季',
    sortOrder: 2,
  ),
  WardrobeTag(
    id: '3f6a7c1e-2b3c-4d5e-9f60-000000000004',
    name: '冬季',
    sortOrder: 3,
  ),
];
