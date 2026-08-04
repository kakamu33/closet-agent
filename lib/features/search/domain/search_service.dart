import '../../outfits/domain/outfit.dart';
import '../../wardrobe/domain/wardrobe_item.dart';
import '../../wardrobe/domain/wardrobe_tag.dart';

class SearchResults {
  const SearchResults({required this.items, required this.outfits});

  final List<WardrobeItem> items;
  final List<Outfit> outfits;
}

class SearchService {
  const SearchService._();

  static SearchResults search({
    required String query,
    required List<WardrobeItem> items,
    required List<Outfit> outfits,
    required List<WardrobeTag> wardrobeTags,
    required List<WardrobeTag> outfitTags,
  }) {
    final keyword = _normalize(query);
    if (keyword.isEmpty) return const SearchResults(items: [], outfits: []);

    final itemById = {for (final item in items) item.id: item};
    final wardrobeTagNames = {for (final tag in wardrobeTags) tag.id: tag.name};
    final outfitTagNames = {for (final tag in outfitTags) tag.id: tag.name};

    final matchedItems = items.where((item) => _contains(keyword, _itemText(item, wardrobeTagNames))).toList();
    final matchedOutfits = outfits.where((outfit) {
      final ownText = [
        outfit.name,
        outfit.notes,
        ...outfit.tags.map((id) => outfitTagNames[id] ?? wardrobeTagNames[id]),
      ].whereType<String>().join(' ');
      final entryText = outfit.entries.map((entry) {
        final linkedItem = entry.itemId == null ? null : itemById[entry.itemId];
        return linkedItem == null ? entry.name : '${entry.name} ${_itemText(linkedItem, wardrobeTagNames)}';
      }).join(' ');
      return _contains(keyword, '$ownText $entryText');
    }).toList();

    return SearchResults(items: matchedItems, outfits: matchedOutfits);
  }

  static String _itemText(WardrobeItem item, Map<String, String> tagNames) => [
    item.name,
    item.brand,
    item.color,
    item.notes,
    ...item.tagIds.map((id) => tagNames[id]),
  ].whereType<String>().join(' ');

  static bool _contains(String keyword, String text) => _normalize(text).contains(keyword);

  static String _normalize(String value) => value.trim().toLowerCase();
}

