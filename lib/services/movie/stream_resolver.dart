import 'package:perzutv/modules/movie/parse_source.dart';
import 'package:perzutv/services/logging/logger.dart';
import 'package:perzutv/services/movie/parse_source_client.dart';
import 'package:perzutv/services/movie/parse_source_manager.dart';
import 'package:perzutv/services/movie/web_stream_scraper.dart';

/// 解析结果。
class ResolvedStream {
  /// 真正的播放地址
  final String url;

  /// 播放时该带上的请求头（多为 Referer）
  final Map<String, String> headers;

  /// 走的哪条路，用于日志与界面提示
  final String via;

  const ResolvedStream({
    required this.url,
    this.headers = const {},
    required this.via,
  });

  @override
  String toString() => 'ResolvedStream($via -> $url)';
}

/// 把「网页地址」换成「播放器能打开的地址」。
///
/// 两条路，按顺序试：
///
///   1. **网页解析**（`WebStreamScraper`）—— 直接抓页面里的 m3u8。
///      采集站自己的播放页（`/play/xxx`、`/share/xxx`）都吃这一套，
///      不需要任何第三方，也不需要用户配置。
///   2. **解析源**（用户自己填的接口）—— 给平台播放页（腾讯/爱奇艺/优酷）
///      准备的。我们不内置。
///
/// 顺序是有讲究的：**已知是平台页面时跳过网页解析**，因为那种页面的 HTML
/// 有几 MB、里面的 `.m3u8` 多半是别的视频的残留，抓它既慢又容易抓错。
class StreamResolver {
  StreamResolver._();

  /// 一次最多试几个解析源。接口可能很慢，全试一遍等不起。
  static const maxParseSources = 3;

  /// 成功结果的缓存时长。
  ///
  /// 解析出来的地址常带 `?sign=...` 这类签名，会过期，所以缓存不能长。
  /// 但同一集反复进出播放页时（比如误按返回）能省一次往返。
  static const _cacheTtl = Duration(minutes: 10);

  /// 失败结果的缓存时长 —— 只是为了避免短时间内反复重试同一个死地址。
  static const _failureTtl = Duration(seconds: 45);

  static final Map<String, _CacheEntry> _cache = {};

  /// 已知的视频平台播放页。
  ///
  /// 这些不需要（也不该）走网页解析：页面是 JS 渲染的重型 SPA，
  /// 真正的地址要么靠解析接口，要么根本拿不到。
  static const List<String> _platformHosts = [
    'v.qq.com',
    'qq.com',
    'iqiyi.com',
    'qiyi.com',
    'youku.com',
    'mgtv.com',
    'bilibili.com',
    'sohu.com',
    'pptv.com',
    'le.com',
    '1905.com',
    'wasu.cn',
  ];

  static bool isPlatformPage(String url) {
    final host = Uri.tryParse(url.trim())?.host ?? '';
    if (host.isEmpty) return false;
    return _platformHosts.any((h) => host == h || host.endsWith('.$h'));
  }

  /// 现在有没有可能解析出东西。
  ///
  /// 网页解析是内置能力，所以只要地址不是平台页就**总是**有可能；
  /// 平台页则必须有用户配置的解析源。
  static bool canResolve(String url) {
    if (isDirectUrl(url)) return true;
    if (!isPlatformPage(url)) return true;
    return ParseSourceManager.hasEnabled;
  }

  /// 解析。已经直链则原样返回。
  static Future<ResolvedStream?> resolve(String pageUrl) async {
    final target = pageUrl.trim();
    if (target.isEmpty) return null;

    if (isDirectUrl(target)) {
      return ResolvedStream(url: target, via: '直链');
    }
    if (!target.startsWith('http')) return null;

    final cached = _fromCache(target);
    if (cached != null) return cached;

    final result = await _resolveUncached(target);
    _cache[target] = _CacheEntry(
      result,
      DateTime.now().add(result == null ? _failureTtl : _cacheTtl),
    );
    return result;
  }

  static Future<ResolvedStream?> _resolveUncached(String target) async {
    // 1. 网页解析（平台页跳过）
    if (!isPlatformPage(target)) {
      final scraped = await WebStreamScraper.resolve(target);
      if (scraped != null) {
        return ResolvedStream(
          url: scraped.url,
          // 播放时带上页面地址当 Referer —— CDN 常按它做防盗链
          headers: {'referer': scraped.referer},
          via: '网页解析',
        );
      }
    }

    // 2. 用户的解析源
    final sources = ParseSourceManager.enabled().take(maxParseSources);
    for (final source in sources) {
      final parsed = await ParseSourceClient.parse(source, target);
      if (parsed == null) continue;
      KazumiLogger().i('StreamResolver: ${source.name} 解析成功 -> ${parsed.url}');
      return ResolvedStream(
        url: parsed.url,
        headers: parsed.headers,
        via: source.name,
      );
    }

    return null;
  }

  /// 单个解析源的连通性测试（设置页用）。
  ///
  /// 与 [resolve] 不同：**只试这一个源**，返回结果或失败原因，
  /// 便于用户判断自己填的接口到底行不行。
  static Future<({bool ok, String message, String url})> test(
    ParseSource source,
    String targetUrl,
  ) async {
    final sw = Stopwatch()..start();
    final parsed = await ParseSourceClient.parse(source, targetUrl);
    sw.stop();

    if (parsed == null) {
      return (
        ok: false,
        message: '没拿到播放地址（${sw.elapsedMilliseconds} ms）',
        url: '',
      );
    }
    return (
      ok: true,
      message: '成功（${sw.elapsedMilliseconds} ms）',
      url: parsed.url,
    );
  }

  /// 是不是已经可以直接交给播放器的地址。
  static bool isDirectUrl(String url) {
    final v = url.trim().toLowerCase();
    if (!v.startsWith('http')) return false;
    return _streamSuffixes.any(v.contains);
  }

  static const _streamSuffixes = ['.m3u8', '.mp4', '.flv'];

  static ResolvedStream? _fromCache(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiresAt)) {
      _cache.remove(key);
      return null;
    }
    return entry.value;
  }

  /// 清缓存（换解析源设置后调用）
  static void clearCache() => _cache.clear();
}

class _CacheEntry {
  final ResolvedStream? value;
  final DateTime expiresAt;

  const _CacheEntry(this.value, this.expiresAt);
}
