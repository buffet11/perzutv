/// 解析源（「解析接口」）。
///
/// 用途：有些播放地址**不是直链**，而是视频平台的播放页（`v.qq.com` /
/// `iqiyi.com` / `youku.com` …）或采集站自己的中转页。这类地址交给播放器
/// 只会黑屏，需要一个「解析服务」把它换成真正的 m3u8。
///
/// 我们不内置任何解析接口，也没法内置 —— 它们大多是第三方搭的、生命周期短，
/// 而且合法性存疑（本质是绕过平台会员）。所以走 TVBOX 生态同一套做法：
/// **接口由用户自己填**，能力在用户手里。
///
/// 字段与 TVBOX 配置里的 `parses` 对齐（`api` 对应它的 `url`），这样可以
/// 直接从 TVBOX 配置导入、也能导出回去。
class ParseSource {
  /// 唯一标识：`parse_0` / `imported_parse_0` / `tvbox_parse_0`
  final String key;

  /// 显示名，如「聚合解析」
  final String name;

  /// 接口地址。支持两种写法：
  ///
  ///   含 `{url}` 占位符   `https://x.com/jx?target={url}`  -> 直接替换
  ///   不含占位符          `https://x.com/jx?url=`          -> 末尾追加编码后的目标地址
  ///
  /// 后者是 TVBOX 配置里最常见的写法（接口地址以 `?url=` 结尾）。
  final String api;

  /// 用 POST 提交（少数接口如此）。默认 GET。
  ///
  /// POST 时目标地址放表单字段 `url`。
  final bool post;

  /// 请求时带的 Referer。有些接口会校验。
  final String referer;

  /// 是否参与解析
  final bool enabled;

  /// 展示顺序
  final int order;

  /// 最近一次解析成功的时间戳。**0 = 从未测试过，-1 = 测试过但失败**。
  final int lastOkAt;

  /// 最近一次解析耗时毫秒（-1 = 失败）
  final int lastLatencyMs;

  const ParseSource({
    required this.key,
    required this.name,
    required this.api,
    this.post = false,
    this.referer = '',
    this.enabled = true,
    this.order = 0,
    this.lastOkAt = 0,
    this.lastLatencyMs = -1,
  });

  bool get isUsable => key.isNotEmpty && name.isNotEmpty && api.trim().isNotEmpty;

  /// 把目标地址拼成实际请求的 URL。
  ///
  /// 三种情况（TVBOX 的接口写法不止一种，都得认）：
  ///   1. 含 `{url}`          -> 替换
  ///   2. 以 `=` / `?` / `&` 结尾 -> 直接追加编码后的地址
  ///      （`https://x.com/?url=` 这种最常见）
  ///   3. 其余               -> 按已有查询串决定用 `?` 还是 `&`
  String buildRequestUrl(String target) {
    final encoded = Uri.encodeComponent(target.trim());
    final base = api.trim();
    if (base.contains('{url}')) {
      return base.replaceAll('{url}', encoded);
    }
    if (base.endsWith('=') || base.endsWith('?') || base.endsWith('&')) {
      return '$base$encoded';
    }
    if (base.contains('?')) return '$base&url=$encoded';
    return '$base?url=$encoded';
  }

  Map<String, String> get requestHeaders => {
        if (referer.trim().isNotEmpty) 'referer': referer.trim(),
      };

  ParseSource copyWith({
    String? key,
    String? name,
    String? api,
    bool? post,
    String? referer,
    bool? enabled,
    int? order,
    int? lastOkAt,
    int? lastLatencyMs,
  }) {
    return ParseSource(
      key: key ?? this.key,
      name: name ?? this.name,
      api: api ?? this.api,
      post: post ?? this.post,
      referer: referer ?? this.referer,
      enabled: enabled ?? this.enabled,
      order: order ?? this.order,
      lastOkAt: lastOkAt ?? this.lastOkAt,
      lastLatencyMs: lastLatencyMs ?? this.lastLatencyMs,
    );
  }

  /// 从 JSON 构造。兼容我们自己的持久化格式、TVBOX 的 `parses` 条目、
  /// 以及通用的 `{name, url}` 简单格式。
  factory ParseSource.fromJson(
    Map<String, dynamic> json, {
    required String key,
    int order = 0,
  }) {
    String pick(List<String> names) {
      for (final n in names) {
        final v = json[n];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
      return '';
    }

    // TVBOX 的 ext 里可能挂着 header / flag，取 header.Referer 或 header.Referrer
    var referer = '';
    final ext = json['ext'];
    if (ext is Map) {
      final header = ext['header'];
      if (header is Map) {
        final r = header['Referer'] ?? header['referer'] ?? header['Referrer'];
        if (r is String) referer = r.trim();
      }
    }

    final rawType = json['type'];
    final post = json['post'] == true ||
        json['method']?.toString().toLowerCase() == 'post' ||
        rawType?.toString() == 'post';

    return ParseSource(
      key: key,
      name: pick(['name', 'title', 'key']),
      api: pick(['api', 'url']),
      post: post,
      referer: referer.isNotEmpty ? referer : pick(['referer', 'referrer']),
      enabled: json['enabled'] != false,
      order: order,
    );
  }

  /// 导出 / 持久化。
  ///
  /// 与 `MovieSource` 一样，这份 JSON 同时用于落盘和导出，所以
  /// **每个字段都必须带上**，否则重启就丢。
  Map<String, dynamic> toJson() => {
        'name': name,
        'url': api,
        if (post) 'post': true,
        if (referer.trim().isNotEmpty) 'referer': referer.trim(),
        if (!enabled) 'enabled': false,
      };

  @override
  String toString() => 'ParseSource($key, $name, $api)';
}
