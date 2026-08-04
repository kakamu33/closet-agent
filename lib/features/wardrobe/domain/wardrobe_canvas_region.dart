enum CanvasRegionShape { rectangle, rounded, oval }

class WardrobeCanvasRegion {
  const WardrobeCanvasRegion({
    required this.id,
    required this.label,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.updatedAt,
    this.colorValue = 0xFF6750A4,
    this.shape = CanvasRegionShape.rounded,
  });

  final String id;
  final String label;
  final double x;
  final double y;
  final double width;
  final double height;
  final DateTime updatedAt;
  final int colorValue;
  final CanvasRegionShape shape;

  Map<String, Object?> toMap() => {
    'id': id,
    'label': label,
    'x': x,
    'y': y,
    'width': width,
    'height': height,
    'updated_at': updatedAt.toIso8601String(),
    'color_value': colorValue,
    'shape': shape.name,
  };

  factory WardrobeCanvasRegion.fromMap(Map<String, Object?> map) =>
      WardrobeCanvasRegion(
        id: map['id']! as String,
        label: map['label']! as String,
        x: (map['x'] as num).toDouble(),
        y: (map['y'] as num).toDouble(),
        width: (map['width'] as num).toDouble(),
        height: (map['height'] as num).toDouble(),
        updatedAt: DateTime.parse(map['updated_at']! as String),
        colorValue: (map['color_value'] as num?)?.toInt() ?? 0xFF6750A4,
        shape: CanvasRegionShape.values.firstWhere(
          (shape) => shape.name == map['shape'],
          orElse: () => CanvasRegionShape.rounded,
        ),
      );
}
