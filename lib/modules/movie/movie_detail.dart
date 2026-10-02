/// 影视详情与播放线路。

/// 单集。电影只有一集，剧集/综艺有多集。
class MovieEpisode {
  /// 「HD国语」/「第01集」
  final String title;

  /// 播放地址。苹果CMS 里没有地址的占位集是空串，已被过滤掉。
  final String url;

  const MovieEpisode({required this.title, required this.url});

  /// 能不能**直接**被播放器打开。
  ///
  /// 实测：苹果CMS 的线路里混着网页播放页（如电影天堂的 `dytt` 线路给的是
  /// `https://vip.dytt-live.com/share/xxx`），这种交给播放器只会看到一页 HTML。
  /// m3u8 才是可靠信号。
  bool get playable =>
      url.startsWith('http') &&
      (url.contains('.m3u8') || url.contains('.mp4') || url.contains('.flv'));

  /// 不是直链，但**有可能换成直链** —— 交给 `StreamResolver` 处理：
  /// 采集站自己的播放页能靠网页解析拿到 m3u8，平台页要靠用户配置的解析源。
  bool get resolvable => url.startsWith('http') && !playable;

  /// 值不值得给一个可点的按钮（直链，或可尝试解析）
  bool get actionable => playable || resolvable;

  @override
  String toString() => '$title -> $url';
}

/// 一条播放线路（源站叫 `vod_play_from`）。
///
/// 一个影片通常有多条线路，每条线路的集数/清晰度/可播性都不同。
/// 实测采集站的线路命名很统一：`xxxm3u8` 给直链，`xxx云` 给网页播放页。
class MovieRoute {
  /// 源站线路名：`dytt` / `dyttm3u8` / `线路一`
  final String name;

  final List<MovieEpisode> episodes;

  const MovieRoute({required this.name, required this.episodes});

  bool get isEmpty => episodes.isEmpty;

  /// 这条线路上有多少集可以**直接**播
  int get playableCount => episodes.where((e) => e.playable).length;

  /// 有多少集不是直链但可以尝试解析
  int get resolvableCount => episodes.where((e) => e.resolvable).length;

  /// 有多少集值得给可点按钮
  int get actionableCount => episodes.where((e) => e.actionable).length;

  /// 有直链
  bool get playable => playableCount > 0;

  /// 至少有一个集是可以做点什么的（直链或可解析）。
  /// 一条「全是网页播放页」的线路也属于这一类 —— 现在的解析器能救回来。
  bool get actionable => actionableCount > 0;

  /// 直链集占比，用于在同为「可播」的线路间排序
  double get playableRatio =>
      episodes.isEmpty ? 0 : playableCount / episodes.length;

  double get actionableRatio =>
      episodes.isEmpty ? 0 : actionableCount / episodes.length;

  MovieEpisode? get firstPlayable {
    for (final e in episodes) {
      if (e.playable) return e;
    }
    return null;
  }

  /// 第一个「能直接播」或「能尝试解析」的集
  MovieEpisode? get firstActionable {
    for (final e in episodes) {
      if (e.actionable) return e;
    }
    return null;
  }

  @override
  String toString() =>
      'MovieRoute($name, ${episodes.length} 集, $playableCount 直链, '
      '$resolvableCount 需解析)';
}

/// 影视详情。
class MovieDetail {
  final String sourceKey;
  final String vodId;
  final String name;
  final String pic;

  /// 已去 HTML 标签的简介
  final String content;

  final String typeName;
  final String year;
  final String area;
  final String remarks;
  final double score;
  final List<String> actors;
  final List<String> directors;

  /// 实测可得（`vod_douban_id`），留给未来扩展
  final String doubanId;

  /// 全部线路，保持源站顺序
  final List<MovieRoute> routes;

  const MovieDetail({
    required this.sourceKey,
    required this.vodId,
    required this.name,
    this.pic = '',
    this.content = '',
    this.typeName = '',
    this.year = '',
    this.area = '',
    this.remarks = '',
    this.score = 0,
    this.actors = const [],
    this.directors = const [],
    this.doubanId = '',
    this.routes = const [],
  });

  /// 有**直链**的线路，按可播性排序。
  ///
  /// 这块是踩过坑的：电影天堂的「流浪地球2」第一条线路 `dytt` 给的是网页
  /// 播放页，播放器打不开；第二条 `dyttm3u8` 才是直链。按源站顺序取第一条
  /// = 用户点了一律播不了。
  ///
  /// 排序依据依次是：可播集数占比 -> 可播集数 -> 线路长度。
  List<MovieRoute> get playableRoutes {
    final list = routes.where((r) => r.playable).toList();
    list.sort((a, b) {
      final byRatio = b.playableRatio.compareTo(a.playableRatio);
      if (byRatio != 0) return byRatio;
      final byCount = b.playableCount.compareTo(a.playableCount);
      if (byCount != 0) return byCount;
      return b.episodes.length.compareTo(a.episodes.length);
    });
    return list;
  }

  /// 展示给用户的线路 —— 在 [playableRoutes] 的基础上，把「全是网页播放页
  /// 但可以解析」的线路也算进来。
  ///
  /// 为什么值得算：实测**每个采集源都有一条这样的线路**（`dytt` / `gsyun` /
  /// `jinyingyun` …），而它们此前被整个丢掉 —— 用户在详情页根本看不到它们
  /// 存在。现在网页解析器能把大部分换成直链，丢掉它们等于白扔一半的线路。
  ///
  /// 排序仍然是**直链优先**：不用等解析，体验更好。其次才看可解析的量。
  List<MovieRoute> get availableRoutes {
    final list = routes.where((r) => r.actionable).toList();
    list.sort((a, b) {
      // 1. 有直链的排前面
      final aDirect = a.playable ? 1 : 0;
      final bDirect = b.playable ? 1 : 0;
      if (aDirect != bDirect) return bDirect.compareTo(aDirect);

      // 2. 直链占比高的优先
      final byRatio = b.playableRatio.compareTo(a.playableRatio);
      if (byRatio != 0) return byRatio;

      // 3. 直链集数多的优先
      final byCount = b.playableCount.compareTo(a.playableCount);
      if (byCount != 0) return byCount;

      // 4. 能处理的集数多的优先（含可解析）
      final byActionable = b.actionableCount.compareTo(a.actionableCount);
      if (byActionable != 0) return byActionable;

      return b.episodes.length.compareTo(a.episodes.length);
    });
    return list;
  }

  /// 默认线路：第一条可用的；全不可用时返回 null（UI 应给出明确提示）
  MovieRoute? get bestRoute {
    final list = availableRoutes;
    return list.isEmpty ? null : list.first;
  }

  /// 一条能用的线路都没有
  bool get hasNoPlayableRoute => availableRoutes.isEmpty;

  @override
  String toString() =>
      'MovieDetail($name, $year, ${routes.length} 线路, '
      '${playableRoutes.length} 直链可播, ${availableRoutes.length} 可用)';
}
