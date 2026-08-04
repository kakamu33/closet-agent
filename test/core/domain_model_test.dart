import 'package:diexu/features/outfits/domain/outfit.dart';
import 'package:diexu/features/wardrobe/domain/wardrobe_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('衣橱单品可完成数据库映射往返', () {
    final item = WardrobeItem(
      id: 'item-1',
      name: '羊绒大衣',
      category: ItemCategory.outerwear,
      brand: '叠序',
      color: '驼色',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

    final restored = WardrobeItem.fromMap(item.toMap());
    expect(restored.id, item.id);
    expect(restored.name, item.name);
    expect(restored.category, ItemCategory.outerwear);
    expect(restored.createdAt, item.createdAt);
  });

  test('搭配成员区分衣橱链接与临时单品', () {
    const linked = OutfitEntry(itemId: 'item-1', name: '羊绒大衣');
    const temporary = OutfitEntry(name: '复古胸针');

    expect(linked.isLinked, isTrue);
    expect(temporary.isLinked, isFalse);
  });
}
