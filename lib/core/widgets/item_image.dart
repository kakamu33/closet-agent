import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../dependencies.dart';
import '../sync/sync_providers.dart';
import '../../features/auth/application/auth_controller.dart';

final _imageBytesProvider = FutureProvider.autoDispose
    .family<Uint8List, String>((ref, path) async {
      ref.watch(authSessionProvider.select((session) => session.value?.id));
      final media = ref.watch(cloudMediaStoreProvider);
      var token = '';
      if (path.startsWith('storage://')) {
        try {
          return await media.read(path, '');
        } catch (_) {
          /* Cache miss: authenticate below. */
        }
        try {
          token =
              await ref.read(authRepositoryProvider).currentAccessToken() ?? '';
        } catch (_) {
          /* An offline cached image does not need a fresh token. */
        }
      }
      return media.read(path, token);
    });

class ItemImage extends ConsumerWidget {
  const ItemImage({
    super.key,
    this.path,
    this.size,
    this.width,
    this.height,
    this.radius = 18,
  });
  final String? path;
  final double? size;
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(
      width: width ?? size,
      height: height ?? size,
      child: path == null
          ? _placeholder(Icons.checkroom)
          : ref
                .watch(_imageBytesProvider(path!))
                .when(
                  data: (bytes) => Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    cacheWidth: 800,
                    errorBuilder: (_, _, _) =>
                        _placeholder(Icons.broken_image_outlined),
                  ),
                  loading: () => _placeholder(Icons.image_outlined),
                  error: (_, _) => _placeholder(Icons.broken_image_outlined),
                ),
    ),
  );
  Widget _placeholder(IconData icon) => ColoredBox(
    color: const Color(0xFFEAE5DD),
    child: Icon(icon, color: Colors.brown.shade300, size: 34),
  );
}
