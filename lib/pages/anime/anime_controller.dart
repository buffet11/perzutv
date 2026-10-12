import 'package:flutter/foundation.dart';
import 'package:perzutv/modules/movie/movie_category.dart';
import 'package:perzutv/modules/movie/movie_item.dart';
import 'package:perzutv/services/movie/anime_catalog_service.dart';

/// 「动漫」Tab 的状态。
///
/// 与影视模块同源（苹果 CMS 采集源），但这里是「按分区翻列表」而不是「关键词搜索」，
/// 所以单独一个控制器，不塞进 `MovieController`（两者生命周期与筛选维度都不同）。
///
/// 用 [ChangeNotifier] 而不是 MobX：MobX 要跑 build_runner 生成 `.g.dart`，
/// 而本机（中文 Windows，ANSI 代码页 936）跑不了 `dart run`，详见
/// `movie_controller.dart` 顶部同款说明。
class AnimeController extends ChangeNotifier {
  /// 可用分区（第一个永远是「全部动漫」）。
  List<AnimePartition> partitions = const [AnimePartition.all];

  /// 当前选中的分区。
  AnimePartition selected = AnimePartition.all;

  /// 已加载的条目（跨页累加、按 [MovieSearchItem.uniqueKey] 去重）。
  List<MovieSearchItem> items = const [];

  /// 首屏 / 换分区时的整页加载。
  bool loading = false;

  /// 加载下一页中。
  bool loadingMore = false;

  /// 整体错误（探测失败、网络异常等）；null 表示无错。
  String? errorMessage;

  /// 是否还有下一页。拉到的页为空即置 false。
  bool hasMore = true;

  /// 已加载到第几页（1 起；0 表示还没加载过）。
  int _page = 0;

  /// 见过的 [MovieSearchItem.uniqueKey]，用于跨页去重。
  final Set<String> _seen = <String>{};

  /// [init] 只跑一次：控制器是模块级单例，Tab 来回切换不该重拉第一页。
  bool _initialized = false;

  /// 参与探测的采集源数量（UI 上显示「来自 N 个采集源」）。
  int get sourceCount => AnimeCatalogService.sourceCount;

  /// 首次进入页面时调用：探分区 → 拉当前分区第一页。
  ///
  /// 分两步：**先用磁盘快照点亮界面**（纯本地、毫秒级），再后台真实刷新。
  /// 这样第二次打开不会先盯着转圈等网络。
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    await AnimeCatalogService.restoreCache();
    if (AnimeCatalogService.ready) _syncPartitions();
    _showCached(selected);
    notifyListeners();

    await _loadFirstPage();
  }

  /// 切换分区：清空现有列表后重拉第一页。
  void selectPartition(AnimePartition partition) {
    if (partition.id == selected.id) return;
    selected = partition;
    items = const [];
    errorMessage = null;
    hasMore = true;
    _page = 0;
    _seen.clear();
    // 该分区有快照就先显示，避免切过去一片空白
    _showCached(partition);
    notifyListeners();
    // 不 await：切换要立刻反映到 UI（选中态已 notifyListeners）。
    _loadFirstPage();
  }

  /// 手动刷新：先让分区缓存失效（用户可能刚改了源开关），再重拉第一页。
  Future<void> refresh() async {
    AnimeCatalogService.invalidate();
    await _loadFirstPage(force: true);
  }

  /// 用磁盘快照填充列表；有内容返回 true。
  ///
  /// 只影响展示与分页基准，不产生网络请求 —— 随后的 [_loadFirstPage] 会用
  /// 真实数据覆盖它。
  bool _showCached(AnimePartition partition) {
    final cached = AnimeCatalogService.cachedFeed(partition);
    if (cached.isEmpty) return false;
    items = cached;
    _seen
      ..clear()
      ..addAll(cached.map((item) => item.uniqueKey));
    _page = 1;
    hasMore = true;
    return true;
  }

  /// 拉下一页（滚动到底部自动触发）。空页即认为到底。
  Future<void> loadMore() async {
    if (loading || loadingMore || !hasMore) return;
    loadingMore = true;
    notifyListeners();
    try {
      final page = await AnimeCatalogService.loadFeed(selected, _page + 1);
      if (page.isEmpty) {
        hasMore = false;
      } else {
        final added = <MovieSearchItem>[];
        for (final item in page) {
          if (_seen.add(item.uniqueKey)) added.add(item);
        }
        items = [...items, ...added];
        _page += 1;
        hasMore = true;
      }
      errorMessage = null;
    } catch (e) {
      // 分页失败只提示，不清空已有内容（列表还在，用户可继续看）。
      errorMessage = _describe(e);
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  Future<void> _loadFirstPage({bool force = false}) async {
    loading = true;
    errorMessage = null;
    hasMore = true;
    notifyListeners();
    try {
      await AnimeCatalogService.ensurePartitions(force: force);
      _syncPartitions();
      final page = await AnimeCatalogService.loadFeed(selected, 1);
      _page = 1;
      final out = <MovieSearchItem>[];
      final seen = <String>{};
      for (final item in page) {
        if (seen.add(item.uniqueKey)) out.add(item);
      }
      if (out.isEmpty && items.isNotEmpty) {
        // 源站这次一条都没给（分类接口不稳是常态）：保留快照内容，
        // 别把用户已经看到的列表擦成空白。
        hasMore = false;
      } else {
        _seen
          ..clear()
          ..addAll(seen);
        items = out;
        hasMore = out.isNotEmpty;
      }
    } catch (e) {
      errorMessage = _describe(e);
      // 同样保留已有内容（快照或上次的结果）；本来就是空的才置空状态
      if (items.isEmpty) {
        items = const [];
        hasMore = false;
      }
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 用服务层最新分区刷新本地列表；当前选中分区若已不存在则回落到第一个。
  void _syncPartitions() {
    final next = AnimeCatalogService.availablePartitions;
    partitions = next;
    if (!next.any((p) => p.id == selected.id)) {
      selected = next.isNotEmpty ? next.first : AnimePartition.all;
    }
  }

  static String _describe(Object error) {
    final text = error.toString();
    return text.length <= 160 ? text : '${text.substring(0, 160)}…';
  }
}
