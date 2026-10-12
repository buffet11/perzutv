import 'package:dio/dio.dart';
import 'package:perzutv/request/core/dio_factory.dart';
import 'package:perzutv/request/core/network_error_mapper.dart';
import 'package:perzutv/utils/dandan_credentials.dart';
import 'package:perzutv/utils/http_headers.dart';
import 'package:perzutv/utils/crypto.dart';

class DanmakuClient {
  DanmakuClient._();

  static final DanmakuClient instance = DanmakuClient._();

  // 官方 api.dandanplay.net 要求 X-AppId/X-Signature 签名；自建兼容服务
  // （如 danmu_api）不校验这些头，凭据缺失时签名也无意义，直接跳过。
  static bool _isOfficialDomain(String url) =>
      url.startsWith('https://api.dandanplay.net');

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
  }) async {
    final requestHeaders = <String, dynamic>{
      'user-agent': getRandomUA(),
      'referer': '',
      ...headers,
    };

    if (_isOfficialDomain(url) &&
        dandanCredentials['id']!.isNotEmpty &&
        dandanCredentials['value']!.isNotEmpty) {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final uri = Uri.parse(url);
      requestHeaders.addAll(<String, dynamic>{
        'X-Auth': 1,
        'X-AppId': dandanCredentials['id'],
        'X-Timestamp': timestamp,
        'X-Signature': generateDandanSignature(uri.path, timestamp),
      });
    }

    try {
      final response = await DioFactory.apiDio.get(
        url,
        queryParameters: queryParameters,
        options: Options(headers: requestHeaders),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }
}
