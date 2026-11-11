import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'cloudbase_config.dart';

class CloudBaseException implements Exception {
  const CloudBaseException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class CloudBaseClient {
  CloudBaseClient({http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;
  void close() => _httpClient.close();

  Future<Map<String, Object?>> requestObject(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? accessToken,
    Map<String, String>? queryParameters,
    Map<String, String>? extraHeaders,
  }) async {
    final value = await request(
      method,
      path,
      body: body,
      accessToken: accessToken,
      queryParameters: queryParameters,
      extraHeaders: extraHeaders,
    );
    if (value is Map) return Map<String, Object?>.from(value);
    throw const CloudBaseException('云端返回的数据格式不正确');
  }

  Future<Object?> request(
    String method,
    String path, {
    Map<String, Object?>? body,
    String? accessToken,
    Map<String, String>? queryParameters,
    Map<String, String>? extraHeaders,
  }) async {
    final uri = Uri.parse(
      '${CloudBaseConfig.baseUrl}$path',
    ).replace(queryParameters: queryParameters);
    final token = accessToken ?? CloudBaseConfig.publishableKey;
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      ...?extraHeaders,
    };
    final response = await _send(
      http.Request(method, uri)
        ..headers.addAll(headers)
        ..body = body == null ? '' : jsonEncode(body),
    );
    final responseBody = response.body;
    final decoded = responseBody.isEmpty ? null : _decodeJson(responseBody);
    // 通过 `/v1/functions/{name}` 云调用普通云函数时，网关一律返回外层
    // HTTP 200，真正的业务状态码/内容被包在云函数自己返回的
    // `{ statusCode, headers, body }` 结构里，其中 `body` 是 JSON 字符串，
    // 需要再解析一层才能拿到真实数据；这里做一次"拆包"，让上层代码始终
    // 拿到业务层真正的响应，而不是这个信封结构本身。
    final unwrapped = _unwrapFunctionResponse(decoded, response.statusCode);
    if (unwrapped.statusCode >= 200 && unwrapped.statusCode < 300) {
      return unwrapped.body;
    }
    throw CloudBaseException(
      _errorMessage(unwrapped.body) ?? '云端请求失败（${unwrapped.statusCode}）',
      statusCode: unwrapped.statusCode,
    );
  }

  Future<http.Response> _send(http.Request request) async {
    final cancel = Completer<void>();
    final abortable =
        http.AbortableRequest(
            request.method,
            request.url,
            abortTrigger: cancel.future,
          )
          ..headers.addAll(request.headers)
          ..bodyBytes = request.bodyBytes;
    try {
      return await (() async {
        final streamed = await _httpClient.send(abortable);
        return http.Response.fromStream(streamed);
      })().timeout(const Duration(seconds: 25));
    } on TimeoutException {
      if (!cancel.isCompleted) cancel.complete();
      throw const CloudBaseException('网络请求超时，数据已保留，可稍后重试');
    } on http.ClientException {
      throw const CloudBaseException('无法连接云端，请检查网络');
    }
  }

  Future<void> uploadBytes(
    String path,
    Uint8List bytes, {
    required String accessToken,
    required String contentType,
  }) async {
    final response = await _send(
      http.Request('POST', Uri.parse('${CloudBaseConfig.baseUrl}$path'))
        ..headers.addAll({
          'Authorization': 'Bearer $accessToken',
          'Content-Type': contentType,
          'x-upsert': 'true',
        })
        ..bodyBytes = bytes,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw CloudBaseException(
        '图片上传失败（${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }
  }

  Future<Uint8List> downloadBytes(Uri uri) async {
    if (uri.scheme != 'https') throw const CloudBaseException('图片链接必须使用 HTTPS');
    final response = await _send(http.Request('GET', uri));
    if (response.statusCode != 200) throw const CloudBaseException('图片下载失败');
    return response.bodyBytes;
  }

  Future<List<Object?>> fetchAll(
    String path, {
    required String accessToken,
    Map<String, String> query = const {},
  }) async {
    final values = <Object?>[];
    var offset = 0;
    // Continue until empty: a server-imposed page cap may be smaller than limit.
    while (true) {
      final page = await request(
        'GET',
        path,
        accessToken: accessToken,
        queryParameters: {...query, 'limit': '200', 'offset': '$offset'},
      );
      if (page is! List) throw const CloudBaseException('云端列表格式不正确');
      if (page.isEmpty) return values;
      values.addAll(page);
      offset += page.length;
    }
  }

  /// 尝试把云函数返回的 `{ statusCode, headers, body }` 信封拆开；如果
  /// 响应并非这种信封形态（比如直接触发 HTTP 访问服务、或普通 REST
  /// 接口），则原样返回，`statusCode` 取外层真实 HTTP 状态码。
  ///
  /// 判定条件要求 `statusCode`（int）、`headers`（Map）、`body` 三个字段
  /// 同时具备——这是云函数 `respond()` 辅助函数返回结构的完整特征，
  /// 避免误伤 `rdb/rest` 等普通接口偶然返回同名字段的数据。
  _UnwrappedResponse _unwrapFunctionResponse(
    Object? decoded, [
    int? httpStatusCode,
  ]) {
    if (decoded is Map &&
        decoded['statusCode'] is int &&
        decoded['headers'] is Map &&
        decoded.containsKey('body')) {
      final rawBody = decoded['body'];
      final innerBody = rawBody is String && rawBody.isNotEmpty
          ? _decodeJson(rawBody)
          : rawBody;
      return _UnwrappedResponse(decoded['statusCode'] as int, innerBody);
    }
    return _UnwrappedResponse(httpStatusCode ?? 200, decoded);
  }

  Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const CloudBaseException('云端返回了无法解析的数据');
    }
  }

  String? _errorMessage(Object? body) {
    if (body is! Map) return null;
    final value = Map<String, Object?>.from(body);
    for (final key in ['error_description', 'message', 'error']) {
      if (value[key] is String) return value[key] as String;
    }
    return null;
  }
}

/// 拆包后的响应：`statusCode` 是业务层真正的状态码，`body` 是解析后的
/// 业务数据（而不是云函数返回的 `{ statusCode, headers, body }` 信封）。
class _UnwrappedResponse {
  const _UnwrappedResponse(this.statusCode, this.body);

  final int statusCode;
  final Object? body;
}
