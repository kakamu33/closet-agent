import 'dart:convert';

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
  CloudBaseClient({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

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
    final uri = Uri.parse('${CloudBaseConfig.baseUrl}$path').replace(
      queryParameters: queryParameters,
    );
    final token = accessToken ?? CloudBaseConfig.publishableKey;
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
      ...?extraHeaders,
    };
    final response = await _httpClient.send(
      http.Request(method, uri)
        ..headers.addAll(headers)
        ..body = body == null ? '' : jsonEncode(body),
    );
    final responseBody = await response.stream.bytesToString();
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

  /// 尝试把云函数返回的 `{ statusCode, headers, body }` 信封拆开；如果
  /// 响应并非这种信封形态（比如直接触发 HTTP 访问服务、或普通 REST
  /// 接口），则原样返回，`statusCode` 取外层真实 HTTP 状态码。
  ///
  /// 判定条件要求 `statusCode`（int）、`headers`（Map）、`body` 三个字段
  /// 同时具备——这是云函数 `respond()` 辅助函数返回结构的完整特征，
  /// 避免误伤 `rdb/rest` 等普通接口偶然返回同名字段的数据。
  _UnwrappedResponse _unwrapFunctionResponse(Object? decoded, [int? httpStatusCode]) {
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
    return value['error_description'] as String? ??
        value['message'] as String? ??
        value['error'] as String?;
  }
}

/// 拆包后的响应：`statusCode` 是业务层真正的状态码，`body` 是解析后的
/// 业务数据（而不是云函数返回的 `{ statusCode, headers, body }` 信封）。
class _UnwrappedResponse {
  const _UnwrappedResponse(this.statusCode, this.body);

  final int statusCode;
  final Object? body;
}

