import '../../../core/time_utils.dart';

class OutfitEntry {
  const OutfitEntry({this.itemId, required this.name, this.imagePath});

  final String? itemId;
  final String name;
  final String? imagePath;
  bool get isLinked => itemId != null;
}

class Outfit {
  const Outfit({
    required this.id,
    required this.name,
    required this.occasion,
    required this.season,
    required this.tags,
    required this.entries,
    required this.createdAt,
    required this.updatedAt,
    this.coverPath,
    this.coverPaths = const [],
    this.notes,
  });

  final String id;
  final String name;
  final String occasion;
  final String season;
  final List<String> tags;
  final List<OutfitEntry> entries;
  final String? coverPath;
  final List<String> coverPaths;
  List<String> get photos => coverPaths.isNotEmpty
      ? coverPaths
      : <String>[?coverPath];
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'occasion': occasion,
    'season': season,
    'tags': tags,
    'photos': photos,
    'notes': notes,
    'created_at': toTimestamp(createdAt),
    'updated_at': toTimestamp(updatedAt),
    'entries': entries
        .map(
          (e) => {
            'item_id': e.itemId,
            'name': e.name,
            'image_path': e.imagePath,
          },
        )
        .toList(),
  };

  factory Outfit.fromMap(Map<String, Object?> map) => Outfit(
    id: map['id']! as String,
    name: map['name']! as String,
    occasion: map['occasion'] as String? ?? '',
    season: map['season'] as String? ?? '',
    tags: (map['tags'] as List).cast<String>(),
    coverPaths: (map['photos'] as List).cast<String>(),
    notes: map['notes'] as String?,
    createdAt: parseTimestamp(map['created_at'])!,
    updatedAt: parseTimestamp(map['updated_at'])!,
    entries: (map['entries'] as List).map((entry) {
      final e = Map<String, Object?>.from(entry as Map);
      return OutfitEntry(
        itemId: e['item_id'] as String?,
        name: e['name']! as String,
        imagePath: e['image_path'] as String?,
      );
    }).toList(),
  );
}

const seasons = ['春', '夏', '秋', '冬', '四季'];
const occasions = ['日常', '通勤', '约会', '旅行', '运动', '正式', '聚会'];
