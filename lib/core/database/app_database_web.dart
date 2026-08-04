import 'dart:convert';
import 'dart:html' as html;

import '../../features/outfits/domain/outfit.dart';
import '../../features/outfits/domain/outfit_tag.dart';
import '../../features/settings/domain/user_profile.dart';
import '../../features/wardrobe/domain/wardrobe_canvas_layout.dart';
import '../../features/wardrobe/domain/wardrobe_canvas_region.dart';
import '../../features/wardrobe/domain/wardrobe_item.dart';
import '../../features/wardrobe/domain/wardrobe_tag.dart';

class AppDatabase {
  static const _itemsKey = 'diexu.wardrobe_items';
  static const _outfitsKey = 'diexu.outfits';
  static const _tagsKey = 'diexu.wardrobe_tags';
  static const _profileKey = 'diexu.user_profile';
  static const _outfitTagsKey = 'diexu.outfit_tags';
  static const _canvasLayoutsKey = 'diexu.wardrobe_canvas_layouts';
  static const _canvasShowNamesKey = 'diexu.wardrobe_canvas_show_names';
  static const _canvasRegionsKey = 'diexu.wardrobe_canvas_regions';

  Future<UserProfile> profile() async {
    final raw = html.window.localStorage[_profileKey];
    if (raw == null || raw.isEmpty) {
      await saveProfile(UserProfile.defaults);
      return UserProfile.defaults;
    }
    try {
      return UserProfile.fromMap(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } on FormatException {
      await saveProfile(UserProfile.defaults);
      return UserProfile.defaults;
    }
  }

  /// 清除浏览器内的业务缓存；不会触及 CloudBase 的远端数据或登录令牌。
  Future<void> clearLocalData() async {
    for (final key in const [
      _itemsKey,
      _outfitsKey,
      _tagsKey,
      _profileKey,
      _outfitTagsKey,
      _canvasLayoutsKey,
      _canvasShowNamesKey,
      _canvasRegionsKey,
    ]) {
      html.window.localStorage.remove(key);
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    html.window.localStorage[_profileKey] = jsonEncode(profile.toMap());
  }

  Future<List<WardrobeItem>> items() async =>
      _readList(_itemsKey).map(WardrobeItem.fromMap).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// 用云端快照替换浏览器内的衣物缓存，防止不同账号之间的数据混合。
  Future<void> replaceItems(List<WardrobeItem> items) async {
    _writeList(_itemsKey, items.map((item) => item.toMap()).toList());
    _writeList(_canvasLayoutsKey, <Map<String, Object?>>[]);
  }

  Future<void> saveItem(WardrobeItem item) async {
    final values = _readList(_itemsKey);
    final index = values.indexWhere((value) => value['id'] == item.id);
    if (index == -1)
      values.add(item.toMap());
    else
      values[index] = item.toMap();
    _writeList(_itemsKey, values);
  }

  Future<void> deleteItem(String id) async {
    final items = _readList(_itemsKey)..removeWhere((item) => item['id'] == id);
    _writeList(_itemsKey, items);
    final layouts = _readList(_canvasLayoutsKey)
      ..removeWhere((layout) => layout['item_id'] == id);
    _writeList(_canvasLayoutsKey, layouts);
    final outfits = _readList(_outfitsKey);
    for (final outfit in outfits) {
      final entries = (outfit['entries'] as List? ?? <Object?>[])
          .cast<Map<String, Object?>>();
      for (final entry in entries) {
        if (entry['item_id'] == id) entry['item_id'] = null;
      }
    }
    _writeList(_outfitsKey, outfits);
  }

  Future<List<WardrobeCanvasRegion>> canvasRegions() async =>
      _readList(_canvasRegionsKey).map(WardrobeCanvasRegion.fromMap).toList();

  Future<void> saveCanvasRegion(WardrobeCanvasRegion region) async {
    final values = _readList(_canvasRegionsKey);
    final index = values.indexWhere((value) => value['id'] == region.id);
    if (index == -1)
      values.add(region.toMap());
    else
      values[index] = region.toMap();
    _writeList(_canvasRegionsKey, values);
  }

  Future<void> deleteCanvasRegion(String id) async {
    final values = _readList(_canvasRegionsKey)
      ..removeWhere((value) => value['id'] == id);
    _writeList(_canvasRegionsKey, values);
  }

  Future<bool> canvasShowNames() async =>
      html.window.localStorage[_canvasShowNamesKey] != 'false';

  Future<void> saveCanvasShowNames(bool showNames) async {
    html.window.localStorage[_canvasShowNamesKey] = showNames.toString();
  }

  Future<List<WardrobeCanvasLayout>> canvasLayouts() async =>
      _readList(_canvasLayoutsKey).map(WardrobeCanvasLayout.fromMap).toList();

  Future<void> saveCanvasLayout(WardrobeCanvasLayout layout) async {
    final values = _readList(_canvasLayoutsKey);
    final index = values.indexWhere(
      (value) => value['item_id'] == layout.itemId,
    );
    if (index == -1)
      values.add(layout.toMap());
    else
      values[index] = layout.toMap();
    _writeList(_canvasLayoutsKey, values);
  }

  Future<List<WardrobeTag>> tags() async {
    final values = _readList(_tagsKey);
    var changed = false;
    if (values.isEmpty) {
      values.addAll(defaultWardrobeTags.map((tag) => tag.toMap()));
      changed = true;
    } else {
      final defaultsById = {for (final tag in defaultWardrobeTags) tag.id: tag};
      for (final value in values) {
        final defaultTag = defaultsById[value['id']];
        if (defaultTag != null &&
            (value['name'] as String? ?? '').trim().isEmpty) {
          value['name'] = defaultTag.name;
          changed = true;
        }
      }
    }
    if (changed) _writeList(_tagsKey, values);
    return values.map(WardrobeTag.fromMap).toList()..sort(
      (a, b) => a.isPrimary == b.isPrimary
          ? a.sortOrder.compareTo(b.sortOrder)
          : (a.isPrimary ? -1 : 1),
    );
  }

  /// 用云端快照替换浏览器内的标签缓存。
  Future<void> replaceTags(List<WardrobeTag> tags) async {
    _writeList(_tagsKey, tags.map((tag) => tag.toMap()).toList());
  }

  Future<void> saveTag(WardrobeTag tag) async {
    final values = _readList(_tagsKey);
    final index = values.indexWhere((value) => value['id'] == tag.id);
    if (index == -1)
      values.add(tag.toMap());
    else
      values[index] = tag.toMap();
    _writeList(_tagsKey, values);
  }

  Future<void> reorderTags(List<WardrobeTag> tags) async {
    final values = _readList(_tagsKey);
    for (var index = 0; index < tags.length; index++) {
      final valueIndex = values.indexWhere(
        (value) => value['id'] == tags[index].id,
      );
      if (valueIndex != -1) values[valueIndex]['sort_order'] = index;
    }
    _writeList(_tagsKey, values);
  }

  Future<void> deleteTag(String id) async {
    final tags = _readList(_tagsKey);
    final removed = tags
        .where((tag) => tag['id'] == id || tag['parent_id'] == id)
        .map((tag) => tag['id']! as String)
        .toSet();
    tags.removeWhere((tag) => removed.contains(tag['id']));
    _writeList(_tagsKey, tags);
    final items = _readList(_itemsKey);
    for (final item in items) {
      final raw = item['tag_ids_json'] as String?;
      if (raw == null || raw.isEmpty) continue;
      item['tag_ids_json'] = jsonEncode(
        (jsonDecode(raw) as List)
            .cast<String>()
            .where((tagId) => !removed.contains(tagId))
            .toList(),
      );
    }
    _writeList(_itemsKey, items);
  }

  Future<List<WardrobeTag>> outfitTags() async {
    final values = _readList(_outfitTagsKey);
    if (values.isEmpty) {
      values.addAll(defaultOutfitTags.map((tag) => tag.toMap()));
      _writeList(_outfitTagsKey, values);
    }
    return values.map(WardrobeTag.fromMap).toList()..sort(
      (a, b) => a.isPrimary == b.isPrimary
          ? a.sortOrder.compareTo(b.sortOrder)
          : (a.isPrimary ? -1 : 1),
    );
  }

  Future<void> saveOutfitTag(WardrobeTag tag) async {
    final values = _readList(_outfitTagsKey);
    final index = values.indexWhere((value) => value['id'] == tag.id);
    if (index == -1)
      values.add(tag.toMap());
    else
      values[index] = tag.toMap();
    _writeList(_outfitTagsKey, values);
  }

  Future<void> reorderOutfitTags(List<WardrobeTag> tags) async {
    final values = _readList(_outfitTagsKey);
    for (var index = 0; index < tags.length; index++) {
      final valueIndex = values.indexWhere(
        (value) => value['id'] == tags[index].id,
      );
      if (valueIndex != -1) values[valueIndex]['sort_order'] = index;
    }
    _writeList(_outfitTagsKey, values);
  }

  Future<void> deleteOutfitTag(String id) async {
    final tags = _readList(_outfitTagsKey);
    final removed = tags
        .where((tag) => tag['id'] == id || tag['parent_id'] == id)
        .map((tag) => tag['id']! as String)
        .toSet();
    tags.removeWhere((tag) => removed.contains(tag['id']));
    _writeList(_outfitTagsKey, tags);
    final outfits = _readList(_outfitsKey);
    for (final outfit in outfits) {
      outfit['tags_json'] = jsonEncode(
        (jsonDecode(outfit['tags_json']! as String) as List)
            .cast<String>()
            .where((tagId) => !removed.contains(tagId))
            .toList(),
      );
    }
    _writeList(_outfitsKey, outfits);
  }

  Future<List<Outfit>> outfits({String? itemId}) async {
    final values = _readList(_outfitsKey)
        .map(_outfitFromJson)
        .where(
          (outfit) =>
              itemId == null ||
              outfit.entries.any((entry) => entry.itemId == itemId),
        )
        .toList();
    values.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return values;
  }

  Future<void> saveOutfit(Outfit outfit) async {
    final values = _readList(_outfitsKey);
    final data = {
      'id': outfit.id,
      'name': outfit.name,
      'occasion': outfit.occasion,
      'season': outfit.season,
      'tags_json': jsonEncode(outfit.tags),
      'cover_path': outfit.photos.isEmpty ? null : outfit.photos.first,
      'cover_paths_json': jsonEncode(outfit.photos),
      'notes': outfit.notes,
      'created_at': outfit.createdAt.toIso8601String(),
      'updated_at': outfit.updatedAt.toIso8601String(),
      'entries': outfit.entries
          .map(
            (entry) => {
              'item_id': entry.itemId,
              'item_name': entry.name,
              'image_path': entry.imagePath,
            },
          )
          .toList(),
    };
    final index = values.indexWhere((value) => value['id'] == outfit.id);
    if (index == -1)
      values.add(data);
    else
      values[index] = data;
    _writeList(_outfitsKey, values);
  }

  Future<void> deleteOutfit(String id) async {
    final values = _readList(_outfitsKey)
      ..removeWhere((outfit) => outfit['id'] == id);
    _writeList(_outfitsKey, values);
  }

  List<Map<String, Object?>> _readList(String key) {
    final value = html.window.localStorage[key];
    if (value == null || value.isEmpty) return <Map<String, Object?>>[];
    try {
      return (jsonDecode(value) as List)
          .map((item) => Map<String, Object?>.from(item as Map))
          .toList();
    } on FormatException {
      html.window.localStorage.remove(key);
      return <Map<String, Object?>>[];
    }
  }

  void _writeList(String key, List<Map<String, Object?>> values) =>
      html.window.localStorage[key] = jsonEncode(values);
  List<String> _coverPaths(Map<String, Object?> data) {
    final raw = data['cover_paths_json'] as String?;
    if (raw != null && raw.isNotEmpty)
      return (jsonDecode(raw) as List).cast<String>();
    return <String>[if (data['cover_path'] case final String path) path];
  }

  Outfit _outfitFromJson(Map<String, Object?> data) => Outfit(
    id: data['id']! as String,
    name: data['name']! as String,
    occasion: data['occasion']! as String,
    season: data['season']! as String,
    tags: (jsonDecode(data['tags_json']! as String) as List).cast<String>(),
    coverPath: data['cover_path'] as String?,
    coverPaths: _coverPaths(data),
    notes: data['notes'] as String?,
    createdAt: DateTime.parse(data['created_at']! as String),
    updatedAt:
        DateTime.tryParse(data['updated_at'] as String? ?? '') ??
        DateTime.parse(data['created_at']! as String),
    entries: (data['entries'] as List? ?? <Object?>[])
        .map((entry) => Map<String, Object?>.from(entry as Map))
        .map(
          (entry) => OutfitEntry(
            itemId: entry['item_id'] as String?,
            name: entry['item_name']! as String,
            imagePath: entry['image_path'] as String?,
          ),
        )
        .toList(),
  );
}
