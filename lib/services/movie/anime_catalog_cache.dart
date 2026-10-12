import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:perzutv/modules/movie/movie_category.dart';
import 'package:perzutv/modules/movie/movie_item.dart';
import 'package:perzutv/services/logging/logger.dart';

/// 「动漫」列表的磁盘快照。
///
/// 为什么需要：动漫页的数据要**先跨源探测分类树、再并发拉分区列表**，首次进入
/// 通常要几秒（慢源更久）。把「分区映射 + 各分区第一页」落盘后，下次启动可以
/// 先用快照把界面点亮，再在后台静默刷新 —— 用户感受到的就是"秒开"。
///
/// 设计取舍：
/// - **只缓存第一页**：翻页数据量大、时效性强，缓存收益低还容易把文件撑大。
/// - **过期即弃**：超过 [maxAge] 的快照不加载（采集源片单变化快，陈旧数据
///   比空列表更糟 —— 用户会点进已经下架的条目）。
/// - **全程静默**：任何 IO / 解析异常只记日志，绝不打断主流程。缓存是加速器，
///   不是数据源，没有它也必须能正常工作。
class AnimeCatalogCache {
  AnimeCatalogCache._();

  static const _fileName = 'anime_catalog_cache.json';
  static const _version = 1;

  /// 快照最长可用时间。
  static const maxAge = Duration(days: 3);

  /// 每个分区最多缓存多少条（源站一页通常 20~40 条，留些余量）。
  static const maxItemsPerPartition = 60;

  static Map<String, dynamic>? _doc;

  /// 快照是否已成功载入（未载入 / 已过期 / 文件损坏都为 false）。
  static bool get loaded => _doc != null;

  /// 快照保存时间；无快照时为 null。
  static DateTime? get savedAt {
    final ms = _doc?['savedAt'];
    return ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
  }

  /// 快照里记录的源 key（有序，决定跨源交错顺序）。
  static List<String> get sourceKeys {
    final raw = _doc?['sourceKeys'];
    if (raw is! List) return const [];
    return raw.whereType<String>().toList();
  }

  /// 参与探测的源数量（UI 上「来自 N 个采集源」用）。
  static int get sourceCount {
    final value = _doc?['sourceCount'];
    return value is int ? value : 0;
  }

  /// 分区映射：`partitionId -> [(sourceKey, typeId), ...]`。
  static Map<String, List<PartitionTarget>> get targets {
    final raw = _doc?['targets'];
    if (raw is! Map) return const {};
    final out = <String, List<PartitionTarget>>{};
    for (final entry in raw.entries) {
      final items = <PartitionTarget>[];
      for (final item in (entry.value as List? ?? const [])) {
        if (item is! Map) continue;
        final sourceKey = item['s'];
        final typeId = item['t'];
        if (sourceKey is String && typeId is String && sourceKey.isNotEmpty) {
          items.add(PartitionTarget(sourceKey: sourceKey, typeId: typeId));
        }
      }
      if (items.isNotEmpty) out['${entry.key}'] = items;
    }
    return out;
  }

  /// 某个分区的第一页快照；没有或全是脏数据时返回空列表。
  static List<MovieSearchItem> itemsFor(String partitionId) {
    final raw = _doc?['feeds'];
    if (raw is! Map) return const [];
    final list = raw[partitionId];
    if (list is! List) return const [];
    final out = <MovieSearchItem>[];
    for (final item in list) {
      if (item is! Map) continue;
      try {
        out.add(MovieSearchItem.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // 单条脏数据不该毁掉整份快照
      }
    }
    return out;
  }

  /// 读取磁盘快照（进程内只读一次）。
  static Future<void> load() async {
    if (_doc != null) return;
    try {
      final file = await _file();
      if (!file.existsSync()) return;
      final text = await file.readAsString();
      if (text.trim().isEmpty) return;

      final json = jsonDecode(text);
      if (json is! Map) return;
      final doc = Map<String, dynamic>.from(json);
      if (doc['version'] != _version) return;

      final savedAtMs = doc['savedAt'];
      if (savedAtMs is! int) return;
      final age = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(savedAtMs),
      );
      if (age > maxAge) {
        KazumiLogger().i('AnimeCatalogCache: snapshot too old ($age), ignored');
        return;
      }

      _doc = doc;
      KazumiLogger().i(
          'AnimeCatalogCache: loaded snapshot (saved ${savedAtMs ~/ 1000}, '
          '${targets.length} partitions)');
    } catch (e) {
      KazumiLogger().w('AnimeCatalogCache: load failed', error: e);
    }
  }

  /// 保存「分区映射」（分类树探测成功后调用）。
  ///
  /// 只更新映射，不动已缓存的列表 —— 探测成功、列表还没回来时也得能落盘。
  static Future<void> saveTargets({
    required List<String> sourceKeys,
    required Map<String, List<PartitionTarget>> targets,
    required int sourceCount,
  }) async {
    try {
      final previousFeeds = _doc?['feeds'];
      _doc = {
        'version': _version,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
        'sourceCount': sourceCount,
        'sourceKeys': sourceKeys,
        'targets': {
          for (final entry in targets.entries)
            entry.key: [
              for (final target in entry.value)
                {'s': target.sourceKey, 't': target.typeId},
            ],
        },
        // 列表跟着新的映射走：源变了以后旧列表可能已经对不上，先清掉
        'feeds': previousFeeds is Map ? previousFeeds : <String, dynamic>{},
      };
      await _write();
    } catch (e) {
      KazumiLogger().w('AnimeCatalogCache: saveTargets failed', error: e);
    }
  }

  /// 保存某个分区的第一页（拉取成功后调用）。
  static Future<void> saveFeed(
    String partitionId,
    List<MovieSearchItem> items,
  ) async {
    final doc = _doc;
    if (doc == null || items.isEmpty) return;
    try {
      final feeds = doc['feeds'];
      final map = feeds is Map
          ? Map<String, dynamic>.from(feeds)
          : <String, dynamic>{};
      map[partitionId] = [
        for (final item in items.take(maxItemsPerPartition)) item.toJson(),
      ];
      doc['feeds'] = map;
      doc['savedAt'] = DateTime.now().millisecondsSinceEpoch;
      await _write();
    } catch (e) {
      KazumiLogger().w('AnimeCatalogCache: saveFeed failed', error: e);
    }
  }

  /// 丢弃快照（进程内与磁盘都清）。
  static Future<void> clear() async {
    _doc = null;
    try {
      final file = await _file();
      if (file.existsSync()) await file.delete();
    } catch (e) {
      KazumiLogger().w('AnimeCatalogCache: clear failed', error: e);
    }
  }

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<void> _write() async {
    final doc = _doc;
    if (doc == null) return;
    final file = await _file();
    // 先写临时文件再替换：避免写入过程中被强杀留下半截 JSON
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(doc), flush: true);
    if (file.existsSync()) await file.delete();
    await tmp.rename(file.path);
  }
}
