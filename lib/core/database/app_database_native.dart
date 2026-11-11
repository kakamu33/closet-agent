import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../../features/outfits/domain/outfit.dart';
import '../../features/outfits/domain/outfit_tag.dart';
import '../../features/settings/domain/user_profile.dart';
import '../../features/wardrobe/domain/wardrobe_canvas_layout.dart';
import '../../features/wardrobe/domain/wardrobe_canvas_region.dart';
import '../../features/wardrobe/domain/wardrobe_item.dart';
import '../../features/wardrobe/domain/wardrobe_tag.dart';
import '../time_utils.dart';
import '../sync/sync_collection.dart';
import 'database_factory.dart';

class AppDatabase implements SyncJournal {
  // Keep the injected database parameter public for adapters and tests.
  // ignore: prefer_initializing_formals
  AppDatabase({Database? database, this.userId}) : _database = database;

  final String? userId;
  Future<Database>? _opening;

  Database? _database;
  Future<Database> get instance async {
    if (_database != null) return _database!;
    try {
      return _database = await (_opening ??= _open());
    } catch (_) {
      _opening = null;
      rethrow;
    }
  }

  @override
  Future<Map<String, Object?>?> readSyncState(String collection) async {
    final rows = await (await instance).query(
      'sync_state',
      where: 'collection = ?',
      whereArgs: [collection],
    );
    return rows.isEmpty
        ? null
        : Map<String, Object?>.from(
            jsonDecode(rows.single['payload']! as String) as Map,
          );
  }

  @override
  Future<void> writeSyncState(
    String collection,
    Map<String, Object?> state,
  ) async {
    await (await instance).insert('sync_state', {
      'collection': collection,
      'payload': jsonEncode(state),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Only called for the authenticated session restored from the old app.
  /// Claiming records an owner before copying, so another account cannot import it.
  Future<void> importLegacyData() async {
    if (userId == null || await readSyncState('legacy_import') != null) return;
    final legacy = AppDatabase();
    if (!await databaseExists('${await getDatabasesPath()}/diexu.db')) {
      await writeSyncState('legacy_import', {'done': true});
      return;
    }
    final source = await legacy.instance;
    try {
      final owner = await legacy.readSyncState('legacy_owner');
      if (owner != null && owner['userId'] != userId) return;
      await legacy.writeSyncState('legacy_owner', {'userId': userId});
      final target = await instance;
      final tables = [
        'wardrobe_items',
        'wardrobe_tags',
        'outfits',
        'outfit_entries',
        'outfit_tags',
        'wardrobe_canvas_layouts',
        'wardrobe_canvas_regions',
        'wardrobe_canvas_preferences',
        'user_profile',
      ];
      final snapshots = <String, List<Map<String, Object?>>>{};
      for (final table in tables) {
        snapshots[table] = await source.query(table);
      }
      await target.transaction((txn) async {
        for (final table in tables) {
          for (final row in snapshots[table]!) {
            await txn.insert(
              table,
              row,
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
          }
        }
        await txn.insert('sync_state', {
          'collection': 'legacy_import',
          'payload': '{"done":true}',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      });
    } finally {
      await source.close();
    }
  }

  Future<void> _createSyncTable(DatabaseExecutor db) => db.execute(
    'CREATE TABLE IF NOT EXISTS sync_state(collection TEXT PRIMARY KEY, payload TEXT NOT NULL)',
  );

  Future<Database> _open() => openAppDatabase(
    userId == null
        ? 'diexu.db'
        : 'diexu_${base64Url.encode(utf8.encode(userId!))}.db',
    version: 18,
    onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
    onCreate: (db, version) async {
      await _createSyncTable(db);
      await _createCoreTables(db);
      await _createTagTables(db);
      await _createProfileTable(db);
      await _createOutfitTagTable(db);
      await _createCanvasLayoutTable(db);
      await _createCanvasPreferenceTable(db);
      await _createCanvasRegionTable(db);
      if (userId == null) {
        await _seedTags(db);
        await _seedOutfitTags(db);
      }
    },
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 18) await _createSyncTable(db);
      if (oldVersion < 2) {
        await db.execute(
          'ALTER TABLE wardrobe_items ADD COLUMN image_paths_json TEXT',
        );
      }
      if (oldVersion < 3) {
        await db.execute(
          'ALTER TABLE wardrobe_items ADD COLUMN tag_ids_json TEXT',
        );
        await _createTagTables(db);
        await _seedTags(db);
      }
      if (oldVersion < 4) {
        await _createProfileTable(db);
      }
      if (oldVersion < 5) {
        await _createOutfitTagTable(db);
        await _seedOutfitTags(db);
      }
      if (oldVersion < 8) {
        await db.execute(
          "ALTER TABLE wardrobe_items ADD COLUMN currency TEXT NOT NULL DEFAULT 'CNY'",
        );
        await db.execute('ALTER TABLE wardrobe_items ADD COLUMN price REAL');
        await db.execute(
          'ALTER TABLE wardrobe_items ADD COLUMN updated_at TEXT',
        );
        await db.execute('ALTER TABLE outfits ADD COLUMN updated_at TEXT');
        await db.execute(
          'UPDATE wardrobe_items SET updated_at = created_at WHERE updated_at IS NULL',
        );
        await db.execute(
          'UPDATE outfits SET updated_at = created_at WHERE updated_at IS NULL',
        );
      }
      if (oldVersion < 9) {
        await db.execute(
          'ALTER TABLE outfits ADD COLUMN cover_paths_json TEXT',
        );
      }
      if (oldVersion < 10) await _createCanvasLayoutTable(db);
      if (oldVersion < 11) {
        await db.execute(
          'ALTER TABLE wardrobe_canvas_layouts ADD COLUMN display_image_path TEXT',
        );
      }
      if (oldVersion < 12) await _createCanvasPreferenceTable(db);
      if (oldVersion < 13) await _createCanvasRegionTable(db);
      if (oldVersion < 14) {
        await db.execute(
          'ALTER TABLE wardrobe_canvas_regions ADD COLUMN color_value INTEGER NOT NULL DEFAULT 4284960932',
        );
        await db.execute(
          "ALTER TABLE wardrobe_canvas_regions ADD COLUMN shape TEXT NOT NULL DEFAULT 'rounded'",
        );
      }
      if (oldVersion < 15) {
        await db.execute(
          'ALTER TABLE wardrobe_canvas_layouts ADD COLUMN width REAL NOT NULL DEFAULT 138',
        );
        await db.execute(
          'ALTER TABLE wardrobe_canvas_layouts ADD COLUMN height REAL NOT NULL DEFAULT 174',
        );
        await db.execute(
          'ALTER TABLE wardrobe_canvas_layouts ADD COLUMN z_index INTEGER NOT NULL DEFAULT 0',
        );
      }
      if (oldVersion < 16) {
        await _dropCategoryColumn(db);
      }
      if (oldVersion < 17) {
        await _purgeLegacyTagIds(db);
        await _migrateTimestampColumns(db);
      }
    },
  );

  /// 把 `wardrobe_items`/`outfits` 的 `created_at`/`updated_at` 列从
  /// ISO8601 字符串迁移为毫秒级时间戳（`INTEGER`，UTC）。
  ///
  /// 统一使用时间戳而不是 `timestamptz`/ISO8601 字符串存储时间字段：一来
  /// 避免不同数据库驱动、不同展示工具对时区的呈现差异造成"时间看起来
  /// 不对"的困惑；二来数值比较、排序效率更高。SQLite 是弱类型数据库，
  /// 列本身不需要 `ALTER COLUMN TYPE`，只需要把已有的字符串值转换成数字
  /// 即可就地生效。
  Future<void> _migrateTimestampColumns(Database db) async {
    for (final spec in const [('wardrobe_items', 'id'), ('outfits', 'id')]) {
      final (table, idColumn) = spec;
      final rows = await db.query(
        table,
        columns: [idColumn, 'created_at', 'updated_at'],
      );
      for (final row in rows) {
        final createdAt = row['created_at'];
        final updatedAt = row['updated_at'];
        final values = <String, Object?>{};
        if (createdAt is String) {
          values['created_at'] =
              DateTime.tryParse(createdAt)?.toUtc().millisecondsSinceEpoch ??
              DateTime.now().toUtc().millisecondsSinceEpoch;
        }
        if (updatedAt is String) {
          values['updated_at'] =
              DateTime.tryParse(updatedAt)?.toUtc().millisecondsSinceEpoch ??
              values['created_at'] ??
              DateTime.now().toUtc().millisecondsSinceEpoch;
        }
        if (values.isEmpty) continue;
        await db.update(
          table,
          values,
          where: '$idColumn = ?',
          whereArgs: [row[idColumn]],
        );
      }
    }
  }

  /// 清理旧版本代码遗留的非法标签 id。
  ///
  /// 历史上默认标签曾用过 `tops`、`outfit_daily` 这类字符串作为 id，而云端
  /// `wardrobe_tags`/`outfit_tags` 表的 `id` 字段是 `uuid` 类型。这些脏数据
  /// 留在本机不会立刻报错，但一旦被当成 `existingTags` 之一参与云端同步，
  /// 会导致 `invalid input syntax for type uuid` 而使整批同步失败。
  /// 清理后如果两张标签表变空，会在下次 [tags]/[outfitTags] 调用时被
  /// [_seedTags]/[_seedOutfitTags] 重新用最新的默认标签填充。
  Future<void> _purgeLegacyTagIds(Database db) async {
    for (final table in const ['wardrobe_tags', 'outfit_tags']) {
      final rows = await db.query(table, columns: const ['id']);
      final invalidIds = rows
          .map((row) => row['id']! as String)
          .where((id) => !isValidTagId(id))
          .toList();
      if (invalidIds.isEmpty) continue;
      final placeholders = List.filled(invalidIds.length, '?').join(',');
      await db.delete(
        table,
        where: 'id IN ($placeholders) OR parent_id IN ($placeholders)',
        whereArgs: [...invalidIds, ...invalidIds],
      );
    }
  }

  /// 移除标签体系重构前遗留的 `wardrobe_items.category` 列。
  ///
  /// SQLite 老版本不支持 `ALTER TABLE ... DROP COLUMN`，因此用
  /// “新建表 -> 拷贝数据 -> 替换旧表”的方式重建 `wardrobe_items`。
  Future<void> _dropCategoryColumn(Database db) async {
    final layouts = await db.query('wardrobe_canvas_layouts');
    await db.execute('''CREATE TABLE wardrobe_items_new(
      id TEXT PRIMARY KEY, name TEXT NOT NULL,
      image_path TEXT, image_paths_json TEXT, tag_ids_json TEXT,
      brand TEXT, color TEXT, notes TEXT, currency TEXT NOT NULL DEFAULT 'CNY',
      price REAL, created_at TEXT NOT NULL, updated_at TEXT NOT NULL
    )''');
    await db.execute('''INSERT INTO wardrobe_items_new
      (id, name, image_path, image_paths_json, tag_ids_json, brand, color, notes, currency, price, created_at, updated_at)
      SELECT id, name, image_path, image_paths_json, tag_ids_json, brand, color, notes, currency, price, created_at, updated_at
      FROM wardrobe_items''');
    await db.execute('DROP TABLE wardrobe_items');
    await db.execute('ALTER TABLE wardrobe_items_new RENAME TO wardrobe_items');
    for (final layout in layouts) {
      await db.insert(
        'wardrobe_canvas_layouts',
        layout,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  Future<void> _createCoreTables(Database db) async {
    await db.execute('''CREATE TABLE wardrobe_items(
      id TEXT PRIMARY KEY, name TEXT NOT NULL,
      image_path TEXT, image_paths_json TEXT, tag_ids_json TEXT,
      brand TEXT, color TEXT, notes TEXT, currency TEXT NOT NULL DEFAULT 'CNY',
      price REAL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE outfits(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, occasion TEXT NOT NULL,
      season TEXT NOT NULL, tags_json TEXT NOT NULL, cover_path TEXT, cover_paths_json TEXT,
      notes TEXT, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
    )''');
    await db.execute('''CREATE TABLE outfit_entries(
      id INTEGER PRIMARY KEY AUTOINCREMENT, outfit_id TEXT NOT NULL,
      item_id TEXT, item_name TEXT NOT NULL, image_path TEXT,
      position INTEGER NOT NULL,
      FOREIGN KEY(outfit_id) REFERENCES outfits(id) ON DELETE CASCADE
    )''');
    await db.execute(
      'CREATE INDEX idx_entries_item ON outfit_entries(item_id)',
    );
  }

  Future<void> _createTagTables(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS wardrobe_tags(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, parent_id TEXT, sort_order INTEGER NOT NULL
    )''');
  }

  Future<void> _createOutfitTagTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS outfit_tags(
      id TEXT PRIMARY KEY, name TEXT NOT NULL, parent_id TEXT, sort_order INTEGER NOT NULL
    )''');
  }

  Future<void> _seedOutfitTags(DatabaseExecutor db) async {
    final existing = await db.query('outfit_tags', limit: 1);
    if (existing.isNotEmpty) return;
    final batch = db.batch();
    for (final tag in defaultOutfitTags) {
      batch.insert('outfit_tags', tag.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<void> _createCanvasLayoutTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS wardrobe_canvas_layouts(
      item_id TEXT PRIMARY KEY, x REAL NOT NULL, y REAL NOT NULL,
      updated_at TEXT NOT NULL, display_image_path TEXT,
      width REAL NOT NULL DEFAULT 138, height REAL NOT NULL DEFAULT 174,
      z_index INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY(item_id) REFERENCES wardrobe_items(id) ON DELETE CASCADE
    )''');
  }

  Future<void> _createCanvasRegionTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS wardrobe_canvas_regions(
      id TEXT PRIMARY KEY, label TEXT NOT NULL, x REAL NOT NULL, y REAL NOT NULL,
      width REAL NOT NULL, height REAL NOT NULL, updated_at TEXT NOT NULL,
      color_value INTEGER NOT NULL DEFAULT 4284960932, shape TEXT NOT NULL DEFAULT 'rounded'
    )''');
  }

  Future<void> _createCanvasPreferenceTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS wardrobe_canvas_preferences(
      id INTEGER PRIMARY KEY CHECK(id = 1), show_names INTEGER NOT NULL DEFAULT 1
    )''');
  }

  Future<void> _createProfileTable(Database db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS user_profile(
      id TEXT PRIMARY KEY, nickname TEXT NOT NULL, signature TEXT NOT NULL, avatar_path TEXT
    )''');
  }

  Future<void> _seedTags(DatabaseExecutor db) async {
    final existing = await db.query('wardrobe_tags', limit: 1);
    if (existing.isNotEmpty) return;
    final batch = db.batch();
    for (final tag in defaultWardrobeTags) {
      batch.insert('wardrobe_tags', tag.toMap());
    }
    await batch.commit(noResult: true);
  }

  Future<UserProfile> profile() async {
    final db = await instance;
    final row = await db.query('user_profile', orderBy: 'rowid DESC', limit: 1);
    if (row.isEmpty) {
      await db.insert('user_profile', UserProfile.defaults.toMap());
      return UserProfile.defaults;
    }
    return UserProfile.fromMap(row.single);
  }

  /// 清除设备缓存中的业务数据；不会触及 CloudBase 的远端数据或登录令牌。
  Future<void> clearLocalData() async {
    final db = await instance;
    await db.transaction((txn) async {
      for (final table in const [
        'sync_state',
        'outfit_entries',
        'outfits',
        'wardrobe_canvas_layouts',
        'wardrobe_canvas_regions',
        'wardrobe_canvas_preferences',
        'wardrobe_items',
        'wardrobe_tags',
        'outfit_tags',
        'user_profile',
      ]) {
        await txn.delete(table);
      }
    });
  }

  Future<void> saveProfile(UserProfile profile) async {
    await (await instance).transaction((txn) async {
      await txn.delete('user_profile');
      await txn.insert('user_profile', profile.toMap());
    });
  }

  Future<List<WardrobeItem>> items() async => (await (await instance).query(
    'wardrobe_items',
    orderBy: 'created_at DESC',
  )).map(WardrobeItem.fromMap).toList();

  /// 用云端快照替换本机衣物缓存，防止不同账号之间的数据混合。
  Future<void> replaceItems(List<WardrobeItem> items) async {
    final db = await instance;
    await db.transaction((txn) async {
      final ids = items.map((item) => item.id).toSet();
      final previous = await txn.query('wardrobe_items', columns: ['id']);
      for (final row in previous) {
        if (!ids.contains(row['id'])) {
          await txn.update(
            'outfit_entries',
            {'item_id': null},
            where: 'item_id = ?',
            whereArgs: [row['id']],
          );
          await txn.delete(
            'wardrobe_items',
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
      for (final item in items) {
        await _upsertItem(txn, item);
      }
    });
  }

  Future<void> _upsertItem(DatabaseExecutor db, WardrobeItem item) async {
    final updated = await db.update(
      'wardrobe_items',
      item.toMap(),
      where: 'id = ?',
      whereArgs: [item.id],
    );
    if (updated == 0) await db.insert('wardrobe_items', item.toMap());
  }

  Future<void> saveItem(WardrobeItem item) async =>
      _upsertItem(await instance, item);

  Future<void> deleteItem(String id) async {
    final db = await instance;
    await db.transaction((txn) async {
      await txn.delete(
        'wardrobe_canvas_layouts',
        where: 'item_id = ?',
        whereArgs: [id],
      );
      await txn.update(
        'outfit_entries',
        {'item_id': null},
        where: 'item_id = ?',
        whereArgs: [id],
      );
      await txn.delete('wardrobe_items', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<WardrobeCanvasRegion>> canvasRegions() async =>
      (await (await instance).query(
        'wardrobe_canvas_regions',
      )).map(WardrobeCanvasRegion.fromMap).toList();

  Future<void> saveCanvasRegion(WardrobeCanvasRegion region) async =>
      (await instance).insert(
        'wardrobe_canvas_regions',
        region.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> deleteCanvasRegion(String id) async => (await instance).delete(
    'wardrobe_canvas_regions',
    where: 'id = ?',
    whereArgs: [id],
  );

  Future<bool> canvasShowNames() async {
    final rows = await (await instance).query(
      'wardrobe_canvas_preferences',
      where: 'id = 1',
      limit: 1,
    );
    return rows.isEmpty || rows.single['show_names'] == 1;
  }

  Future<void> saveCanvasShowNames(bool showNames) async =>
      (await instance).insert('wardrobe_canvas_preferences', {
        'id': 1,
        'show_names': showNames ? 1 : 0,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<WardrobeCanvasLayout>> canvasLayouts() async =>
      (await (await instance).query(
        'wardrobe_canvas_layouts',
      )).map(WardrobeCanvasLayout.fromMap).toList();

  Future<void> saveCanvasLayout(WardrobeCanvasLayout layout) async =>
      (await instance).insert(
        'wardrobe_canvas_layouts',
        layout.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<List<WardrobeTag>> tags() async {
    final db = await instance;
    return (await db.query(
      'wardrobe_tags',
      orderBy: 'parent_id IS NOT NULL, sort_order, name',
    )).map(WardrobeTag.fromMap).toList();
  }

  /// 用云端快照替换本机标签缓存。
  Future<void> replaceTags(List<WardrobeTag> tags) async {
    final db = await instance;
    await db.transaction((txn) async {
      await txn.delete('wardrobe_tags');
      for (final tag in tags) {
        await txn.insert('wardrobe_tags', tag.toMap());
      }
    });
  }

  Future<void> saveTag(WardrobeTag tag) async => (await instance).insert(
    'wardrobe_tags',
    tag.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> reorderTags(List<WardrobeTag> tags) async {
    final db = await instance;
    final batch = db.batch();
    for (var index = 0; index < tags.length; index++) {
      batch.update(
        'wardrobe_tags',
        {'sort_order': index},
        where: 'id = ?',
        whereArgs: [tags[index].id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteTag(String id) async {
    final db = await instance;
    await db.transaction((txn) async {
      final removed = (await txn.query(
        'wardrobe_tags',
        where: 'id = ? OR parent_id = ?',
        whereArgs: [id, id],
      )).map((row) => row['id']! as String).toSet();
      await txn.delete(
        'wardrobe_tags',
        where: 'id = ? OR parent_id = ?',
        whereArgs: [id, id],
      );
      final rows = await txn.query('wardrobe_items');
      for (final row in rows) {
        final raw = row['tag_ids_json'] as String?;
        if (raw == null || raw.isEmpty) continue;
        final tagIds = (jsonDecode(raw) as List).cast<String>();
        final retained = tagIds
            .where((tagId) => !removed.contains(tagId))
            .toList();
        if (retained.length != tagIds.length) {
          await txn.update(
            'wardrobe_items',
            {'tag_ids_json': jsonEncode(retained)},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    });
  }

  Future<List<WardrobeTag>> outfitTags() async {
    final db = await instance;
    return (await db.query(
      'outfit_tags',
      orderBy: 'parent_id IS NOT NULL, sort_order, name',
    )).map(WardrobeTag.fromMap).toList();
  }

  /// 用云端快照替换本机搭配标签缓存。
  Future<void> replaceOutfitTags(List<WardrobeTag> tags) async {
    final db = await instance;
    await db.transaction((txn) async {
      await txn.delete('outfit_tags');
      for (final tag in tags) {
        await txn.insert('outfit_tags', tag.toMap());
      }
    });
  }

  Future<void> saveOutfitTag(WardrobeTag tag) async => (await instance).insert(
    'outfit_tags',
    tag.toMap(),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );

  Future<void> reorderOutfitTags(List<WardrobeTag> tags) async {
    final db = await instance;
    final batch = db.batch();
    for (var index = 0; index < tags.length; index++) {
      batch.update(
        'outfit_tags',
        {'sort_order': index},
        where: 'id = ?',
        whereArgs: [tags[index].id],
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> deleteOutfitTag(String id) async {
    final db = await instance;
    await db.transaction((txn) async {
      final removed = (await txn.query(
        'outfit_tags',
        where: 'id = ? OR parent_id = ?',
        whereArgs: [id, id],
      )).map((row) => row['id']! as String).toSet();
      await txn.delete(
        'outfit_tags',
        where: 'id = ? OR parent_id = ?',
        whereArgs: [id, id],
      );
      final rows = await txn.query('outfits');
      for (final row in rows) {
        final ids = (jsonDecode(row['tags_json']! as String) as List)
            .cast<String>();
        final retained = ids
            .where((tagId) => !removed.contains(tagId))
            .toList();
        if (ids.length != retained.length) {
          await txn.update(
            'outfits',
            {'tags_json': jsonEncode(retained)},
            where: 'id = ?',
            whereArgs: [row['id']],
          );
        }
      }
    });
  }

  Future<List<Outfit>> outfits({String? itemId}) async {
    final db = await instance;
    final rows = itemId == null
        ? await db.query('outfits', orderBy: 'created_at DESC')
        : await db.rawQuery(
            'SELECT DISTINCT o.* FROM outfits o JOIN outfit_entries e ON e.outfit_id = o.id WHERE e.item_id = ? ORDER BY o.created_at DESC',
            [itemId],
          );
    final result = <Outfit>[];
    for (final row in rows) {
      final entryRows = await db.query(
        'outfit_entries',
        where: 'outfit_id = ?',
        whereArgs: [row['id']],
        orderBy: 'position',
      );
      result.add(
        Outfit(
          id: row['id']! as String,
          name: row['name']! as String,
          occasion: row['occasion']! as String,
          season: row['season']! as String,
          tags: (jsonDecode(row['tags_json']! as String) as List)
              .cast<String>(),
          coverPath: row['cover_path'] as String?,
          coverPaths: _coverPaths(row),
          notes: row['notes'] as String?,
          createdAt: parseTimestamp(row['created_at'])!,
          updatedAt:
              parseTimestamp(row['updated_at']) ??
              parseTimestamp(row['created_at'])!,
          entries: entryRows
              .map(
                (entry) => OutfitEntry(
                  itemId: entry['item_id'] as String?,
                  name: entry['item_name']! as String,
                  imagePath: entry['image_path'] as String?,
                ),
              )
              .toList(),
        ),
      );
    }
    return result;
  }

  Future<void> saveOutfit(Outfit outfit) async {
    final db = await instance;
    await db.transaction((txn) async {
      await _insertOutfitRow(txn, outfit);
      await _replaceOutfitEntries(txn, outfit);
    });
  }

  /// 用云端快照替换本机搭配缓存，防止不同账号之间的数据混合。
  Future<void> replaceOutfits(List<Outfit> outfits) async {
    final db = await instance;
    await db.transaction((txn) async {
      await txn.delete('outfit_entries');
      await txn.delete('outfits');
      for (final outfit in outfits) {
        await _insertOutfitRow(txn, outfit);
        await _replaceOutfitEntries(txn, outfit);
      }
    });
  }

  Future<void> _insertOutfitRow(DatabaseExecutor txn, Outfit outfit) =>
      txn.insert('outfits', {
        'id': outfit.id,
        'name': outfit.name,
        'occasion': outfit.occasion,
        'season': outfit.season,
        'tags_json': jsonEncode(outfit.tags),
        'cover_path': outfit.photos.isEmpty ? null : outfit.photos.first,
        'cover_paths_json': jsonEncode(outfit.photos),
        'notes': outfit.notes,
        'created_at': toTimestamp(outfit.createdAt),
        'updated_at': toTimestamp(outfit.updatedAt),
      }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<void> _replaceOutfitEntries(
    DatabaseExecutor txn,
    Outfit outfit,
  ) async {
    await txn.delete(
      'outfit_entries',
      where: 'outfit_id = ?',
      whereArgs: [outfit.id],
    );
    for (var i = 0; i < outfit.entries.length; i++) {
      final entry = outfit.entries[i];
      await txn.insert('outfit_entries', {
        'outfit_id': outfit.id,
        'item_id': entry.itemId,
        'item_name': entry.name,
        'image_path': entry.imagePath,
        'position': i,
      });
    }
  }

  List<String> _coverPaths(Map<String, Object?> row) {
    final raw = row['cover_paths_json'] as String?;
    if (raw != null && raw.isNotEmpty) {
      return (jsonDecode(raw) as List).cast<String>();
    }
    return <String>[if (row['cover_path'] case final String path) path];
  }

  Future<void> deleteOutfit(String id) async =>
      (await instance).delete('outfits', where: 'id = ?', whereArgs: [id]);
}
