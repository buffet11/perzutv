import 'dart:convert';

/// 影视地址解析里的**纯逻辑** —— 不碰网络、不依赖 Flutter。
///
/// 单独放一个文件是为了能离线验证：`WebStreamScraper` 和 `ParseSourceClient`
/// 都要走 Dio，而 Dio 要经过 `DioFactory -> GStorage -> path_provider`，
/// 纯 Dart VM 跑不起来。把「从 HTML 里抠地址」「从解析接口的响应里抠地址」
/// 这类判断留在这里，就能用 `dart run` 直接对着真实抓下来的页面测。
///
/// （与 `AppleCmsApi.parseSearchPage` 那组公开纯函数是同一个思路。）
class StreamParsing {
  StreamParsing._();

  /// 播放地址的后缀。m3u8 是绝对主力，mp4/flv 是少数源给的。
  static const streamSuffixes = ['.m3u8', '.mp4', '.flv'];

  static const defaultCandidateLimit = 6;

  /// 一个字符串像不像播放地址。
  static bool looksLikeStreamUrl(String value) {
    final v = value.trim().toLowerCase();
    if (!v.startsWith('http')) return false;
    return streamSuffixes.any(v.contains);
  }

  /// 把页面/响应里出现的地址补成绝对地址。补不出来返回 null。
  ///
  /// 支持：绝对地址、`//host/path`（协议相对）、`/path`（根相对）。
  /// 更复杂的相对形式（`../x.m3u8`）只在有明确基准时才算 —— 猜错的地址
  /// 比没有地址更糟，后面还要多一次失败的请求。
  static String? absolutize(String raw, String baseUrl) {
    final base = Uri.tryParse(baseUrl.trim());
    if (base == null || !base.hasScheme || base.host.isEmpty) return null;

    var candidate = raw.trim();
    if (candidate.isEmpty) return null;
    if (candidate.startsWith('//')) candidate = '${base.scheme}:$candidate';

    final uri = Uri.tryParse(candidate);
    if (uri == null) return null;

    if (uri.hasScheme) {
      return uri.host.isEmpty ? null : uri.toString();
    }
    // 没有 scheme 时 Uri 会把第一个路径段当 host，所以要看原始字符串
    if (!candidate.startsWith('/')) {
      final resolved = base.resolveUri(uri);
      return resolved.hasScheme ? resolved.toString() : null;
    }
    return base.resolveUri(uri).toString();
  }

  /// 网页里的播放地址：绝对地址，或根相对路径，或协议相对地址。
  ///
  /// 前缀那个字符类是为了跳过 `"`、`'`、`(` 之类紧贴在 URL 前的符号，
  /// 用捕获组取真正的 URL。
  static final RegExp _htmlCandidatePattern = RegExp(
    r'''["'\s(=]((?:https?:)?//[^"'\s\\)<>]+?\.(?:m3u8|mp4|flv)(?:\?[^"'\s\\)<>]*)?|/[^"'\s\\)<>]+?\.(?:m3u8|mp4|flv)(?:\?[^"'\s\\)<>]*)?)''',
    caseSensitive: false,
  );

  /// 从网页 HTML 里抽出候选播放地址（补成绝对地址、去重、保持出现顺序）。
  static List<String> extractCandidates(
    String html,
    String pageUrl, {
    int limit = defaultCandidateLimit,
  }) {
    if (html.isEmpty) return const <String>[];

    // JS 字符串里常见 `\/`，HTML 里常见 `&amp;`，先还原再找
    final text = html.replaceAll(r'\/', '/').replaceAll('&amp;', '&');

    final out = <String>[];
    final seen = <String>{};
    for (final match in _htmlCandidatePattern.allMatches(text)) {
      final raw = match.group(1)?.trim();
      if (raw == null || raw.isEmpty) continue;
      final absolute = absolutize(raw, pageUrl);
      if (absolute == null) continue;
      if (!seen.add(absolute)) continue;
      out.add(absolute);
      if (out.length >= limit) break;
    }
    return out;
  }

  /// 解析接口的响应体 -> 播放地址（+ 接口给的请求头）。
  ///
  /// 接口协议没有标准，实测至少三种：JSON（地址藏在 `url` / `data.url` /
  /// 更深的层级）、纯文本（正文就是地址）、以及 3xx 跳转（在 client 侧处理）。
  /// 这里覆盖前两种。返回 null 表示没找到。
  static ({String url, Map<String, String> headers})? parseParseResponse(
    String body,
    String requestUrl,
  ) {
    final text = body.trim();
    if (text.isEmpty) return null;

    final decoded = tryJson(text);
    if (decoded != null) {
      final url = findStreamUrl(decoded);
      if (url == null) return null;
      final absolute = absolutize(url, requestUrl) ?? url;
      if (!looksLikeStreamUrl(absolute)) return null;
      return (url: absolute, headers: findHeaders(decoded));
    }

    // 整个 body 就是一个地址
    if (looksLikeStreamUrl(text)) {
      return (url: text, headers: const <String, String>{});
    }

    // 正文里夹着一个地址
    final found = firstStreamSubstring(text);
    if (found == null) return null;
    final absolute = absolutize(found, requestUrl) ?? found;
    return (url: absolute, headers: const <String, String>{});
  }

  /// 在 JSON 里找播放地址。
  ///
  /// 先看常见键（别把无关字段里的地址捞出来），都不中再深度遍历 ——
  /// 有些接口把地址埋在 `data.list[0].play_url` 这种地方，
  /// 所以**数组也必须遍历**（这里踩过一次：只看 Map 不看 List，
  /// `{"data":{"list":[{"play_url":"..."}]}}` 就挖不到）。
  static String? findStreamUrl(dynamic node, [int depth = 0]) {
    if (depth > 8) return null;
    if (node is String) {
      return looksLikeStreamUrl(node) ? node.trim() : null;
    }
    if (node is List) {
      for (final item in node) {
        final hit = findStreamUrl(item, depth + 1);
        if (hit != null) return hit;
      }
      return null;
    }
    if (node is! Map) return null;

    const preferred = [
      'url',
      'playUrl',
      'play_url',
      'playurl',
      'm3u8',
      'src',
      'video',
      'data',
      'result',
    ];
    for (final key in preferred) {
      final value = node[key];
      if (value == null) continue;
      final hit = findStreamUrl(value, depth + 1);
      if (hit != null) return hit;
    }

    for (final value in node.values) {
      final hit = findStreamUrl(value, depth + 1);
      if (hit != null) return hit;
    }
    return null;
  }

  /// 找接口一并给出的自定义请求头。有些接口返回的地址要带特定 Referer
  /// 才能播，缺了它用户看到的就是黑屏。
  ///
  /// 同样要深度遍历 —— 实测常见的形状是 `{"data":{"url":"...",
  /// "header":{...}}}`，header 并不在顶层。
  static Map<String, String> findHeaders(dynamic node, [int depth = 0]) {
    if (depth > 8) return const {};

    if (node is List) {
      for (final item in node) {
        final hit = findHeaders(item, depth + 1);
        if (hit.isNotEmpty) return hit;
      }
      return const {};
    }
    if (node is! Map) return const {};

    for (final key in const ['header', 'headers', 'httpHeaders']) {
      final value = node[key];
      if (value is Map) {
        final out = <String, String>{};
        value.forEach((k, v) {
          if (k is String && v != null) out[k] = '$v';
        });
        if (out.isNotEmpty) return out;
      }
    }

    for (final value in node.values) {
      if (value is Map || value is List) {
        final hit = findHeaders(value, depth + 1);
        if (hit.isNotEmpty) return hit;
      }
    }
    return const {};
  }

  /// 正文里第一个播放地址子串。
  ///
  /// 用 `\x22` 表示双引号 —— 这样整条正则能放进原始字符串，
  /// 不必为了引号去转义（Dart 的原始字符串里写不了两种引号）。
  static String? firstStreamSubstring(String text) {
    final match = RegExp(
      r"https?://[^\s\x22'<>\\]+?\.(?:m3u8|mp4|flv)[^\s\x22'<>\\]*",
      caseSensitive: false,
    ).firstMatch(text);
    return match?.group(0);
  }

  /// 宽松的 JSON 解析：有的接口在 JSON 前后带提示文字。
  static dynamic tryJson(String text) {
    try {
      return jsonDecode(text);
    } catch (_) {
      final start = text.indexOf('{');
      final end = text.lastIndexOf('}');
      if (start >= 0 && end > start) {
        try {
          return jsonDecode(text.substring(start, end + 1));
        } catch (_) {}
      }
      return null;
    }
  }
}
