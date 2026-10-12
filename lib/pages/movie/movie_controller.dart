import 'package:flutter/foundation.dart';
import 'package:perzutv/modules/movie/movie_history.dart';
import 'package:perzutv/modules/movie/movie_item.dart';
import 'package:perzutv/modules/movie/movie_origin.dart';
import 'package:perzutv/modules/movie/movie_source.dart';
import 'package:perzutv/services/movie/movie_history_service.dart';
import 'package:perzutv/services/movie/movie_search_service.dart';
import 'package:perzutv/services/movie/movie_source_manager.dart';
import 'package:perzutv/services/storage/storage.dart';

/// 影视 Tab 的状态。
///
/// 用 [ChangeNotifier] 而不是 MobX：MobX 要跑 build_runner 生成 `.g.dart`，
/// 而生成步骤要求 `dart run` 能构建本包的 native assets —— 在中文 Windows
/// （ANSI 代码页 936）上这会因 native_toolchain_c 的缺陷而失败。
/// 新页面不必背这个包袱，`ListenableBuilder` 足够。
class MovieController extends ChangeNotifier {
  /// 搜索历史。走 `putStringListSettingByName`，不必往 SettingsKeys 里加键。
  static const historyKey = 'movieSearchHistory';

  static const historyLimit = 12;

  bool searching = false;

  /// 最近一次搜索结果；null 表示还没搜过
  SearchOutcome? outcome;

  /// 整体性错误（某几个源失败不算，那些记在 [failures] 里）
  String? errorMessage;

  /// 当前只看某个源；null / 空串表示全看
  String? sourceFilter;

  String keyword = '';

  /// 观看历史（最近的在前），供初始态的「继续观看」区块使用。
  ///
  /// 复用已有的 [MovieHistoryService]，不新建存储 —— 里面的
  /// `MoviePlayProgress` 已带片名、封面、进度，足够直接渲染卡片。
  /// 首次为 `const []`（还没读过盘），[loadWatchHistory] 之后才有内容。
  List<MoviePlayProgress> watchHistory = const [];

  /// 搜索历史。
  ///
  /// ⚠️ 必须**复制一份**再交给调用方。没有任何历史时
  /// `getStringListSettingByName` 返回的是方法签名上的默认值 `const []` ——
  /// 一个**不可变**列表，对它 `..remove()` 会抛
  /// `Unsupported operation: Cannot remove from an unmodifiable list`。
  List<String> get history =>
      List<String>.of(GStorage.getStringListSettingByName(historyKey));

  List<MovieSource> get sources => MovieSourceManager.enabled();

  bool get noSourceEnabled => sources.isEmpty;

  bool get hasSearched => outcome != null;

  /// 当前筛选后的结果
  List<MovieSearchItem> get items {
    final all = outcome?.items ?? const <MovieSearchItem>[];
    final filter = sourceFilter;
    if (filter == null || filter.isEmpty) return all;
    return all.where((item) => item.sourceKey == filter).toList();
  }

  List<SourceFailure> get failures => outcome?.failures ?? const [];

  /// 全源都失败（区别于「都成功但没搜到」）
  bool get allFailed => outcome?.allFailed ?? false;

  /// 每个源命中多少条 —— 筛选条上要显示数量，否则用户不知道哪个源有货
  Map<String, int> get countBySource {
    final map = <String, int>{};
    for (final item in outcome?.items ?? const <MovieSearchItem>[]) {
      map[item.sourceKey] = (map[item.sourceKey] ?? 0) + 1;
    }
    return map;
  }

  /// 参与本次搜索的源（含失败的），用于筛选条
  List<MovieSource> get searchedSources {
    final keys = <String>{
      ...?outcome?.items.map((e) => e.sourceKey),
      ...failures.map((e) => e.sourceKey),
    };
    return sources.where((s) => keys.contains(s.key)).toList();
  }

  Future<void> search(String raw) async {
    final kw = raw.trim();
    if (kw.isEmpty) return;

    keyword = kw;
    searching = true;
    errorMessage = null;
    sourceFilter = null;
    notifyListeners();

    try {
      outcome = await MovieSearchService.searchAll(kw, sources: sources);
    } catch (e) {
      outcome = null;
      errorMessage = _describe(e);
    } finally {
      searching = false;
      notifyListeners();
    }

    // 历史写入单独兜住：它只是锦上添花，失败了不该把搜索结果一起吞掉。
    // （之前就是这里抛异常，被上面那个 catch 抓住，导致明明搜到了却显示「搜索失败」。）
    try {
      await _remember(kw);
    } catch (_) {
      // 忽略：历史没记上不影响本次搜索
    }
  }

  void setSourceFilter(String? key) {
    final next = (key == null || key.isEmpty) ? null : key;
    if (next == sourceFilter) return;
    sourceFilter = next;
    notifyListeners();
  }

  /// 清空搜索结果，回到初始态（保留关键词输入框内容由页面自己管）
  void clearResult() {
    outcome = null;
    errorMessage = null;
    sourceFilter = null;
    notifyListeners();
  }

  Future<void> removeHistory(String kw) async {
    final list = history;
    list.remove(kw);
    await GStorage.putStringListSettingByName(historyKey, list);
    notifyListeners();
  }

  Future<void> clearHistory() async {
    await GStorage.putStringListSettingByName(historyKey, <String>[]);
    notifyListeners();
  }

  /// 读取观看历史（进入页面、以及从详情/播放页返回时各调一次）。
  ///
  /// **只取影视来源的记录**：动漫模块走的是同一条播放链路，也写同一份历史，
  /// 但它的记录属于「动漫」列表（见「我的 → 观看记录」），不该混进影视首页的
  /// 「继续观看」里。
  ///
  /// 读盘失败只降级为空列表，不抛 —— 历史读不出来不该把整个影视页搞崩。
  Future<void> loadWatchHistory() async {
    List<MoviePlayProgress> list;
    try {
      list = MovieHistoryService.all(origin: MovieOrigin.movie);
    } catch (_) {
      list = const <MoviePlayProgress>[];
    }
    watchHistory = list;
    notifyListeners();
  }

  /// 把一条播放历史还原成搜索结果条目，作为影视详情页的 arguments。
  ///
  /// 历史里**有** sourceKey / vodId / name(片名) / coverUrl(封面)，所以能直接
  /// 拼出 [MovieSearchItem]，不必再打一次源站接口（详情页自己会拉详情）。
  /// 历史里**没有** sourceName / typeName / year / area / remarks / score /
  /// isAdult —— 这些是搜索结果独有的，留默认值即可。其中 sourceName 用源列表
  /// 里的显示名补上（源被删/停用就退回 sourceKey，至少不是空白）。
  MovieSearchItem toSearchItem(MoviePlayProgress progress) {
    return MovieSearchItem(
      sourceKey: progress.sourceKey,
      sourceName: _sourceNameOf(progress.sourceKey),
      vodId: progress.vodId,
      name: progress.name,
      pic: progress.coverUrl,
    );
  }

  /// 按 key 找源的显示名；找不到就用 key 本身兜底。
  static String _sourceNameOf(String key) {
    for (final source in MovieSourceManager.all()) {
      if (source.key == key) return source.name;
    }
    return key;
  }

  Future<void> _remember(String kw) async {
    // 先取一份可变的副本，再动它 —— 见 history getter 的注释
    final list = history;
    list.remove(kw);
    list.insert(0, kw);
    if (list.length > historyLimit) {
      list.removeRange(historyLimit, list.length);
    }
    await GStorage.putStringListSettingByName(historyKey, list);
  }

  static String _describe(Object error) {
    final text = error.toString();
    return text.length <= 160 ? text : '${text.substring(0, 160)}…';
  }
}
