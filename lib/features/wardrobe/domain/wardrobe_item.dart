import 'item_details.dart';
import 'dart:convert';

import '../../../core/time_utils.dart';

class WardrobeItem {
  const WardrobeItem({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    this.imagePaths = const [],
    this.tagIds = const [],
    this.brand,
    this.color,
    this.notes,
    this.currency = 'CNY',
    this.price,
    this.syncVersion = 0,
    this.details = const ItemDetails(),
  });

  final ItemDetails details;
  final int syncVersion;
  final String id;
  final String name;
  final List<String> imagePaths;
  final List<String> tagIds;
  String? get imagePath => imagePaths.isEmpty ? null : imagePaths.first;
  final String? brand;
  final String? color;
  final String? notes;
  final String currency;
  final double? price;
  final DateTime createdAt;
  final DateTime updatedAt;

  Object? attribute(String key) => switch (key) {
    'status' => details.status,
    'seasons' => details.seasons,
    'brand' => brand,
    'color' => color,
    'price' => price,
    'notes' => notes,
    _ => details.values[key],
  };

  WardrobeItem copyWith({
    ItemDetails? details,
    String? name,
    List<String>? imagePaths,
    DateTime? updatedAt,
  }) => WardrobeItem(
    details: details ?? this.details,
    id: id,
    syncVersion: syncVersion,
    name: name ?? this.name,
    imagePaths: imagePaths ?? this.imagePaths,
    tagIds: tagIds,
    brand: brand,
    color: color,
    notes: notes,
    currency: currency,
    price: price,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toMap() => {
    'details_json': details.encode(),
    'id': id,
    'sync_version': syncVersion,
    'name': name,
    'image_path': imagePath,
    'image_paths_json': jsonEncode(imagePaths),
    'tag_ids_json': jsonEncode(tagIds),
    'brand': brand,
    'color': color,
    'notes': notes,
    'currency': currency,
    'price': price,
    'created_at': toTimestamp(createdAt),
    'updated_at': toTimestamp(updatedAt),
  };

  factory WardrobeItem.fromMap(Map<String, Object?> map) {
    final rawPaths = map['image_paths_json'] as String?;
    final paths = rawPaths == null || rawPaths.isEmpty
        ? <String>[if (map['image_path'] case final String path) path]
        : (jsonDecode(rawPaths) as List).cast<String>();
    final rawTags = map['tag_ids_json'] as String?;
    final tags = rawTags == null || rawTags.isEmpty
        ? const <String>[]
        : (jsonDecode(rawTags) as List).cast<String>();
    final createdAt = parseTimestamp(map['created_at'])!;
    return WardrobeItem(
      details: ItemDetails.parse(map['details_json']),
      id: map['id']! as String,
      syncVersion: (map['sync_version'] as num?)?.toInt() ?? 0,
      name: map['name']! as String,
      imagePaths: paths,
      tagIds: tags,
      brand: map['brand'] as String?,
      color: map['color'] as String?,
      notes: map['notes'] as String?,
      currency: map['currency'] as String? ?? 'CNY',
      price: (map['price'] as num?)?.toDouble(),
      createdAt: createdAt,
      updatedAt: parseTimestamp(map['updated_at']) ?? createdAt,
    );
  }
}

/// Merge only photo fields; all independently edited attributes stay intact.
WardrobeItem replaceItemPhotos(
  WardrobeItem current,
  WardrobeItem before,
  WardrobeItem after,
) {
  final paths = jsonEncode(current.imagePaths);
  if (paths != jsonEncode(before.imagePaths) &&
      paths != jsonEncode(after.imagePaths)) {
    throw StateError('图片已发生变化，请关闭后重新选择单品');
  }
  return current.copyWith(
    imagePaths: after.imagePaths,
    details: current.details.copyWith(originals: after.details.originals),
    updatedAt: DateTime.now(),
  );
}
