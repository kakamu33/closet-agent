import '../../wardrobe/domain/wardrobe_tag.dart';

const defaultOutfitTags = <WardrobeTag>[
  WardrobeTag(id: 'outfit_daily', name: '日常', sortOrder: 0),
  WardrobeTag(id: 'outfit_commute', name: '通勤', sortOrder: 1),
  WardrobeTag(id: 'outfit_date', name: '约会', sortOrder: 2),
  WardrobeTag(id: 'outfit_travel', name: '旅行', sortOrder: 3),
  WardrobeTag(id: 'outfit_daily_casual', name: '休闲', parentId: 'outfit_daily', sortOrder: 0),
  WardrobeTag(id: 'outfit_daily_weekend', name: '周末', parentId: 'outfit_daily', sortOrder: 1),
  WardrobeTag(id: 'outfit_commute_simple', name: '简约', parentId: 'outfit_commute', sortOrder: 0),
  WardrobeTag(id: 'outfit_date_gentle', name: '温柔', parentId: 'outfit_date', sortOrder: 0),
  WardrobeTag(id: 'outfit_travel_comfy', name: '舒适', parentId: 'outfit_travel', sortOrder: 0),
];

