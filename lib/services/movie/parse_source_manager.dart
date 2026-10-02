import 'dart:convert';

import 'package:kazutv/modules/movie/parse_source.dart';
import 'package:kazutv/services/storage/storage.dart';

/// 解析源管理：持久化、增删改、导入。
///
/// **没有内置源** —— 解析接口大多是第三方搭的、生命周期短、合法性存疑
/// （本质是绕过平台会员），我们不提供也不推荐任何具体接口。
/// 能力在用户手里：自己填、自己负责。TVBOX 生态就是这么做。
///
/// 存储用 `Box<String>` 存 JSON 数组，与影视源一致 —— 绕开 Hive adapter
/// 的代码生成步骤（本机跑不了 build_runner）。
class ParseSourceManager {
  ParseSourceManager._();

  static const _boxKey = 'list';

  static List<ParseSource>? _cache;

  // ------------------------------------------------------------ 读写

  static List<ParseSource> all() {
    if (_cache != null) return _cache!;
    final raw = GStorage.parseSources.get(_boxKey);
    if (raw == null || raw.trim().isEmpty) {
      _cache = const [];
      return _cache!;
    }
    _cache = parseJson(raw);
    return _cache!;
  }

  /// 参与解析的源，按 order 排序
  static List<ParseSource> enabled() {
    final list = all().where((s) => s.enabled && s.isUsable).toList();
    list.sort((a, b) => a.order.compareTo(b.order));
    return list;
  }

  static bool get hasEnabled => enabled().isNotEmpty;

  static void _persist() {
    GStorage.parseSources.put(_boxKey, encodeJson(_cache ?? const []));
  }

  static void _setAll(List<ParseSource> list) {
    for (var i = 0; i < list.length; i++) {
      list[i] = list[i].copyWith(order: i);
    }
    _cache = list;
    _persist();
  }

  // ------------------------------------------------------------ 增删改

  /// 追加。api 重复会被拒（返回 null）。
  static ParseSource? add({
    required String name,
    required String api,
    bool post = false,
    String referer = '',
  }) {
    final normalized = api.trim();
    if (name.trim().isEmpty || normalized.isEmpty) return null;
    final list = [...all()];
    if (list.any((s) => s.api.trim() == normalized)) return null;

    final source = ParseSource(
      key: _nextKey(list),
      name: name.trim(),
      api: normalized,
      post: post,
      referer: referer.trim(),
      order: list.length,
    );
    list.add(source);
    _setAll(list);
    return source;
  }

  static bool update(ParseSource source) {
    final list = [...all()];
    final i = list.indexWhere((s) => s.key == source.key);
    if (i < 0) return false;
    list[i] = source;
    _setAll(list);
    return true;
  }

  static bool remove(String key) {
    final list = [...all()];
    final before = list.length;
    list.removeWhere((s) => s.key == key);
    if (list.length == before) return false;
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

  /// 记录一次测试结果（UI 上显示「上次成功」/「上次失败」/「未测试」）。
  ///
  /// 失败时把 `lastOkAt` 置 -1 而不是留着 0 —— 0 的含义是「从没测过」，
  /// 不区分的话失败之后界面会退回显示「未测试」，看着像没点动。
  static void noteResult(String key, {required bool ok, required int latencyMs}) {
    final list = [...all()];
    final i = list.indexWhere((s) => s.key == key);
    if (i < 0) return;
    list[i] = list[i].copyWith(
      lastOkAt: ok ? DateTime.now().millisecondsSinceEpoch : -1,
      lastLatencyMs: ok ? latencyMs : -1,
    );
    _setAll(list);
  }

  static String _nextKey(List<ParseSource> list) {
    var i = 0;
    while (list.any((s) => s.key == 'parse_$i')) {
      i++;
    }
    return 'parse_$i';
  }

  // ------------------------------------------------------------ 导入导出

  /// 解析 JSON。兼容三种外形：
  ///   - 我们自己的导出：`{parses: [...]}`
  ///   - TVBOX 配置：`{parses: [...]}`（同一个键，字段名不同）
  ///   - 顶层数组
  static List<ParseSource> parseJson(
    String raw, {
    String keyPrefix = 'imported_parse',
    bool dedupeByApi = true,
  }) {
    final decoded = _decode(raw);
    if (decoded == null) return const [];

    List<dynamic>? entries;
    if (decoded is List) {
      entries = decoded;
    } else if (decoded is Map) {
      for (final k in const ['parses', 'list', 'data', 'sources']) {
        final v = decoded[k];
        if (v is List) {
          entries = v;
          break;
        }
      }
    }
    if (entries == null) return const [];

    final out = <ParseSource>[];
    final seen = <String>{};
    var i = 0;
    for (final e in entries) {
      if (e is! Map) continue;
      final source = ParseSource.fromJson(
        Map<String, dynamic>.from(e),
        key: '${keyPrefix}_$i',
        order: i,
      );
      if (!source.isUsable) continue;
      if (dedupeByApi && !seen.add(source.api.trim())) continue;
      out.add(source);
      i++;
    }
    return out;
  }

  /// 从 TVBOX 配置里取 `parses` 段。
  ///
  /// 注意**只取接口本身，不采信它的 type 语义** —— TVBOX 的 type 取值各版本
  /// 含义不一，我们统一按「GET，地址里带 url 参数」处理，判断不了的情况
  /// 交给用户自己测。
  static List<ParseSource> parseTvboxJson(
    String raw, {
    String keyPrefix = 'tvbox_parse',
  }) {
    final decoded = _decode(raw);
    if (decoded is! Map) return const [];
    final parses = decoded['parses'];
    if (parses is! List) return const [];
    return parseJson(
      jsonEncode({'parses': parses}),
      keyPrefix: keyPrefix,
    );
  }

  /// 合并导入（按 api 去重）
  static int mergeImport(List<ParseSource> incoming) {
    final list = [...all()];
    final existing = list.map((s) => s.api.trim()).toSet();
    var added = 0;
    for (final s in incoming) {
      if (!existing.add(s.api.trim())) continue;
      list.add(s.copyWith(key: _nextKey(list), order: list.length));
      added++;
    }
    if (added > 0) _setAll(list);
    return added;
  }

  static String encodeJson(List<ParseSource> sources) {
    return const JsonEncoder.withIndent('  ').convert({
      'parses': sources.map((s) => s.toJson()).toList(),
    });
  }

  static String exportJson() => encodeJson(all());

  // ------------------------------------------------------------ 工具

  static dynamic _decode(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
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

  /// 测试用：清内存缓存
  static void clearCache() => _cache = null;
}
