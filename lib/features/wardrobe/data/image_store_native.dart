import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// 将用户选择的照片复制到应用私有目录，数据库保存相对路径，避免 iOS 沙盒目录变化导致引用失效。
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
    return p.join('wardrobe_images', p.basename(target));
  }

  /// Old iOS records contain a full container path. Resolve the owned filename
  /// against the current Documents directory, including pending sync commands.
  Future<File> _localFile(String path) async {
    final normalized = p.normalize(path);
    final root = await getApplicationDocumentsDirectory();
    final directory = p.join(root.path, 'wardrobe_images');
    if (p.basename(p.dirname(normalized)) == 'wardrobe_images') {
      return File(p.join(directory, p.basename(normalized)));
    }
    if (!p.isAbsolute(normalized)) {
      throw const MissingLocalImageException();
    }
    return File(normalized);
  }

  Future<Uint8List> readBytes(String path) async {
    if (path.startsWith('data:')) return UriData.parse(path).contentAsBytes();
    final file = await _localFile(path);
    if (!await file.exists()) throw const MissingLocalImageException();
    try {
      return await file.readAsBytes();
    } on FileSystemException catch (error) {
      if (error.osError?.errorCode == 2) {
        throw const MissingLocalImageException();
      }
      rethrow;
    }
  }

  Future<String> persistBytes(Uint8List bytes) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'wardrobe_images'));
    await directory.create(recursive: true);
    final target = p.join(directory.path, '${const Uuid().v4()}.png');
    await File(target).writeAsBytes(bytes, flush: true);
    return p.join('wardrobe_images', p.basename(target));
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
    final file = await _localFile(path);
    if (!p.isWithin(directory, p.normalize(file.path))) return;
    if (await file.exists()) await file.delete();
  }
}

/// A missing original must be replaced explicitly, never silently discarded.
class MissingLocalImageException implements Exception {
  const MissingLocalImageException();
  @override
  String toString() => '本机照片文件已不存在，暂时无法上传。请编辑对应衣物或搭配，重新选择照片后保存；衣物记录仍保留。';
}
