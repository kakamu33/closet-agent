import 'dart:io';

import 'package:flutter/material.dart';

class ItemImage extends StatelessWidget {
  const ItemImage({super.key, this.path, this.size, this.width, this.height, this.radius = 18});

  final String? path;
  final double? size;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(
      width: width ?? size,
      height: height ?? size,
      child: path == null
          ? ColoredBox(
              color: const Color(0xFFEAE5DD),
              child: Icon(Icons.checkroom, color: Colors.brown.shade300, size: 34),
            )
          : path!.startsWith('data:')
              ? Image.network(path!, fit: BoxFit.cover, errorBuilder: _error)
              : Image.file(File(path!), fit: BoxFit.cover, errorBuilder: _error),
    ),
  );

  Widget _error(BuildContext context, Object error, StackTrace? stackTrace) =>
      const ColoredBox(
        color: Color(0xFFEAE5DD),
        child: Icon(Icons.broken_image_outlined),
      );
}

