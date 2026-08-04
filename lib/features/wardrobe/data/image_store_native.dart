import 'dart:io';

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
    final extension = p.extension(image.path).isEmpty ? '.jpg' : p.extension(image.path);
    final target = p.join(directory.path, '${const Uuid().v4()}$extension');
    await File(image.path).copy(target);
    return target;
  }

  /// 抠图完成后删除应用私有目录中的旧图，避免重复占用本地空间。
  Future<void> delete(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}

