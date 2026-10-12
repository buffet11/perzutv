import 'dart:async';

import 'package:perzutv/modules/movie/movie_category.dart';
import 'package:perzutv/modules/movie/movie_item.dart';
import 'package:perzutv/modules/movie/movie_source.dart';
import 'package:perzutv/request/apis/apple_cms_api.dart';
import 'package:perzutv/services/logging/logger.dart';
import 'package:perzutv/services/movie/anime_catalog_cache.dart';
import 'package:perzutv/services/movie/movie_source_manager.dart';

/// 「动漫」模块的数据层。
///
/// 动漫模块不依赖 Bangumi 元数据，而是**直接用采集源的动漫分区**：
///   1. [ensurePartitions] 并发拉每个启用源的分类树（`ac=list`），
///      把各站五花八门的分区名（动漫片 / 国产动漫 / 动画片 …）归一成
///      [AnimePartition]，并记下「统一分区 → 各源具体 typeId」的映射；
///   2. [loadFeed] 按统一分区并发向各源要列表（`ac=detail&t=<typeId>`），
///      跨源合并、按片名去重后轮询交错，得到一个能直接点开播放的动漫流。
///
/// 这样点进去就能播（走影视那套详情页 + 解析链），不需要再去番剧插件里找源。
class AnimeCatalogService {
  AnimeCatalogService._();

  /// 最多同时参与的源数量。请求数是「源数 × 分区数」，这里做个上限，
  /// 免得用户开了十几个源后一进页面就打几十个请求。
  static const maxSources = 6;

  /// 「全部动漫」每个源最多拼几个地区子分区。
  ///
  /// 取 1 会显得"全部"名不副实（只有国产），取 3 以上请求数翻倍，
  /// 折中取 2：既有跨地区内容，请求数也还压得住。
  static const _allPartitionTargetsPerSource = 2;

  /// 单次从每个源取的条数上限（源站 limit 通常是 20，这里不额外限制）。
  static const _probeTimeout = Duration(seconds: 10);

  /// 分区映射缓存（进程内）。源列表变化或手动刷新时重建。
  static Map<String, List<PartitionTarget>>? _targets;
  static DateTime? _builtAt;

  /// 探测后确定「真正带动漫分区」的源（已按优劣排序，最多 [maxSources] 个）。
  ///
  /// ⚠️ 不能拿「启用的前 N 个源」直接用：源是按延迟排序的，排前面的几个
  /// （电影天堂、360 等）未必提供动漫分类，那样动漫页会空着。所以先探测
  /// **所有**候选源，再筛掉没有动漫分区的，才轮到数量上限。
  static List<MovieSource> _animeSources = const [];

  /// 已经确认「拉不出内容」的「源 × 分区」组合，key = `sourceKey:typeId`。
  ///
  /// 为什么要记：多数采集站的「按分类取列表」接口是残的（实测 360 / 电影天堂 /
  /// 百度 三种 ac 形式全返回空），不记的话每次翻页都白等一轮超时。
  /// ⚠️ 只有「接口正常响应但确实没条目」才记；超时/网络失败不记（那是暂时性的）。
  static final Set<String> _deadTargets = <String>{};

  /// 缓存有效期：分类树基本不变，10 分钟内不重复探测。
  static const _cacheTtl = Duration(minutes: 10);

  /// 本次探测里真正拿到分区的源（界面上可以显示「来自 N 个源」）。
  static int _sourceCount = 0;

  static int get sourceCount => _sourceCount;

  /// 可用的统一分区（按 [AnimePartition.ordered] 排序，只保留有源的）。
  static List<AnimePartition> get availablePartitions {
    final targets = _targets;
    if (targets == null) return const [AnimePartition.all];
    final out = <AnimePartition>[];
    for (final partition in AnimePartition.ordered) {
      if ((targets[partition.id] ?? const []).isNotEmpty) out.add(partition);
    }
    // 一个分区都没探到也要给「全部动漫」，否则界面没法渲染
    return out.isEmpty ? const [AnimePartition.all] : out;
  }

  static bool get ready => _targets != null;

  /// 磁盘快照里某个分区的第一页（没有则空列表）。
  ///
  /// 给「先渲染、后刷新」用：控制器拿它先把列表铺出来，再走 [loadFeed] 更新。
  static List<MovieSearchItem> cachedFeed(AnimePartition partition) =>
      AnimeCatalogCache.itemsFor(partition.id);

  /// 用磁盘快照预热：恢复分区映射与源清单，**不发任何网络请求**。
  ///
  /// 拿到的只是"上次看到的样子"，随后的 [loadFeed] 仍会真实拉取并覆盖它。
  /// 任何失败都静默返回，调用方不需要区分成功与否（用 [ready] 判断即可）。
  static Future<void> restoreCache() async {
    if (_targets != null) return;
    await AnimeCatalogCache.load();
    if (!AnimeCatalogCache.loaded) return;

    final rawTargets = AnimeCatalogCache.targets;
    if (rawTargets.isEmpty) return;

    // 快照里的源可能已被用户停用/删除 —— 这类目标直接丢弃，别用它去请求
    final byKey = <String, MovieSource>{
      for (final source in MovieSourceManager.all()) source.key: source,
    };
    final restoredSources = <MovieSource>[];
    final map = <String, List<PartitionTarget>>{};
    for (final entry in rawTargets.entries) {
      final list = <PartitionTarget>[];
      for (final target in entry.value) {
        final source = byKey[target.sourceKey];
        final usable = source != null &&
            (source.enabled || source.highQuality) &&
            source.isUsable &&
            !source.isAdult;
        if (!usable) continue;
        list.add(target);
        if (!restoredSources.contains(source)) restoredSources.add(source);
      }
      if (list.isNotEmpty) map[entry.key] = list;
    }
    if (map.isEmpty) return;

    _targets = map;
    _animeSources = restoredSources;
    _sourceCount = AnimeCatalogCache.sourceCount;
    // 用快照时间当探测时间：超过 TTL 时下次 ensurePartitions 会自动重新探测，
    // 未超过就省掉一轮分类树请求。
    _builtAt = AnimeCatalogCache.savedAt ?? DateTime.now();
    KazumiLogger().i(
        'AnimeCatalog: warmed up from snapshot（${map.length} partitions, '
        '${restoredSources.length} sources）');
  }

  /// 清除缓存（用户改动了源开关 / 手动刷新时调用）。
  ///
  /// 磁盘快照**不删**：里面还有上次成功的分区映射，重探失败时还能退回旧数据；
  /// 而且 [restoreCache] 会按当前源配置过滤，不存在"用到已停用源"的问题。
  static void invalidate() {
    _targets = null;
    _builtAt = null;
    _resetSources();
  }

  /// 探测各源的动漫分区，建立「统一分区 → (源, typeId)」映射。
  ///
  /// 失败按源隔离：某个源分类树拿不到，只是不参与分区浏览，不影响其它源。
  static Future<void> ensurePartitions({bool force = false}) async {
    final builtAt = _builtAt;
    if (!force &&
        _targets != null &&
        builtAt != null &&
        DateTime.now().difference(builtAt) < _cacheTtl) {
      return;
    }

    // 探测**所有**候选源（不只是前几个），否则可能一个带动漫分区的都挑不出来
    final probed = _allUsableSources();
    final perSource = <MovieSource, Map<String, String>>{};
    final perSourceAll = <MovieSource, List<String>>{};

    await Future.wait(probed.map((source) async {
      List<CmsCategory> categories;
      try {
        categories = await AppleCmsApi.listCategories(source)
            .timeout(_probeTimeout);
      } catch (e) {
        KazumiLogger().w(
            'AnimeCatalog: category probe failed for ${source.name}', error: e);
        return;
      }
      if (categories.isEmpty) return;

      // 归一化：分区 id → 该源对应的 typeId
      final byPartition = <String, String>{};
      final regions = <String, String>{}; // 只有地区子分区
      String? neutralAll; // 中性总类目（动漫片 / 动画片，不含地区）
      for (final category in categories) {
        final partition = AnimePartition.fromTypeName(category.typeName);
        if (partition == null) continue;
        if (partition == AnimePartition.all) {
          neutralAll ??= category.typeId;
        } else {
          byPartition.putIfAbsent(partition.id, () => category.typeId);
          regions.putIfAbsent(partition.id, () => category.typeId);
        }
      }
      if (byPartition.isEmpty && neutralAll == null) return;

      // 「全部动漫」怎么拼 —— **别用总类目**。
      //
      // 实测（2026-10-09，360/量子）：这些采集站的总类目（`动漫(4)` /
      // `动漫片(4)`）是**空壳**，三种 ac 形式都返回 0 条（量子那行只回 1 条），
      // 而内容全挂在地区子分区（国产动漫/日韩动漫/欧美动漫）下，各 20 条带封面。
      // 所以这里改为：拿该源的**地区子分区**拼「全部动漫」，每个源最多取
      // [_allPartitionTargetsPerSource] 个；一个都没有时才退回总类目。
      final regionOrder = [
        AnimePartition.cn.id,
        AnimePartition.jpKr.id,
        AnimePartition.usEu.id,
        AnimePartition.hkTw.id,
        AnimePartition.other.id,
      ];
      final allIds = <String>[];
      for (final id in regionOrder) {
        final typeId = regions[id];
        if (typeId != null && !allIds.contains(typeId)) {
          allIds.add(typeId);
        }
        if (allIds.length >= _allPartitionTargetsPerSource) break;
      }
      if (allIds.isEmpty && neutralAll != null) allIds.add(neutralAll);
      if (allIds.isEmpty && regions.isNotEmpty) {
        allIds.add(regions.values.first);
      }

      for (final typeId in allIds) {
        (perSourceAll[source] ??= <String>[]).add(typeId);
      }
      perSource[source] = byPartition;
    }));

    // 排序：地区子分区多的源优先（它们才有货），其次保持原顺序。
    final ranked = perSourceAll.keys.toList()
      ..sort((a, b) {
        final ca = perSourceAll[a]!.length;
        final cb = perSourceAll[b]!.length;
        if (ca != cb) return cb - ca;
        return probed.indexOf(a) - probed.indexOf(b);
      });

    final chosen = ranked.take(maxSources).toList();
    final map = <String, List<PartitionTarget>>{};
    for (final source in chosen) {
      // 「全部动漫」：该源的 1~2 个地区子分区
      for (final typeId in perSourceAll[source]!) {
        (map[AnimePartition.all.id] ??= <PartitionTarget>[]).add(
          PartitionTarget(sourceKey: source.key, typeId: typeId),
        );
      }
      // 其余分区：一一对应
      for (final entry in perSource[source]!.entries) {
        (map[entry.key] ??= <PartitionTarget>[]).add(PartitionTarget(
          sourceKey: source.key,
          typeId: entry.value,
        ));
      }
    }

    _animeSources = chosen;
    _targets = map;
    _sourceCount = chosen.length;
    _builtAt = DateTime.now();
    KazumiLogger().i(
        'AnimeCatalog: partitions ready, ${chosen.length}/${probed.length} sources '
        'contribute（${chosen.map((s) => s.name).join('、')}）');

    // 落盘：下次启动先用这份映射把界面点亮，不必等分类树探测
    unawaited(AnimeCatalogCache.saveTargets(
      sourceKeys: chosen.map((s) => s.key).toList(),
      targets: map,
      sourceCount: chosen.length,
    ));
  }

  /// 拉某个统一分区的一页动漫。
  ///
  /// [page] 从 1 开始。返回已经跨源去重、轮询交错的列表（顺序稳定）。
  static Future<List<MovieSearchItem>> loadFeed(
    AnimePartition partition,
    int page,
  ) async {
    await ensurePartitions();
    final targets = _targets?[partition.id] ?? const <PartitionTarget>[];
    if (targets.isEmpty) return const [];

    final byKey = <String, MovieSource>{
      for (final source in _animeSources) source.key: source,
    };

    // 每个源一个桶，保留源站自己的排序（通常是最近更新在前）。
    // 用下标当 key 收集：并发返回的顺序不确定，按 key 取回来才能保证
    // 每次渲染的源交替顺序一致。
    final bucketsByIndex = <int, List<MovieSearchItem>>{};
    final live = <int, PartitionTarget>{};
    for (var i = 0; i < targets.length; i++) {
      final target = targets[i];
      if (_deadTargets.contains('${target.sourceKey}:${target.typeId}')) continue;
      live[i] = target;
    }
    if (live.isEmpty) {
      KazumiLogger().i('AnimeCatalog: all targets for ${partition.label} are dead');
      return const [];
    }

    await Future.wait(live.entries.map((entry) async {
      final index = entry.key;
      final target = entry.value;
      final source = byKey[target.sourceKey];
      if (source == null) return;
      try {
        final result = await AppleCmsApi.tryListByCategory(
          source,
          target.typeId,
          page,
        );
        if (result == null) {
          // 全部接口形式都失败（超时/网络）→ 暂时性，别拉黑
          KazumiLogger().w(
              'AnimeCatalog: feed transient failure for ${source.name}/${target.typeId}');
          return;
        }
        if (result.items.isEmpty) {
          // 接口正常响应但没内容 → 这个组合没戏，记住并跳过
          _deadTargets.add('${target.sourceKey}:${target.typeId}');
          KazumiLogger().i(
              'AnimeCatalog: ${source.name}/${target.typeId} has no items, marking dead');
          return;
        }
        bucketsByIndex[index] = result.items;
      } catch (e) {
        KazumiLogger().w(
            'AnimeCatalog: feed failed for ${source.name}/${target.typeId}',
            error: e);
      }
    }));

    final buckets = [
      for (var i = 0; i < targets.length; i++)
        if (bucketsByIndex[i] != null) bucketsByIndex[i]!,
    ];
    final merged = _mergeByRoundRobin(buckets);

    // 第一页就是"首屏"，缓存它 —— 下次启动能直接显示。
    // 翻页数据不缓存（量大、时效短、收益低）。
    if (page == 1 && merged.isNotEmpty) {
      unawaited(AnimeCatalogCache.saveFeed(partition.id, merged));
    }
    return merged;
  }

  /// 轮询交错多个源的列表，并按片名去重。
  ///
  /// 为什么要去重：同一部动漫在多个采集源都存在，直接拼接会出现连排重复；
  /// 为什么轮询而不是拼接：拼接会让第一页全是同一个源的内容。
  static List<MovieSearchItem> _mergeByRoundRobin(
      List<List<MovieSearchItem>> buckets) {
    final seen = <String>{};
    final out = <MovieSearchItem>[];
    var index = 0;
    var added = true;
    while (added) {
      added = false;
      for (final bucket in buckets) {
        if (index >= bucket.length) continue;
        final item = bucket[index];
        final key = _dedupeKey(item.name);
        if (key.isNotEmpty && seen.add(key)) {
          out.add(item);
        }
        added = true;
      }
      index++;
    }
    return out;
  }

  /// 片名归一化：去掉季数后缀差异与空白，避免「斗罗大陆」和「斗罗大陆 第1季」
  /// 被当成两部片子。
  static String _dedupeKey(String name) {
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[\s\-_:：·]'), '')
        .replaceAll(RegExp(r'第[一二三四五六七八九十0-9]+季'), '')
        .trim();
  }

  /// 全部可参与动漫模块的候选源。
  ///
  /// 关键：**高画质源也算在内，不跟着「高画质源总开关」走**。
  /// 那个开关管的是"搜索时别用慢源"，而动漫模块是浏览式列表 —— 而实测能真正
  /// 返回分区列表的恰恰是非凡资源这类高画质源（它们是动漫内容的主力）。
  /// 全按开关排掉的话，动漫页会几乎没内容。
  static List<MovieSource> _allUsableSources() {
    return MovieSourceManager.all()
        .where((s) => (s.enabled || s.highQuality) && s.isUsable && !s.isAdult)
        .toList();
  }

  /// 清空缓存时一并丢掉源清单。
  static void _resetSources() {
    _animeSources = const [];
    _deadTargets.clear();
  }
}
