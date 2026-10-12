import 'package:perzutv/modules/bangumi/bangumi_item.dart';
import 'package:perzutv/modules/download/download_module.dart';
import 'package:perzutv/modules/movie/movie_detail.dart';
import 'package:perzutv/modules/movie/movie_origin.dart';
import 'package:perzutv/modules/roads/road_module.dart';
import 'package:perzutv/plugins/plugins.dart';

/// Route arguments for '/video/'. Entry points hand playback context over
/// through the route instead of pre-filling a shared controller, which lets
/// [VideoPageController] live and die with the route.
///
/// `bangumiItem` deliberately lives on the two anime variants rather than on
/// this base class: movie playback has no Bangumi metadata at all, and forcing
/// a fake one through the shared field would make "is this really a bangumi?"
/// unanswerable at every use site.
sealed class VideoPlaybackArgs {
  const VideoPlaybackArgs();
}

class OnlineVideoPlaybackArgs extends VideoPlaybackArgs {
  const OnlineVideoPlaybackArgs({
    required this.bangumiItem,
    required this.plugin,
    required this.title,
    required this.src,
    required this.roads,
  });

  final BangumiItem bangumiItem;
  final Plugin plugin;
  final String title;
  final String src;
  final List<Road> roads;
}

class OfflineVideoPlaybackArgs extends VideoPlaybackArgs {
  const OfflineVideoPlaybackArgs({
    required this.bangumiItem,
    required this.pluginName,
    required this.episodeNumber,
    required this.road,
    required this.downloadedEpisodes,
  });

  final BangumiItem bangumiItem;
  final String pluginName;
  final int episodeNumber;
  final int road;
  final List<DownloadEpisode> downloadedEpisodes;
}

/// 影视播放参数（来自苹果CMS 采集源）。
///
/// 与在线番剧的关键区别：**地址通常已经是现成的直链，不需要 WebView**。
/// 番剧要给插件一个网页地址、让规则把真实视频流从页面里挖出来；苹果CMS 的
/// `xxxm3u8` 线路本身就是 m3u8/mp4 直链，拿到即可播。所以影视走一条完全独立
/// 的换集路径（`_changeMovieEpisode`），不碰 WebView。
///
/// 但**并非总是直链** —— 采集站的 `xxx云` 线路给的是网页播放页。那些集也允许
/// 出现在这里，由 `_changeMovieEpisode` 在换集时调 `StreamResolver` 换成直链。
/// 放在播放页做而不是进页面前批量做，是因为一季几十集、批量解析要等好几分钟，
/// 而用户一次只看一集。
class MovieVideoPlaybackArgs extends VideoPlaybackArgs {
  const MovieVideoPlaybackArgs({
    required this.sourceKey,
    required this.vodId,
    required this.movieName,
    required this.sourceName,
    required this.routeName,
    required this.episodes,
    required this.startIndex,
    this.coverUrl = '',
    this.year = '',
    this.startOffsetSeconds = 0,
    this.origin = MovieOrigin.movie,
  });

  /// 来源源 key —— 与 [vodId] 一起作为播放进度的身份
  /// （`MoviePlayProgress.keyOf`）。同一个片在不同源里各存一份进度。
  final String sourceKey;

  /// 源站内的影片 id
  final String vodId;

  /// 片名（画中画标题、播放器面板都用它）
  final String movieName;

  /// 来源源名，仅用于展示
  final String sourceName;

  /// 线路名（源站的 `vod_play_from`）
  final String routeName;

  /// 这条线路里**值得展示的**剧集，保持源站顺序。电影通常只有一集。
  ///
  /// 调用方传 `MovieEpisode.actionable` 的那些：直链的、以及网页播放页
  /// （可以解析成直链的）。两种都能在播放页播出来，所以都能进 [Road]。
  ///
  /// 完全没办法的集（比如相对路径）不要传 —— 它们既播不了也解析不了，
  /// 放进来只会让「自动连播」走到必然失败的集上。
  /// 展示全部集（含播不了的）是详情页选集列表的职责。
  final List<MovieEpisode> episodes;

  /// 从第几集开始播（**0 基下标**）
  final int startIndex;

  final String coverUrl;
  final String year;

  /// 从第几秒开始播（续播用）。0 表示从头开始。
  final int startOffsetSeconds;

  /// 从哪个模块进来的（[MovieOrigin.movie] / [MovieOrigin.anime]）。
  ///
  /// 只影响写进观看记录时的归类 —— 动漫与影视共用这条播放链路，
  /// 没有它「我的 → 观看记录」就没法分成两个列表。
  final String origin;

  @override
  String toString() =>
      'MovieVideoPlaybackArgs($movieName / $routeName / ${episodes.length} 集, 起始 $startIndex)';
}
