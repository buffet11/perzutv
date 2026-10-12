import 'package:perzutv/modules/movie/movie_origin.dart';

/// 影视 / 动漫播放进度。
///
/// **刻意与番剧历史分开存。** 番剧那套 `History` 是绑在 `BangumiItem` 上、
/// 还挂着 WebDAV 同步的；影视没有 Bangumi id，混进去会污染番剧的「看过」列表
/// 和同步数据，还会让「番剧历史」里冒出一堆 id=0 的记录。
///
/// 动漫模块复用同一份记录（同一套采集源链路），靠 [origin] 区分来源模块。
class MoviePlayProgress {
  /// 来源源 key，与 [vodId] 一起定位一部片
  final String sourceKey;

  /// 源站内的影片 id
  final String vodId;

  final String name;
  final String coverUrl;

  /// 线路名（源站的 `vod_play_from`）
  final String routeName;

  /// 在哪看过的：[MovieOrigin.movie] 或 [MovieOrigin.anime]。
  final String origin;

  /// 在这条线路**可播集**列表里的下标（0 基）。
  ///
  /// 之所以是「可播集列表」而不是源站全集列表：播放页拿到的就是可播集
  /// （见 `MovieVideoPlaybackArgs.episodes` 的注释），两边必须同一个坐标系，
  /// 否则续播会串集。
  final int episodeIndex;

  final String episodeTitle;

  final int positionSeconds;
  final int durationSeconds;

  /// 毫秒时间戳
  final int updatedAt;

  const MoviePlayProgress({
    required this.sourceKey,
    required this.vodId,
    required this.name,
    this.coverUrl = '',
    this.routeName = '',
    this.origin = MovieOrigin.movie,
    this.episodeIndex = 0,
    this.episodeTitle = '',
    this.positionSeconds = 0,
    this.durationSeconds = 0,
    required this.updatedAt,
  });

  /// 唯一键：同一个影片在不同源里是两条记录（换源之后进度各算各的）
  String get key => keyOf(sourceKey, vodId);

  static String keyOf(String sourceKey, String vodId) => '$sourceKey:$vodId';

  double get percent {
    if (durationSeconds <= 0) return 0;
    return (positionSeconds / durationSeconds).clamp(0.0, 1.0);
  }

  /// 值不值得提供「继续观看」。
  ///
  /// 太靠前（还没看进去）或太靠后（基本看完了）都不给 —— 否则「继续观看
  /// 00:03」这种按钮比没有还烦人。
  bool get resumable {
    if (positionSeconds < 15) return false;
    if (durationSeconds > 0 && positionSeconds > durationSeconds - 30) {
      return false;
    }
    return true;
  }

  /// `1:23:45` 或 `12:34`
  String get positionLabel => formatClock(positionSeconds);

  String get remainingLabel => durationSeconds > 0
      ? formatClock((durationSeconds - positionSeconds).clamp(0, durationSeconds))
      : '';

  static String formatClock(int seconds) {
    final s = seconds < 0 ? 0 : seconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    final mm = m.toString().padLeft(h > 0 ? 2 : 1, '0');
    final ss = sec.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  MoviePlayProgress copyWith({
    String? name,
    String? coverUrl,
    String? routeName,
    String? origin,
    int? episodeIndex,
    String? episodeTitle,
    int? positionSeconds,
    int? durationSeconds,
    int? updatedAt,
  }) {
    return MoviePlayProgress(
      sourceKey: sourceKey,
      vodId: vodId,
      name: name ?? this.name,
      coverUrl: coverUrl ?? this.coverUrl,
      routeName: routeName ?? this.routeName,
      origin: origin ?? this.origin,
      episodeIndex: episodeIndex ?? this.episodeIndex,
      episodeTitle: episodeTitle ?? this.episodeTitle,
      positionSeconds: positionSeconds ?? this.positionSeconds,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'sourceKey': sourceKey,
        'vodId': vodId,
        'name': name,
        'coverUrl': coverUrl,
        'routeName': routeName,
        'origin': origin,
        'episodeIndex': episodeIndex,
        'episodeTitle': episodeTitle,
        'positionSeconds': positionSeconds,
        'durationSeconds': durationSeconds,
        'updatedAt': updatedAt,
      };

  factory MoviePlayProgress.fromJson(Map<String, dynamic> json) {
    int asInt(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;
    String asStr(Object? v) => v is String ? v : '${v ?? ''}';
    return MoviePlayProgress(
      sourceKey: asStr(json['sourceKey']),
      vodId: asStr(json['vodId']),
      name: asStr(json['name']),
      coverUrl: asStr(json['coverUrl']),
      routeName: asStr(json['routeName']),
      // 老记录没有这个字段 → 按影视处理（它们本来就是从影视 Tab 看的）
      origin: MovieOrigin.resolve(json['origin']),
      episodeIndex: asInt(json['episodeIndex']),
      episodeTitle: asStr(json['episodeTitle']),
      positionSeconds: asInt(json['positionSeconds']),
      durationSeconds: asInt(json['durationSeconds']),
      updatedAt: asInt(json['updatedAt']),
    );
  }

  @override
  String toString() => 'MoviePlayProgress($name / $routeName 第${episodeIndex + 1}集 '
      '$positionLabel, ${(percent * 100).toStringAsFixed(1)}%)';
}
