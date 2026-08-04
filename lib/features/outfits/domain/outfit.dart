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
  List<String> get photos => coverPaths.isNotEmpty ? coverPaths : <String>[if (coverPath != null) coverPath!];
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;
}

const seasons = ['春', '夏', '秋', '冬', '四季'];
const occasions = ['日常', '通勤', '约会', '旅行', '运动', '正式', '聚会'];
