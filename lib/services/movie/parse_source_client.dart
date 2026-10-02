import 'package:dio/dio.dart';
import 'package:kazutv/modules/movie/parse_source.dart';
import 'package:kazutv/request/core/dio_factory.dart';
import 'package:kazutv/services/movie/movie_stream_parsing.dart';

/// 解析出的播放地址。
class ParsedStream {
  final String url;

  /// 接口有时会一并给出播放所需的自定义请求头（Referer / User-Agent 等）
  final Map<String, String> headers;

  const ParsedStream({required this.url, this.headers = const {}});

  @override
  String toString() => 'ParsedStream($url, ${headers.length} headers)';
}

/// 单个解析源的调用。
///
/// 解析接口的协议**没有标准**，实测到的至少三种：
///   1. `301/302` 直接跳到播放地址（`Location` 头就是答案）
///   2. 返回 JSON，播放地址藏在 `url` / `data.url` / 甚至更深的层级里
///   3. 返回纯文本，内容就是一个地址
///
/// 所以这里不猜、三条都试，谁先出结果算谁。判定成功与否靠
/// [StreamParsing.looksLikeStreamUrl]（必须 http 开头且是 m3u8/mp4/flv），
/// 而不是接口自报的 `code` —— 那个字段各家定义不一。
///
/// 响应体的解析在 `StreamParsing.parseParseResponse`（纯函数，可离线验证）。
class ParseSourceClient {
  static const timeout = Duration(seconds: 15);

  /// 判定一个字符串像不像播放地址（转发到纯函数）
  static bool looksLikeStream(String value) =>
      StreamParsing.looksLikeStreamUrl(value);

  /// 用某个解析源解析目标地址。失败返回 null。
  static Future<ParsedStream?> parse(
    ParseSource source,
    String targetUrl,
  ) async {
    final requestUrl = source.buildRequestUrl(targetUrl);

    try {
      final response = await DioFactory.apiDio.request<dynamic>(
        requestUrl,
        data: source.post ? {'url': targetUrl.trim()} : null,
        options: Options(
          method: source.post ? 'POST' : 'GET',
          responseType: ResponseType.plain,
          headers: {
            ...source.requestHeaders,
            'Accept': '*/*',
          },
          // 302 跳转本身就是答案，别跟着走
          followRedirects: false,
          validateStatus: (status) => status == null || status < 500,
          receiveTimeout: timeout,
          sendTimeout: timeout,
        ),
      );

      final redirect = _redirectTarget(response, requestUrl);
      if (redirect != null) return ParsedStream(url: redirect);

      final data = response.data;
      final text = data is String ? data : (data == null ? '' : '$data');
      final parsed = StreamParsing.parseParseResponse(text, requestUrl);
      if (parsed == null) return null;
      return ParsedStream(url: parsed.url, headers: parsed.headers);
    } catch (_) {
      return null;
    }
  }

  /// 3xx 的 `Location`。
  static String? _redirectTarget(Response<dynamic> response, String requestUrl) {
    final status = response.statusCode ?? 0;
    if (status < 300 || status >= 400) return null;

    final raw = response.headers.value('location');
    if (raw == null || raw.trim().isEmpty) return null;

    final target = raw.trim();
    if (looksLikeStream(target)) return target;

    // 相对 Location 要按请求地址补全
    final absolute = StreamParsing.absolutize(target, requestUrl);
    if (absolute == null) return null;
    return looksLikeStream(absolute) ? absolute : null;
  }
}
