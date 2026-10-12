/// 观看记录来自哪个模块。
///
/// **为什么需要这个标记**：动漫模块与影视模块走的是**同一套**采集源播放链路
/// （动漫页 → `/movie-detail/` → `/video/`），观看进度都落在
/// `MovieHistoryService` 里 —— 光看记录本身（sourceKey/vodId/片名）根本分不出
/// 「这条是动漫还是电影」。所以从入口页把来源带下来，随记录一起落盘，
/// 「我的 → 观看记录」才能分成电影 / 动漫两个列表展示。
///
/// ⚠️ 历史记录是**后加**的字段：老记录里没有 `origin`，[resolve] 统一按
/// [movie] 处理，保证老数据照样能读出来、且默认归入电影列表（它们本来就是
/// 从影视 Tab 看过的）。
class MovieOrigin {
  MovieOrigin._();

  /// 影视 Tab 进入的播放（电影 / 剧集 / 综艺 / 纪录片…）
  static const String movie = 'movie';

  /// 动漫 Tab 进入的播放
  static const String anime = 'anime';

  /// 归一化：只认 [anime]，其余（含缺失、脏数据）一律当 [movie]。
  static String resolve(Object? raw) => raw == anime ? anime : movie;

  /// 展示名。
  static String label(String origin) => origin == anime ? '动漫' : '影视';
}
