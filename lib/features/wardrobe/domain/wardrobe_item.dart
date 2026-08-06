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
  });

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

  WardrobeItem copyWith({
    String? name,
    List<String>? imagePaths,
    DateTime? updatedAt,
  }) => WardrobeItem(
    id: id,
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
    'id': id,
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
      id: map['id']! as String,
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
