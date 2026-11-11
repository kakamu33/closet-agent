import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 将用户选择的照片复制到应用私有目录，数据库只保存该文件的路径。
class ImageStore {
  const ImageStore();

  Future<String> persist(XFile image) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'wardrobe_images'));
    await directory.create(recursive: true);
    final extension = p.extension(image.path).isEmpty
        ? '.jpg'
        : p.extension(image.path);
    final target = p.join(directory.path, '${const Uuid().v4()}$extension');
    await File(image.path).copy(target);
    return target;
  }

  Future<Uint8List> readBytes(String path) async {
    if (path.startsWith('data:')) return UriData.parse(path).contentAsBytes();
    return File(path).readAsBytes();
  }

  Future<String> persistBytes(Uint8List bytes) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'wardrobe_images'));
    await directory.create(recursive: true);
    final target = p.join(directory.path, '${const Uuid().v4()}.png');
    await File(target).writeAsBytes(bytes, flush: true);
    return target;
  }

  Future<File> _cacheFile(String reference) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'media_cache'));
    await directory.create(recursive: true);
    return File(
      p.join(directory.path, sha256.convert(utf8.encode(reference)).toString()),
    );
  }

  Future<Uint8List?> readCached(String reference) async {
    final file = await _cacheFile(reference);
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> cache(String reference, Uint8List bytes) async {
    await (await _cacheFile(reference)).writeAsBytes(bytes, flush: true);
  }

  /// Only delete files owned by this application's media directory.
  Future<void> delete(String path) async {
    if (path.contains('://') || path.startsWith('data:')) return;
    final root = await getApplicationDocumentsDirectory();
    final directory = p.join(root.path, 'wardrobe_images');
    if (!p.isWithin(directory, p.normalize(path))) return;
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
