import 'dart:convert';
import 'browser_storage.dart';

import '../../features/outfits/domain/outfit.dart';
import '../../features/outfits/domain/outfit_tag.dart';
import '../../features/settings/domain/user_profile.dart';
import '../../features/wardrobe/domain/wardrobe_canvas_layout.dart';
import '../../features/wardrobe/domain/wardrobe_canvas_region.dart';
import '../../features/wardrobe/domain/wardrobe_item.dart';
import '../../features/wardrobe/domain/wardrobe_tag.dart';
import '../time_utils.dart';
import '../sync/sync_collection.dart';
import '../sync/storage_coordinator.dart';

class AppDatabase implements SyncJournal, SyncCoordinator {
  AppDatabase({this.userId});
  final String? userId;
  late final _coordinator = StorageCoordinator(userId ?? 'legacy');
  @override
  Future<T> runLocal<T>(Future<T> Function() action) =>
      _coordinator.local(action);
  @override
  Future<T> runSync<T>(String collection, Future<T> Function() action) =>
      _coordinator.sync(collection, action);

  String _scope(String key) =>
      userId == null ? key : '$key.${base64Url.encode(utf8.encode(userId!))}';

  @override
  Future<Map<String, Object?>?> readSyncState(String collection) async {
    final raw = browserStorage[_scope('diexu.sync.$collection')];
    return raw == null
        ? null
        : Map<String, Object?>.from(jsonDecode(raw) as Map);
  }

  @override
  Future<void> writeSyncState(
    String collection,
    Map<String, Object?> state,
  ) async {
    browserStorage[_scope('diexu.sync.$collection')] = jsonEncode(state);
  }

  Future<void> acknowledgeVersions(
    String collection,
    Map<String, int> versions,
  ) async {
    final key = switch (collection) {
      'items' => _itemsKey,
      'outfits' => _outfitsKey,
      'wardrobe_tags' => _tagsKey,
      'outfit_tags' => _outfitTagsKey,
      _ => throw ArgumentError('Invalid collection'),
    };
    final values = _readList(key);
    for (final row in values) {
      if (versions[row['id']] case final version?) {
        row['sync_version'] = version;
      }
    }
    _writeList(key, values);
  }

  static const _itemsKey = 'diexu.wardrobe_items';
  static const _outfitsKey = 'diexu.outfits';
  static const _tagsKey = 'diexu.wardrobe_tags';
  static const _profileKey = 'diexu.user_profile';
  static const _outfitTagsKey = 'diexu.outfit_tags';
  static const _canvasLayoutsKey = 'diexu.wardrobe_canvas_layouts';
  static const _canvasShowNamesKey = 'diexu.wardrobe_canvas_show_names';
  static const _canvasRegionsKey = 'diexu.wardrobe_canvas_regions';

  Future<bool> hasLegacyDataForImport() async {
    if (userId == null || await readSyncState('legacy_import') != null) {
      return false;
    }
    final owner = browserStorage['diexu.legacy_owner'];
    if (owner != null && owner != userId && owner != 'signed-out') return false;
    return [
      _itemsKey,
      _outfitsKey,
    ].any((key) => (browserStorage[key] ?? '[]') != '[]');
  }

  Future<void> importLegacyData({bool confirmed = false}) => StorageCoordinator(
    'legacy-import',
  ).local(() => runLocal(() => _importLegacyData(confirmed)));
  Future<void> _importLegacyData(bool confirmed) async {
    if (userId == null || await readSyncState('legacy_import') != null) return;
    final owner = browserStorage['diexu.legacy_owner'];
    if (owner != null &&
        owner != userId &&
        !(confirmed && owner == 'signed-out')) {
      return;
    }
    if (owner == null && !confirmed) return;
    browserStorage['diexu.legacy_owner'] = userId!;
    for (final key in [
      _itemsKey,
      _outfitsKey,
      _tagsKey,
      _profileKey,
      _outfitTagsKey,
      _canvasLayoutsKey,
      _canvasShowNamesKey,
      _canvasRegionsKey,
    ]) {
      final value = browserStorage[key];
      if (value == null) continue;
      final existing = browserStorage[_scope(key)];
      if (existing == null) {
        browserStorage[_scope(key)] = value;
      } else if (key != _profileKey && key != _canvasShowNamesKey) {
        final current = (jsonDecode(existing) as List).cast<Map>();
        final ids = current.map((row) => row['id'] ?? row['item_id']).toSet();
        final incoming = (jsonDecode(value) as List).cast<Map>();
        browserStorage[_scope(key)] = jsonEncode([
          ...current,
          ...incoming.where(
            (row) => !ids.contains(row['id'] ?? row['item_id']),
          ),
        ]);
      }
    }
    for (final collection in [
      'items',
      'outfits',
      'wardrobe_tags',
      'outfit_tags',
    ]) {
      final old = browserStorage['diexu.sync.$collection'];
      final existing = await readSyncState(collection) ?? {};
      final prior = old == null ? <String, Object?>{} : jsonDecode(old) as Map;
      await writeSyncState(collection, {
        ...existing,
        'protocol': 1,
        'pending': [
          ...?existing['pending'] as List?,
          ...?prior['pending'] as List?,
        ],
      });
    }
    await writeSyncState('legacy_import', {'done': true});
  }

  Future<UserProfile> profile() async {
    final raw = browserStorage[_scope(_profileKey)];
    if (raw == null || raw.isEmpty) {
      await saveProfile(UserProfile.defaults);
      return UserProfile.defaults;
    }
    try {
      return UserProfile.fromMap(
        Map<String, Object?>.from(jsonDecode(raw) as Map),
      );
    } on FormatException {
      throw StateError('本机资料无法解析，原始内容已保留');
    }
  }

  /// 清除浏览器内的业务缓存；不会触及 CloudBase 的远端数据或登录令牌。
  Future<void> clearLocalData() async {
    for (final key in const [
      'diexu.sync.references',
      'diexu.sync.legacy_import',
      'diexu.sync.items',
      'diexu.sync.outfits',
      'diexu.sync.wardrobe_tags',
      'diexu.sync.outfit_tags',
      _itemsKey,
      _outfitsKey,
      _tagsKey,
      _profileKey,
      _outfitTagsKey,
      _canvasLayoutsKey,
      _canvasShowNamesKey,
      _canvasRegionsKey,
    ]) {
      browserStorage.remove(_scope(key));
    }
  }

  Future<void> saveProfile(UserProfile profile) async {
    browserStorage[_scope(_profileKey)] = jsonEncode(profile.toMap());
  }

  Future<List<WardrobeItem>> items() async =>
      _readList(_itemsKey).map(WardrobeItem.fromMap).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// 用云端快照替换浏览器内的衣物缓存，防止不同账号之间的数据混合。
  Future<void> replaceItems(List<WardrobeItem> items) async {
    _writeList(_itemsKey, items.map((item) => item.toMap()).toList());
    final ids = items.map((item) => item.id).toSet();
    _writeList(
      _canvasLayoutsKey,
      _readList(
        _canvasLayoutsKey,
      ).where((layout) => ids.contains(layout['item_id'])).toList(),
    );
  }

  Future<void> saveItem(WardrobeItem item) async {
    final values = _readList(_itemsKey);
    final index = values.indexWhere((value) => value['id'] == item.id);
    if (index == -1) {
      values.add(item.toMap());
    } else {
      values[index] = item.toMap();
    }
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
    if (index == -1) {
      values.add(region.toMap());
    } else {
      values[index] = region.toMap();
    }
    _writeList(_canvasRegionsKey, values);
  }

  Future<void> deleteCanvasRegion(String id) async {
    final values = _readList(_canvasRegionsKey)
      ..removeWhere((value) => value['id'] == id);
    _writeList(_canvasRegionsKey, values);
  }

  Future<bool> canvasShowNames() async =>
      browserStorage[_scope(_canvasShowNamesKey)] != 'false';

  Future<void> saveCanvasShowNames(bool showNames) async {
    browserStorage[_scope(_canvasShowNamesKey)] = showNames.toString();
  }

  Future<List<WardrobeCanvasLayout>> canvasLayouts() async =>
      _readList(_canvasLayoutsKey).map(WardrobeCanvasLayout.fromMap).toList();

  Future<void> saveCanvasLayout(WardrobeCanvasLayout layout) async {
    final values = _readList(_canvasLayoutsKey);
    final index = values.indexWhere(
      (value) => value['item_id'] == layout.itemId,
    );
    if (index == -1) {
      values.add(layout.toMap());
    } else {
      values[index] = layout.toMap();
    }
    _writeList(_canvasLayoutsKey, values);
  }

  Future<List<WardrobeTag>> tags() async {
    var values = _readList(_tagsKey);
    var changed = false;
    // 清理旧版本代码遗留的非法 id（历史上默认标签用过 'tops' 这类字符串，
    // 而云端 wardrobe_tags.id 是 uuid 类型）；留在本地不会立刻报错，但
    // 一旦被当成 existingTags 之一参与云端同步就会导致
    // invalid input syntax for type uuid 报错。
    final beforeCount = values.length;
    values = values
        .where((value) => isValidTagId(value['id'] as String? ?? ''))
        .toList();
    if (values.length != beforeCount) changed = true;
    if (userId == null &&
        values.isEmpty &&
        !browserStorage.containsKey(_scope(_tagsKey))) {
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
    if (index == -1) {
      values.add(tag.toMap());
    } else {
      values[index] = tag.toMap();
    }
    _writeList(_tagsKey, values);
  }

  Future<void> reorderTags(List<WardrobeTag> tags) async {
    final values = _readList(_tagsKey);
    for (var index = 0; index < tags.length; index++) {
      final valueIndex = values.indexWhere(
        (value) => value['id'] == tags[index].id,
      );
      if (valueIndex != -1) {
        values[valueIndex]['sort_order'] = index;
        values[valueIndex]['sync_version'] = tags[index].syncVersion;
      }
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
    var values = _readList(_outfitTagsKey);
    var changed = false;
    // 清理旧版本代码遗留的非法 id（历史上默认搭配标签用过 'outfit_daily'
    // 这类字符串，而云端 outfit_tags.id 是 uuid 类型）；留在本地不会立刻
    // 报错，但一旦被当成 existingTags 之一参与云端同步就会导致
    // invalid input syntax for type uuid 报错。
    final beforeCount = values.length;
    values = values
        .where((value) => isValidTagId(value['id'] as String? ?? ''))
        .toList();
    if (values.length != beforeCount) changed = true;
    if (userId == null &&
        values.isEmpty &&
        !browserStorage.containsKey(_scope(_outfitTagsKey))) {
      values.addAll(defaultOutfitTags.map((tag) => tag.toMap()));
      changed = true;
    }
    if (changed) _writeList(_outfitTagsKey, values);
    return values.map(WardrobeTag.fromMap).toList()..sort(
      (a, b) => a.isPrimary == b.isPrimary
          ? a.sortOrder.compareTo(b.sortOrder)
          : (a.isPrimary ? -1 : 1),
    );
  }

  /// 用云端快照替换浏览器内的搭配标签缓存。
  Future<void> replaceOutfitTags(List<WardrobeTag> tags) async {
    _writeList(_outfitTagsKey, tags.map((tag) => tag.toMap()).toList());
  }

  Future<void> saveOutfitTag(WardrobeTag tag) async {
    final values = _readList(_outfitTagsKey);
    final index = values.indexWhere((value) => value['id'] == tag.id);
    if (index == -1) {
      values.add(tag.toMap());
    } else {
      values[index] = tag.toMap();
    }
    _writeList(_outfitTagsKey, values);
  }

  Future<void> reorderOutfitTags(List<WardrobeTag> tags) async {
    final values = _readList(_outfitTagsKey);
    for (var index = 0; index < tags.length; index++) {
      final valueIndex = values.indexWhere(
        (value) => value['id'] == tags[index].id,
      );
      if (valueIndex != -1) {
        values[valueIndex]['sort_order'] = index;
        values[valueIndex]['sync_version'] = tags[index].syncVersion;
      }
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
    final index = values.indexWhere((value) => value['id'] == outfit.id);
    if (index == -1) {
      values.add(_outfitToJson(outfit));
    } else {
      values[index] = _outfitToJson(outfit);
    }
    _writeList(_outfitsKey, values);
  }

  /// 用云端快照替换浏览器内的搭配缓存，防止不同账号之间的数据混合。
  Future<void> replaceOutfits(List<Outfit> outfits) async {
    _writeList(_outfitsKey, outfits.map(_outfitToJson).toList());
  }

  Future<void> deleteOutfit(String id) async {
    final values = _readList(_outfitsKey)
      ..removeWhere((outfit) => outfit['id'] == id);
    _writeList(_outfitsKey, values);
  }

  List<Map<String, Object?>> _readList(String key) {
    final value = browserStorage[_scope(key)];
    if (value == null || value.isEmpty) return <Map<String, Object?>>[];
    try {
      return (jsonDecode(value) as List)
          .map((item) => Map<String, Object?>.from(item as Map))
          .toList();
    } on FormatException {
      throw StateError('本机数据无法解析，原始内容已保留');
    }
  }

  void _writeList(String key, List<Map<String, Object?>> values) =>
      browserStorage[_scope(key)] = jsonEncode(values);
  Map<String, Object?> _outfitToJson(Outfit outfit) => {
    'id': outfit.id,
    'sync_version': outfit.syncVersion,
    'name': outfit.name,
    'occasion': outfit.occasion,
    'season': outfit.season,
    'tags_json': jsonEncode(outfit.tags),
    'cover_path': outfit.photos.isEmpty ? null : outfit.photos.first,
    'cover_paths_json': jsonEncode(outfit.photos),
    'notes': outfit.notes,
    'created_at': toTimestamp(outfit.createdAt),
    'updated_at': toTimestamp(outfit.updatedAt),
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

  List<String> _coverPaths(Map<String, Object?> data) {
    final raw = data['cover_paths_json'] as String?;
    if (raw != null && raw.isNotEmpty) {
      return (jsonDecode(raw) as List).cast<String>();
    }
    return <String>[if (data['cover_path'] case final String path) path];
  }

  Outfit _outfitFromJson(Map<String, Object?> data) => Outfit(
    id: data['id']! as String,
    syncVersion: (data['sync_version'] as num?)?.toInt() ?? 0,
    name: data['name']! as String,
    occasion: data['occasion']! as String,
    season: data['season']! as String,
    tags: (jsonDecode(data['tags_json']! as String) as List).cast<String>(),
    coverPath: data['cover_path'] as String?,
    coverPaths: _coverPaths(data),
    notes: data['notes'] as String?,
    createdAt: parseTimestamp(data['created_at'])!,
    updatedAt:
        parseTimestamp(data['updated_at']) ??
        parseTimestamp(data['created_at'])!,
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
