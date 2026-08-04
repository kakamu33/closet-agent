import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class BackgroundRemovalException implements Exception {
  const BackgroundRemovalException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Poof 返回透明 PNG，并保存到应用私有目录。
class BackgroundRemovalService {
  const BackgroundRemovalService();

  Future<String> removeBackground({
    required String imagePath,
    required String apiKey,
  }) async {
    final file = File(imagePath);
    if (!await file.exists()) {
      throw const BackgroundRemovalException('找不到需要抠图的原始图片。');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.poof.bg/v1/remove'),
    )
      ..headers['x-api-key'] = apiKey
      ..fields['format'] = 'png'
      ..fields['channels'] = 'rgba'
      ..files.add(
        await http.MultipartFile.fromPath(
          'image_file',
          imagePath,
          contentType: _mediaTypeFor(imagePath),
        ),
      );
    final response = await request.send();
    final bytes = await response.stream.toBytes();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackgroundRemovalException(_apiError(response.statusCode, bytes));
    }

    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'wardrobe_images'));
    await directory.create(recursive: true);
    final outputPath = p.join(directory.path, '${const Uuid().v4()}_cutout.png');
    await File(outputPath).writeAsBytes(bytes, flush: true);
    return outputPath;
  }

  MediaType? _mediaTypeFor(String path) {
    final mime = lookupMimeType(path);
    if (mime == null) return null;
    final parts = mime.split('/');
    return parts.length == 2 ? MediaType(parts[0], parts[1]) : null;
  }

  String _apiError(int status, Uint8List body) => switch (status) {
        401 => 'Poof API Key 无效，请检查配置。',
        402 => 'Poof 账户余额不足，无法完成抠图。',
        413 => '图片文件过大，请选择 20MB 以内的图片。',
        429 => 'Poof 请求过于频繁，请稍后再试。',
        _ => '抠图失败（Poof 服务返回 $status）。',
      };
}

