import 'dart:convert';

import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart';

/// 浏览器端没有应用文件目录，图片以 Data URL 保存到 localStorage。
class ImageStore {
  const ImageStore();

  Future<String> persist(XFile image) async {
    final bytes = await image.readAsBytes();
    final mimeType = lookupMimeType(image.name, headerBytes: bytes) ?? 'image/jpeg';
    return 'data:$mimeType;base64,${base64Encode(bytes)}';
  }

  /// Web 端的图片随数据库记录替换，Data URL 本身没有独立文件可删除。
  Future<void> delete(String path) async {}
}

