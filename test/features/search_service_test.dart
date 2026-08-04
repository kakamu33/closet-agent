import 'package:diexu/features/outfits/domain/outfit.dart';
import 'package:diexu/features/search/domain/search_service.dart';
import 'package:diexu/features/wardrobe/domain/wardrobe_item.dart';
import 'package:diexu/features/wardrobe/domain/wardrobe_tag.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 1, 1);
  WardrobeItem item({
    required String id,
    required String name,
    List<String> tagIds = const [],
    String? brand,
    String? color,
    String? notes,
  }) => WardrobeItem(
    id: id,
    name: name,
    category: ItemCategory.tops,
    tagIds: tagIds,
    brand: brand,
    color: color,
    notes: notes,
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  Outfit outfit({required String id, required String name, required List<OutfitEntry> entries, List<String> tags = const []}) => Outfit(
    id: id,
    name: name,
    occasion: '',
    season: '',
    tags: tags,
    entries: entries,
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  final wardrobeTags = const [
    WardrobeTag(id: 'tops', name: '上装', sortOrder: 0),
    WardrobeTag(id: 'full_body', name: '全身', sortOrder: 1),
  ];
  final outfitTags = const [WardrobeTag(id: 'daily', name: '日常', sortOrder: 0)];
  final items = [
    item(id: 'item-1', name: '测试单品1', tagIds: const ['full_body', 'tops'], brand: 'zoom'),
    item(id: 'item-2', name: '单品222111', tagIds: const ['tops'], notes: 'zoom 纪念'),
    item(id: 'item-3', name: '单品3331', tagIds: const ['tops']),
  ];
  final outfits = [
    outfit(id: 'outfit-11', name: '搭配11', entries: const [OutfitEntry(itemId: 'item-2', name: '单品222111')]),
    outfit(id: 'outfit-22', name: '搭配22', entries: const [OutfitEntry(name: '黑色上衣')], tags: const ['tops']),
  ];

  SearchResults search(String query) => SearchService.search(
    query: query,
    items: items,
    outfits: outfits,
    wardrobeTags: wardrobeTags,
    outfitTags: outfitTags,
  );

  test('case1: 搜索全召回带全身标签的测试单品1', () {
    expect(search('全').items.map((item) => item.name), contains('测试单品1'));
  });

  test('case2: 搜索1召回三个单品及搭配11', () {
    final result = search('1');
    expect(result.items, hasLength(3));
    expect(result.outfits.map((outfit) => outfit.name), contains('搭配11'));
  });

  test('case3: 搜索zoom召回两个单品及使用该单品的搭配11', () {
    final result = search('zoom');
    expect(result.items.map((item) => item.name), containsAll(['单品222111', '测试单品1']));
    expect(result.outfits.map((outfit) => outfit.name), contains('搭配11'));
  });

  test('case4: 搜索黑色召回含临时单品黑色上衣的搭配22', () {
    expect(search('黑色').outfits.map((outfit) => outfit.name), contains('搭配22'));
  });

  test('case5: 搜索上装召回三个单品及携带上装单品的搭配', () {
    final result = search('上装');
    expect(result.items, hasLength(3));
    expect(result.outfits.map((outfit) => outfit.name), containsAll(['搭配11', '搭配22']));
  });
}

