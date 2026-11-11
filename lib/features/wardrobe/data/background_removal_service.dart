import 'dart:convert';
import '../../../core/cloudbase/cloudbase_client.dart';
import '../../../core/media/cloud_media_store.dart';
import 'image_store.dart';

class BackgroundRemovalException implements Exception {
  const BackgroundRemovalException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The Poof credential exists only in the cloud function environment.
class BackgroundRemovalService {
  BackgroundRemovalService({
    required this.client,
    required this.token,
    required this.userId,
  });
  final CloudBaseClient client;
  final Future<String?> Function() token;
  final Future<String?> Function() userId;

  Future<String> removeBackground({required String imagePath}) async {
    try {
      final accessToken = await token();
      if (accessToken == null) {
        throw const BackgroundRemovalException('请重新登录后抠图');
      }
      const local = ImageStore();
      final media = CloudMediaStore(
        client: client,
        local: local,
        ownerId: await userId(),
      );
      final bytes = await media.read(imagePath, accessToken);
      if (bytes.length > 4 * 1024 * 1024) {
        throw const BackgroundRemovalException('抠图图片不能超过 4MB，请先压缩图片');
      }
      final result = await client.requestObject(
        'POST',
        '/v1/functions/removeBackground',
        accessToken: accessToken,
        body: {'accessToken': accessToken, 'image': base64Encode(bytes)},
      );
      final output = result['image'];
      if (output is! String || output.isEmpty) {
        throw const BackgroundRemovalException('抠图服务返回了无效图片');
      }
      return local.persistBytes(base64Decode(output));
    } on CloudBaseException catch (error) {
      throw BackgroundRemovalException(error.message);
    }
  }
}
