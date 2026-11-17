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
      final owner = await userId();
      final accessToken = await token();
      if (owner == null || accessToken == null || accessToken.isEmpty) {
        throw const BackgroundRemovalException('请重新登录后抠图');
      }
      if (await userId() != owner) {
        throw const BackgroundRemovalException('账号已切换，本次抠图已停止');
      }
      const local = ImageStore();
      final media = CloudMediaStore(
        client: client,
        local: local,
        ownerId: owner,
      );
      final bytes = await media.read(imagePath, accessToken);
      if (bytes.length > 4 * 1024 * 1024) {
        throw const BackgroundRemovalException('抠图图片不能超过 4MB，请先压缩图片');
      }
      if (await userId() != owner) {
        throw const BackgroundRemovalException('账号已切换，本次抠图已停止');
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
      if (await userId() != owner) {
        throw const BackgroundRemovalException('账号已切换，本次抠图已停止');
      }
      return local.persistBytes(base64Decode(output));
    } on CloudBaseException catch (error) {
      if (error.message.contains('FUNCTIONS_NOT_FOUND') ||
          error.message.contains('FunctionName parameter could not be found')) {
        throw const BackgroundRemovalException(
          '未找到抠图云函数：请在 App 对应的云环境部署普通云函数 removeBackground（注意大小写）',
        );
      }
      throw BackgroundRemovalException(error.message);
    }
  }
}
