import 'dart:convert';

import 'package:kazutv/modules/movie/builtin_movie_sources.dart';
import 'package:kazutv/modules/movie/movie_source.dart';
import 'package:kazutv/request/apis/apple_cms_api.dart';
import 'package:kazutv/services/storage/settings_keys.dart';
import 'package:kazutv/services/storage/storage.dart';

/// 探活结果。
class ProbeResult {
  final bool ok;

  /// 成功时是响应耗时，失败为 -1
  final int latencyMs;

  /// 失败原因（成功时为空）
  final String message;

  const ProbeResult({required this.ok, required this.latencyMs, this.message = ''});

  /// UI 上显示成「正常 120ms / 超时 / 失败」
  String get label {
    if (!ok) return message.isEmpty ? '失败' : message;
    if (latencyMs < 1000) return '正常 $latencyMs ms';
    return '正常 ${(latencyMs / 1000).toStringAsFixed(1)} s';
  }

  @override
  String toString() => ok ? 'OK ${latencyMs}ms' : 'FAIL $message';
}

/// 影视源管理：持久化、增删改、探活、导入导出、URL 订阅。
///
/// 存储用 `Box<String>` 存 JSON 数组（见 GStorage.movieSources 的注释）。
class MovieSourceManager {
  MovieSourceManager._();

  static const _boxKey = 'list';

  /// 内存缓存，避免每次都读 Hive。
  static List<MovieSource>? _cache;

  // ------------------------------------------------------------ 读写

  /// 取全部源（含未启用的）。首次运行会落一份内置源。
  static List<MovieSource> all() {
    if (_cache != null) return _cache!;
    final raw = GStorage.movieSources.get(_boxKey);
    if (raw == null || raw.trim().isEmpty) {
      _cache = builtinMovieSources();
      _persist();
      return _cache!;
    }
    final parsed = parseSourceListJson(raw);
    if (parsed.isEmpty) {
      _cache = builtinMovieSources();
      _persist();
      return _cache!;
    }
    final merged = _mergeMissingBuiltins(parsed);
    if (merged.length != parsed.length) {
      // 补齐了就顺手归一化 order 并落盘，免得每次启动都重算
      _setAll(merged);
      return _cache!;
    }
    _cache = parsed;
    return _cache!;
  }

  /// 补齐缺失的内置源。
  ///
  /// 老版本存下的列表里没有后来新增的内置源（比如高画质那一组），
  /// 不补的话它们永远不会出现 —— 用户也没法在设置里看到开关有什么用。
  /// 只做「新增」，不动用户已有的启停/改名/顺序。
  static List<MovieSource> _mergeMissingBuiltins(List<MovieSource> existing) {
    final have = existing.map((s) => s.key).toSet();
    final missing = builtinMovieSources().where((s) => !have.contains(s.key));
    if (missing.isEmpty) return existing;
    return [...existing, ...missing];
  }

  /// 高画质源是否启用（设置里的总开关）。
  static bool get highQualityEnabled =>
      GStorage.getSetting(SettingsKeys.enableHighQualityMovieSources);

  static Future<void> setHighQualityEnabled(bool value) async {
    await GStorage.putSetting(
      SettingsKeys.enableHighQualityMovieSources,
      value,
    );
  }

  /// 参与聚合搜索的源，按 order 排序。
  ///
  /// **高画质源还要过一道总开关**：关着时它们完全不参与（不管自己是不是
  /// 「启用」），这样用户不必逐个去关。
  static List<MovieSource> enabled() {
    final hqOn = highQualityEnabled;
    final list = all()
        .where((s) => s.enabled && s.isUsable && (!s.highQuality || hqOn))
        .toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  /// 普通源 / 高画质源，供设置界面分组展示。
  static List<MovieSource> normalSources() =>
      all().where((s) => !s.highQuality).toList();

  static List<MovieSource> highQualitySources() =>
      all().where((s) => s.highQuality).toList();

  static void _persist() {
    final list = _cache ?? [];
    GStorage.movieSources.put(_boxKey, toSourceListJson(list));
  }

  static void _setAll(List<MovieSource> list) {
    for (var i = 0; i < list.length; i++) {
      list[i] = list[i].copyWith(order: i);
    }
    _cache = list;
    _persist();
  }

  /// 供外部（导入、订阅）替换整份列表
  static void replaceAll(List<MovieSource> list) => _setAll(list);

  // ------------------------------------------------------------ 增删改

  /// 追加一个自定义源。key 自动生成，重复的 api 会被拒。
  static MovieSource? add({
    required String name,
    required String api,
    String detail = '',
    bool isAdult = false,
    bool highQuality = false,
  }) {
    final normalized = api.trim();
    if (name.trim().isEmpty || normalized.isEmpty) return null;
    final list = [...all()];
    if (list.any((s) => s.api.trim() == normalized)) return null;

    final source = MovieSource(
      key: _nextCustomKey(list),
      name: name.trim(),
      api: normalized,
      detail: detail.trim(),
      isAdult: isAdult,
      highQuality: highQuality,
      order: list.length,
    );
    list.add(source);
    _setAll(list);
    return source;
  }

  static bool update(MovieSource source) {
    final list = [...all()];
    final i = list.indexWhere((s) => s.key == source.key);
    if (i < 0) return false;
    list[i] = source;
    _setAll(list);
    return true;
  }

  static bool remove(String key) {
    // 内置源不可删 —— 界面已经挡了一道，这里再兜一道（它同时是
    // `_mergeMissingBuiltins` 的前提：内置源会在下次加载时被补回来，
    // 与其让用户「删了又出现」，不如直接告知不能删）。
    if (builtinMovieSourceKeys.contains(key)) return false;
    final list = [...all()];
    final before = list.length;
    list.removeWhere((s) => s.key == key);
    if (list.length == before) return false;
    _setAll(list);
    return true;
  }

  /// 把一个自定义源标记/取消「高画质」。
  static bool setHighQuality(String key, bool value) {
    final list = [...all()];
    final i = list.indexWhere((s) => s.key == key);
    if (i < 0) return false;
    list[i] = list[i].copyWith(highQuality: value);
    _setAll(list);
    return true;
  }

  static bool setEnabled(String key, bool enabled) {
    final list = [...all()];
    final i = list.indexWhere((s) => s.key == key);
    if (i < 0) return false;
    list[i] = list[i].copyWith(enabled: enabled);
    _setAll(list);
    return true;
  }

  /// 拖拽排序：把 from 位置的源挪到 to
  static void reorder(int from, int to) {
    final list = [...all()];
    if (from < 0 || from >= list.length) return;
    final item = list.removeAt(from);
    list.insert(to.clamp(0, list.length), item);
    _setAll(list);
  }

  /// 恢复内置源（不动自定义源）
  static void restoreBuiltin() {
    final customs = all().where((s) => !builtinMovieSourceKeys.contains(s.key)).toList();
    final merged = [...builtinMovieSources(), ...customs];
    _setAll(merged);
  }

  static String _nextCustomKey(List<MovieSource> list) {
    var i = 0;
    while (list.any((s) => s.key == 'custom_$i')) {
      i++;
    }
    return 'custom_$i';
  }

  // ------------------------------------------------------------ 探活

  /// 单源探活。用 `wd=test` 发一次最小搜索，量响应时间。
  static Future<ProbeResult> probe(MovieSource source) async {
    final sw = Stopwatch()..start();
    try {
      await AppleCmsApi.search(source, 'test', 1);
      sw.stop();
      final ms = sw.elapsedMilliseconds;
      // 顺带把结果写回列表，UI 可以显示「上次正常 120ms」
      final list = [...all()];
      final i = list.indexWhere((s) => s.key == source.key);
      if (i >= 0) {
        list[i] = list[i].copyWith(
          lastOkAt: DateTime.now().millisecondsSinceEpoch,
          lastLatencyMs: ms,
        );
        _setAll(list);
      }
      return ProbeResult(ok: true, latencyMs: ms);
    } catch (e) {
      sw.stop();
      final list = [...all()];
      final i = list.indexWhere((s) => s.key == source.key);
      if (i >= 0) {
        list[i] = list[i].copyWith(lastLatencyMs: -1);
        _setAll(list);
      }
      return ProbeResult(
        ok: false,
        latencyMs: -1,
        message: _short(e.toString()),
      );
    }
  }

  /// 批量探活（并发）
  static Future<Map<String, ProbeResult>> probeAll(List<MovieSource> sources) async {
    final result = <String, ProbeResult>{};
    await Future.wait(sources.map((s) async {
      result[s.key] = await probe(s);
    }));
    return result;
  }

  // ------------------------------------------------------------ 导入

  /// 解析「LibreTV 源列表」/ 通用源 JSON。
  ///
  /// 容忍三种外形：顶层数组、`{sources: [...]}`、`{list: [...]}`。
  /// 字段映射见 MovieSource.fromSourceListJson（`url` 与 `api` 都认）。
  static List<MovieSource> parseSourceListJson(
    String raw, {
    String keyPrefix = 'imported',
    bool dedupeByApi = true,
  }) {
    final decoded = _decodeJson(raw);
    if (decoded == null) return const [];

    List<dynamic>? entries;
    if (decoded is List) {
      entries = decoded;
    } else if (decoded is Map) {
      for (final k in const ['sources', 'list', 'data', 'sites']) {
        final v = decoded[k];
        if (v is List) {
          entries = v;
          break;
        }
      }
    }
    if (entries == null) return const [];

    final out = <MovieSource>[];
    final seenApi = <String>{};
    var i = 0;
    for (final e in entries) {
      if (e is! Map) continue;
      final source = MovieSource.fromSourceListJson(
        Map<String, dynamic>.from(e),
        key: '${keyPrefix}_$i',
        order: i,
      );
      if (!source.isUsable) continue;
      if (dedupeByApi && !seenApi.add(source.api.trim())) continue;
      out.add(source);
      i++;
    }
    return out;
  }

  /// 解析 TVBOX 配置，只取 `type == 1`（CMS 直连）的站点。
  static List<MovieSource> parseTvboxJson(String raw, {String keyPrefix = 'tvbox'}) {
    final decoded = _decodeJson(raw);
    if (decoded is! Map) return const [];
    final sites = decoded['sites'];
    if (sites is! List) return const [];

    final out = <MovieSource>[];
    final seenApi = <String>{};
    var i = 0;
    for (final e in sites) {
      if (e is! Map) continue;
      final site = Map<String, dynamic>.from(e);
      // type 1 = 苹果CMS 直连；其余（蜘蛛/解析/网盘）不适用
      final type = site['type'];
      if (type != null && type.toString() != '1') continue;

      final api = (site['api'] ?? '').toString().trim();
      final name = (site['name'] ?? site['key'] ?? '').toString().trim();
      if (api.isEmpty || name.isEmpty) continue;
      if (!seenApi.add(api)) continue;

      out.add(MovieSource(
        key: '${keyPrefix}_$i',
        name: name,
        api: api,
        detail: (site['ext'] ?? '').toString(),
        order: i,
      ));
      i++;
    }
    return out;
  }

  /// 自动识别格式并解析（JSON 就够，TVBOX 也是 JSON）
  static List<MovieSource> parseAnyJson(String raw, {String keyPrefix = 'imported'}) {
    final tvbox = parseTvboxJson(raw, keyPrefix: keyPrefix);
    if (tvbox.isNotEmpty) return tvbox;
    return parseSourceListJson(raw, keyPrefix: keyPrefix);
  }

  /// 合并导入（按 api 去重，跳过已存在的）
  static int mergeImport(List<MovieSource> incoming) {
    final list = [...all()];
    final existing = list.map((s) => s.api.trim()).toSet();
    var added = 0;
    for (final s in incoming) {
      if (!existing.add(s.api.trim())) continue;
      list.add(s.copyWith(key: _nextCustomKey(list), order: list.length));
      added++;
    }
    if (added > 0) _setAll(list);
    return added;
  }

  // ------------------------------------------------------------ 导出

  /// 导出成 LibreTV-SourceList 兼容的 JSON（对方可直接吃）。
  static String toSourceListJson(List<MovieSource> sources) {
    return const JsonEncoder.withIndent('  ').convert({
      'sources': sources.map((s) => s.toSourceListJson()).toList(),
    });
  }

  // ------------------------------------------------------------ 工具

  static dynamic _decodeJson(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    // 去掉 UTF-8 BOM，
    final cleaned = text.startsWith('\uFEFF') ? text.substring(1) : text;
    try {
      return jsonDecode(cleaned);
    } catch (_) {
      final start = cleaned.indexOf('[');
      final end = cleaned.lastIndexOf(']');
      if (start >= 0 && end > start) {
        try {
          return jsonDecode(cleaned.substring(start, end + 1));
        } catch (_) {}
      }
      return null;
    }
  }

  static String _short(String text) {
    if (text.length <= 60) return text;
    return '${text.substring(0, 60)}…';
  }

  /// 测试用：清掉内存缓存（不影响 Hive）
  static void clearCache() => _cache = null;
}
