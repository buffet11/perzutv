import 'package:dio/dio.dart';
import 'package:perzutv/request/core/dio_factory.dart';
import 'package:perzutv/services/logging/logger.dart';
import 'package:perzutv/services/movie/movie_stream_parsing.dart';

/// 从网页里解析出来的可播地址。
class WebStream {
  /// 真正的播放地址（m3u8 / mp4 / flv）
  final String url;

  /// 抓取它的那个页面 —— 播放时通常要把它当 Referer 发出去
  final String referer;

  const WebStream({required this.url, required this.referer});

  @override
  String toString() => 'WebStream($url)';
}

/// 从「网页播放页」里抠出真正的播放地址。
///
/// 为什么需要它：采集站的线路分两种 ——
///   `xxxm3u8`  给的直接就是 m3u8 直链；
///   `xxx云`    给的是**网页播放页**（`/play/xxx`、`/share/xxx`），
///              播放器打开它只会看到一页 HTML。
///
/// 实测（2026-10-02）这类页面的规律很统一：HTML 里直接写着 m3u8 地址，
/// 要么是绝对的（`https://v.gsuus.com/play/e1wwYPGb/index.m3u8`），
/// 要么是根相对路径（`/20250505/5821_926c11cc/index.m3u8?sign=...`），
/// 后者按页面 origin 补全即可。**不需要任何第三方解析接口**。
///
/// 这一步能救回每个源的一条线路 —— 实测 13 个源里有 9 个的「云」线路是这样
/// 拿回来的（`v.gsuus.com`、`vv.jisuzyv.com`、`hn.bfvvs.com`、`1080p.huyall.com`、
/// `play.hhuus.com`、`hd.kuktxu.com`、`vip.dytt-live.com`、`vip.lzcdn2.com` …）。
/// 例外是「非凡资源」那个页面返回空 body，拿不到。
///
/// 两个刻意的做法：
///
/// **1. 抽出来之后一定去校验。** 光靠正则从 HTML 里抠 URL 会捞到假货
/// （JS 里的模板、示例、别的清晰度的残留）。所以候选地址要真的请求一次，
/// **必须以 `#EXTM3U` 开头才算数**。多一次请求，换来的是不会把用户送到一个
/// 必然黑屏的地址上。
///
/// **2. 只接受绝对地址和根相对路径。** `../foo.m3u8` 这类没有可靠基准，
/// 与其猜一个不如不要。
class WebStreamScraper {
  WebStreamScraper._();

  /// 页面抓取超时。这类页面很小（实测 1~3 KB），给 10 秒足够。
  static const pageTimeout = Duration(seconds: 10);

  /// 校验候选地址的超时
  static const probeTimeout = Duration(seconds: 8);

  /// 一页最多校验几个候选，防止页面里有几十个 URL 时逐个去试
  static const maxCandidates = StreamParsing.defaultCandidateLimit;

  /// 抽候选 —— 转发到纯函数，便于离线验证。
  static List<String> extractCandidates(
    String html,
    String pageUrl, {
    int limit = maxCandidates,
  }) =>
      StreamParsing.extractCandidates(html, pageUrl, limit: limit);

  /// 抓页面 -> 抽候选 -> 逐个校验，返回第一个真正可播的地址。
  ///
  /// 失败（页面拿不到 / 一个候选都不成立）返回 null。
  static Future<WebStream?> resolve(String pageUrl) async {
    final html = await _fetchPage(pageUrl);
    if (html == null || html.isEmpty) {
      KazumiLogger().d('WebStreamScraper: 页面为空 $pageUrl');
      return null;
    }

    final candidates = extractCandidates(html, pageUrl);
    KazumiLogger().d(
      'WebStreamScraper: $pageUrl -> ${candidates.length} 个候选',
    );

    for (final candidate in candidates) {
      if (await _isPlayable(candidate)) {
        KazumiLogger().i('WebStreamScraper: 命中 $candidate');
        return WebStream(url: candidate, referer: pageUrl);
      }
    }
    return null;
  }

  /// 候选地址是否真的能播。
  ///
  /// 只认 `#EXTM3U` —— 那才是 HLS 播放列表。
  static Future<bool> _isPlayable(String url) async {
    try {
      final response = await DioFactory.apiDio.get<List<int>>(
        url,
        options: Options(
          responseType: ResponseType.bytes,
          // 只要开头一段就够判断，别把整个列表拉下来
          headers: {'Range': 'bytes=0-2047', 'Accept': '*/*'},
          receiveTimeout: probeTimeout,
          sendTimeout: probeTimeout,
        ),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) return false;
      final head = String.fromCharCodes(bytes.take(2048));
      return head.contains('#EXTM3U');
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _fetchPage(String url) async {
    try {
      final response = await DioFactory.apiDio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          headers: {'Accept': 'text/html,application/xhtml+xml,*/*'},
          receiveTimeout: pageTimeout,
          sendTimeout: pageTimeout,
        ),
      );
      return response.data;
    } catch (e) {
      KazumiLogger().d('WebStreamScraper: 页面抓取失败 $url ($e)');
      return null;
    }
  }
}
