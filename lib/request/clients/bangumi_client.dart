import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:perzutv/request/config/api_endpoints.dart';
import 'package:perzutv/request/core/dio_factory.dart';
import 'package:perzutv/request/core/network_error_mapper.dart';
import 'package:perzutv/services/network/bangumi_acceleration.dart';
import 'package:perzutv/services/storage/storage.dart';
import 'package:perzutv/utils/bangumi_mirror_credentials.dart';
import 'package:perzutv/utils/constants.dart';
import 'package:perzutv/utils/crypto.dart';

class BangumiClient {
  BangumiClient._();

  static final BangumiClient instance = BangumiClient._();

  Future<dynamic> get(
    String url, {
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
    String? accessToken,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await DioFactory.bangumiDio.get(
        url,
        queryParameters: queryParameters,
        options: Options(
          headers: _headers(
            requiresAuth: requiresAuth,
            accessToken: accessToken,
            url: url,
            method: 'GET',
          ),
        ),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  Future<dynamic> post(
    String url, {
    Object? data,
    Map<String, dynamic>? queryParameters,
    bool requiresAuth = false,
    CancelToken? cancelToken,
  }) async {
    try {
      final response = await DioFactory.bangumiDio.post(
        url,
        data: data,
        queryParameters: queryParameters,
        options: Options(
          headers: _headers(
            requiresAuth: requiresAuth,
            url: url,
            method: 'POST',
            data: data,
          ),
        ),
        cancelToken: cancelToken,
      );
      return response.data;
    } on DioException catch (e) {
      throw await NetworkErrorMapper.mapException(e);
    }
  }

  Map<String, dynamic> _headers({
    required bool requiresAuth,
    String? accessToken,
    required String url,
    required String method,
    Object? data,
  }) {
    final headers = <String, dynamic>{...bangumiHTTPHeader};
    final bangumiSyncEnable = GStorage.getSetting(
      SettingsKeys.bangumiSyncEnable,
    );
    final token =
        (accessToken ??
                GStorage.getSetting<String>(SettingsKeys.bangumiAccessToken))
            .trim();
    if ((requiresAuth || bangumiSyncEnable) && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (_shouldSignProtectedMirrorRequest(url, method)) {
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final body = data == null ? '' : jsonEncode(data);
      headers['X-AppId'] = bangumiMirrorCredentials['id'];
      headers['X-Timestamp'] = timestamp;
      headers['X-Signature'] = generateBangumiMirrorSearchSignature(
        method: method,
        path: Uri.parse(url).path,
        body: body,
        timestamp: timestamp,
      );
    }
    return headers;
  }

  bool _shouldSignProtectedMirrorRequest(String url, String method) {
    final uri = Uri.parse(url);
    if (BangumiAcceleration.current != BangumiAcceleration.mirror ||
        !ApiEndpoints.bangumiPublicApiHosts.contains(uri.host)) {
      return false;
    }
    // 没有凭据就签不出有效签名。此时既不加签名头（加了也是错的），
    // 拦截器那边也会让这类请求绕开镜像 —— 两处都看同一个判定。
    if (!BangumiAcceleration.hasMirrorCredentials) {
      return false;
    }
    return BangumiAcceleration.needsMirrorSignature(method, uri.path);
  }
}
