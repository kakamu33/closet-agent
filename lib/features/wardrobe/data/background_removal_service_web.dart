import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

class BackgroundRemovalException implements Exception {
  const BackgroundRemovalException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 浏览器端将 Data URL 解码上传，并将 Poof 的透明 PNG 再编码为 Data URL。
class BackgroundRemovalService {
  const BackgroundRemovalService();

  Future<String> removeBackground({
    required String imagePath,
    required String apiKey,
  }) async {
    if (!imagePath.startsWith('data:')) {
      throw const BackgroundRemovalException('网页端仅支持已保存在衣橱中的图片。');
    }
    final match = RegExp(r'^data:([^;]+);base64,(.*)$').firstMatch(imagePath);
    if (match == null) {
      throw const BackgroundRemovalException('图片数据格式不正确。');
    }
    final sourceMime = match.group(1)!;
    final bytes = base64Decode(match.group(2)!);
    final parts = sourceMime.split('/');
    if (parts.length != 2) {
      throw const BackgroundRemovalException('不支持的图片格式。');
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('https://api.poof.bg/v1/remove'),
    )
      ..headers['x-api-key'] = apiKey
      ..fields['format'] = 'png'
      ..fields['channels'] = 'rgba'
      ..files.add(
        http.MultipartFile.fromBytes(
          'image_file',
          bytes,
          filename: 'wardrobe-image.${parts[1]}',
          contentType: MediaType(parts[0], parts[1]),
        ),
      );
    try {
      final response = await request.send();
      final result = await response.stream.toBytes();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw BackgroundRemovalException(_apiError(response.statusCode));
      }
      return 'data:image/png;base64,${base64Encode(result)}';
    } on TimeoutException {
      throw const BackgroundRemovalException('抠图请求超时，请稍后重试。');
    } catch (error) {
      if (error is BackgroundRemovalException) rethrow;
      throw const BackgroundRemovalException('无法连接 Poof 服务，请检查网络或浏览器跨域设置。');
    }
  }

  String _apiError(int status) => switch (status) {
        401 => 'Poof API Key 无效，请检查配置。',
        402 => 'Poof 账户余额不足，无法完成抠图。',
        413 => '图片文件过大，请选择 20MB 以内的图片。',
        429 => 'Poof 请求过于频繁，请稍后再试。',
        _ => '抠图失败（Poof 服务返回 $status）。',
      };
}

