class WardrobeCanvasLayout {
  const WardrobeCanvasLayout({
    required this.itemId,
    required this.x,
    required this.y,
    required this.updatedAt,
    this.displayImagePath,
    this.width = 138,
    this.height = 174,
    this.zIndex = 0,
  });

  /// 坐标与展示图片均可直接作为未来云端同步记录。
  final String itemId;
  final double x;
  final double y;
  final DateTime updatedAt;
  final String? displayImagePath;
  final double width;
  final double height;
  final int zIndex;

  Map<String, Object?> toMap() => {
    'item_id': itemId,
    'x': x,
    'y': y,
    'updated_at': updatedAt.toIso8601String(),
    'display_image_path': displayImagePath,
    'width': width,
    'height': height,
    'z_index': zIndex,
  };

  factory WardrobeCanvasLayout.fromMap(Map<String, Object?> map) =>
      WardrobeCanvasLayout(
        itemId: map['item_id']! as String,
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        updatedAt: DateTime.parse(map['updated_at']! as String),
        displayImagePath: map['display_image_path'] as String?,
        width: (map['width'] as num?)?.toDouble() ?? 138,
        height: (map['height'] as num?)?.toDouble() ?? 174,
        zIndex: (map['z_index'] as num?)?.toInt() ?? 0,
      );
}
