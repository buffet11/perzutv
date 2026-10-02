import 'dart:async';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:kazutv/modules/roads/road_module.dart';
import 'package:kazutv/pages/video/video_playback_args.dart';
import 'package:kazutv/plugins/plugins.dart';
import 'package:kazutv/pages/history/history_controller.dart';
import 'package:kazutv/pages/player/player_controller.dart';
import 'package:kazutv/modules/bangumi/bangumi_item.dart';
import 'package:kazutv/modules/download/download_module.dart';
import 'package:kazutv/modules/history/history_module.dart';
import 'package:kazutv/modules/movie/movie_history.dart';
import 'package:kazutv/services/movie/movie_history_service.dart';
import 'package:kazutv/services/movie/stream_resolver.dart';
import 'package:kazutv/repositories/download_repository.dart';
import 'package:kazutv/services/download/download_manager.dart';
import 'package:kazutv/services/video_source/services.dart';
import 'package:kazutv/bean/dialog/dialog_helper.dart';
import 'package:mobx/mobx.dart';
import 'package:kazutv/services/logging/logger.dart';
import 'package:kazutv/modules/bangumi/episode_item.dart';
import 'package:kazutv/modules/comments/comment_item.dart';
import 'package:kazutv/modules/comments/comment_response.dart';
import 'package:kazutv/request/apis/bangumi_api.dart';
import 'package:kazutv/services/storage/storage.dart';
import 'package:kazutv/utils/episode_url.dart';
import 'package:kazutv/utils/http_headers.dart';
import 'package:kazutv/utils/media.dart';
import 'package:kazutv/utils/async_session.dart';
import 'package:kazutv/services/platform/display_mode_service.dart';
import 'package:kazutv/pages/video/video_fullscreen_controller.dart';

part 'video_controller.g.dart';

class VideoPageController = _VideoPageController with _$VideoPageController;

class VideoEpisodeSelection {
  const VideoEpisodeSelection({
    required this.episode,
    required this.road,
  });

  final int episode;
  final int road;

  @override
  bool operator ==(Object other) {
    return other is VideoEpisodeSelection &&
        other.episode == episode &&
        other.road == road;
  }

  @override
  int get hashCode => Object.hash(episode, road);

  @override
  String toString() {
    return 'VideoEpisodeSelection(episode: $episode, road: $road)';
  }
}

abstract class _VideoPageController with Store implements Disposable {
  _VideoPageController(
    this.historyController,
    this.downloadRepository,
    this.downloadManager,
  );

  late BangumiItem bangumiItem;
  EpisodeInfo episodeInfo = EpisodeInfo.fromTemplate();

  @observable
  var episodeCommentsList = ObservableList<EpisodeCommentItem>();

  // Resolution state machine: [_beginEpisodeSwitch] enters the loading state;
  // [_finishLoading] and [_failLoading] are the only terminal transitions.
  // [_errorMessage] is non-null only in the failed state.
  @readonly
  bool _loading = true;

  @readonly
  String? _errorMessage;

  @observable
  VideoEpisodeSelection selectedEpisode =
      const VideoEpisodeSelection(episode: 1, road: 0);

  @observable
  VideoEpisodeSelection? playingEpisode;

  @observable
  int commentsEpisode = 1;

  @action
  void resetEpisodeState({int episode = 1, int road = 0}) {
    final selection = VideoEpisodeSelection(episode: episode, road: road);
    selectedEpisode = selection;
    playingEpisode = null;
    commentsEpisode = commentEpisodeForSelection(selection);
  }

  VideoEpisodeSelection get playbackEpisode =>
      playingEpisode ?? selectedEpisode;

  final fullscreen = VideoFullscreenController(
    applyFullscreen: DisplayModeService.applyVideoFullscreen,
  );

  bool get isFullscreen => fullscreen.isFullscreen;

  @observable
  bool isCommentsAscending = false;

  // Playback, automatic danmaku loading, and comment loading have separate
  // owners. Manual danmaku selection can cancel auto danmaku without touching
  // playback; comment refreshes never cancel playback.
  final AsyncSessionOwner _playbackSessions = AsyncSessionOwner();
  final AsyncSessionOwner _danmakuSessions = AsyncSessionOwner();
  final AsyncSessionOwner _commentSessions = AsyncSessionOwner();

  @observable
  bool isPip = false;

  @observable
  int historyOffset = 0;

  @observable
  bool isOfflineMode = false;

  /// 影视播放参数。非空即表示当前这次播放来自影视源。
  ///
  /// 为什么不能只靠 [isOfflineMode] 二选一：影视既不是「番剧在线」（不需要
  /// WebView 从网页里挖视频流），也不是「番剧离线」（不是本地文件），它有
  /// 自己的换集路径 —— 苹果CMS 给的本来就是直链。
  MovieVideoPlaybackArgs? _movieArgs;

  bool get isMovieMode => _movieArgs != null;

  /// 仅在 [isMovieMode] 为真时可读。
  MovieVideoPlaybackArgs get movieArgs => _movieArgs!;

  /// 影视进度的落盘节流：位置回调约每秒一次，10 秒写一次足够。
  static const _movieSaveIntervalMs = 10000;

  /// 小于这个秒数不记 —— 起播瞬间位置还是 0，写下去会把已有进度覆盖成 0。
  static const _movieMinRecordSeconds = 5;

  int _movieLastSavedAtMs = 0;
  Duration? _movieLastPosition;

  PlaybackHistoryIdentity? _playbackHistoryIdentity;
  final Map<int, DownloadEpisode> _offlineEpisodesByNumber = {};
  final Map<int, int> _offlineDisplayRoadToOriginalRoad = {};
  final Map<int, int> _offlineOriginalRoadToDisplayRoad = {};

  /// Title reported by the video source; may differ from [bangumiItem]'s.
  String title = '';

  String src = '';

  @observable
  var roadList = ObservableList<Road>();

  late Plugin currentPlugin;

  String _offlinePluginName = '';

  final HistoryController historyController;
  final IDownloadRepository downloadRepository;
  final IDownloadManager downloadManager;

  WebViewVideoSourceService? _videoSourceService;

  final StreamController<String> _logStreamController =
      StreamController<String>.broadcast();

  Stream<String> get logStream => _logStreamController.stream;

  StreamSubscription<String>? _logSubscription;

  /// Applies the route arguments exactly once, from [VideoPage.initState].
  @action
  void applyPlaybackArgs(VideoPlaybackArgs args) {
    switch (args) {
      case OnlineVideoPlaybackArgs():
        bangumiItem = args.bangumiItem;
        currentPlugin = args.plugin;
        title = args.title;
        src = args.src;
        roadList.clear();
        roadList.addAll(args.roads);
      case OfflineVideoPlaybackArgs():
        _initForOfflinePlayback(
          bangumiItem: args.bangumiItem,
          pluginName: args.pluginName,
          episodeNumber: args.episodeNumber,
          road: args.road,
          downloadedEpisodes: args.downloadedEpisodes,
        );
      case MovieVideoPlaybackArgs():
        _initForMoviePlayback(args);
    }
  }

  @action
  void _initForOfflinePlayback({
    required BangumiItem bangumiItem,
    required String pluginName,
    required int episodeNumber,
    required int road,
    required List<DownloadEpisode> downloadedEpisodes,
  }) {
    this.bangumiItem = bangumiItem;
    _offlinePluginName = pluginName;
    title =
        bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name;
    isOfflineMode = true;
    _loading = false;

    _buildOfflineRoadList(downloadedEpisodes);

    final target = _findOfflineEpisodeByNumber(
      episodeNumber,
      preferredOriginalRoad: road,
    );
    final selected = VideoEpisodeSelection(
      episode: target?.listIndex ?? 1,
      road: target?.roadIndex ?? 0,
    );
    selectedEpisode = selected;
    playingEpisode = null;
    commentsEpisode = commentEpisodeForSelection(selected);
    final resolvedEpisode = _resolveOfflineEpisode(
      selected.episode,
      road: selected.road,
    );
    if (resolvedEpisode != null) {
      _setOfflineHistoryIdentity(resolvedEpisode);
    } else {
      _playbackHistoryIdentity = null;
    }
    KazumiLogger().i(
        'VideoPageController: initialized for offline playback, episode $episodeNumber (position: ${selected.episode})');
  }

  /// 影视播放的初始化。
  ///
  /// 与番剧在线的区别：**不做 WebView 解析**（苹果CMS 给的 vod_play_url 本身
  /// 就是 m3u8/mp4 直链）；不查历史、也不设 [_playbackHistoryIdentity] ——
  /// 那个字段为 null 正好是「不写历史」的闸门（见 `player_item.dart` 里
  /// `updateHistory` 的前置条件）。
  void _initForMoviePlayback(MovieVideoPlaybackArgs args) {
    _movieArgs = args;

    // 播放器的画中画与信息面板会读 `videoPageController.bangumiItem`
    // （封面 / 标题），而那个字段是 `late` —— 不赋值就是 LateInitializationError。
    // 所以给影视造一个纯展示用的占位条目，正好显示片名和海报。
    bangumiItem = _moviePlaceholderItem(args);

    // currentPlugin 同样是 `late`，而播放器 UI 也在读它：
    //   player_item.dart      -> OS 媒体面板的专辑名（currentPlugin.name）
    //   player_item_panel.dart -> 投屏时传给接收端的 referer
    // 用官方模板构造一个空壳，name 填来源源名（媒体面板上就显示「电影天堂」
    // 这样的来处）。影视不跑任何插件规则，这个对象只承担展示。
    currentPlugin = Plugin.fromTemplate()..name = args.sourceName;

    title = args.movieName;
    src = args.routeName;
    isOfflineMode = false;
    _loading = false;

    // 续播起点。影视没有 Bangumi 历史可查，这个值由详情页从
    // MovieHistoryService 取出后经参数带进来 —— 播放页不自己去猜。
    historyOffset = args.startOffsetSeconds;

    // 复用 Road：data 放播放地址、identifier 放集名。这样
    // _resolveOnlineEpisode / 剧集切换 / 自动连播 全部现成可用。
    roadList.clear();
    roadList.add(
      Road(
        name: args.routeName,
        data: [for (final episode in args.episodes) episode.url],
        identifier: [for (final episode in args.episodes) episode.title],
      ),
    );

    final start = args.episodes.isEmpty
        ? 0
        : args.startIndex.clamp(0, args.episodes.length - 1);
    resetEpisodeState(episode: start + 1, road: 0);

    KazumiLogger().i(
        'VideoPageController: initialized for movie playback, ${args.movieName} '
        '(${args.routeName}), episode ${start + 1}/${args.episodes.length}');
  }

  /// 影视用的展示型占位 BangumiItem。
  ///
  /// `id: 0` 表示「不属于任何一部番剧」—— 弹幕与短评都按 id 查，0 查不到任何
  /// 东西，正好是我们要的（影视的弹幕在后续阶段接匹配器，不走 id）。
  static BangumiItem _moviePlaceholderItem(MovieVideoPlaybackArgs args) {
    return BangumiItem(
      id: 0,
      type: 0,
      name: args.movieName,
      nameCn: args.movieName,
      summary: '',
      airDate: args.year,
      airWeekday: 0,
      rank: 0,
      images: args.coverUrl.isEmpty ? const {} : {'large': args.coverUrl},
      tags: const [],
      alias: const [],
      ratingScore: 0,
      votes: 0,
      votesCount: const [],
      info: '',
    );
  }

  void _buildOfflineRoadList(List<DownloadEpisode> episodes) {
    final snapshot = buildOfflineRoadListSnapshot(episodes);
    roadList.clear();
    roadList.addAll(snapshot.roads);
    _offlineEpisodesByNumber.clear();
    _offlineEpisodesByNumber.addAll(snapshot.episodesByNumber);
    _offlineDisplayRoadToOriginalRoad.clear();
    _offlineDisplayRoadToOriginalRoad
        .addAll(snapshot.displayRoadToOriginalRoad);
    _offlineOriginalRoadToDisplayRoad.clear();
    _offlineOriginalRoadToDisplayRoad
        .addAll(snapshot.originalRoadToDisplayRoad);
  }

  String get offlinePluginName => _offlinePluginName;

  PlaybackHistoryIdentity? get currentHistoryIdentity =>
      _playbackHistoryIdentity;

  ({int listIndex, int roadIndex})? _findOfflineEpisodeByNumber(
    int episodeNumber, {
    required int preferredOriginalRoad,
  }) {
    if (episodeNumber <= 0 || roadList.isEmpty) {
      return null;
    }
    final preferredDisplayRoad =
        _offlineOriginalRoadToDisplayRoad[preferredOriginalRoad];
    final roadIndices = <int>[
      if (preferredDisplayRoad != null) preferredDisplayRoad,
      for (var i = 0; i < roadList.length; i++)
        if (i != preferredDisplayRoad) i,
    ];
    for (final roadIndex in roadIndices) {
      final match = _findOfflineEpisodeInDisplayRoad(episodeNumber, roadIndex);
      if (match != null) {
        return match;
      }
    }
    return null;
  }

  ({int listIndex, int roadIndex})? _findOfflineEpisodeInDisplayRoad(
    int episodeNumber,
    int roadIndex,
  ) {
    if (roadIndex < 0 || roadIndex >= roadList.length) {
      return null;
    }
    final index = roadList[roadIndex].data.indexOf(episodeNumber.toString());
    if (index < 0) {
      return null;
    }
    return (listIndex: index + 1, roadIndex: roadIndex);
  }

  int getHistoryOffsetFor(PlaybackHistoryIdentity identity) {
    final playResume = GStorage.getSetting(SettingsKeys.playResume);
    if (playResume != true) {
      return 0;
    }
    return historyController
            .findProgress(
              identity.bangumiItem,
              identity.pluginName,
              identity.episodeNumber,
              entryKind: identity.entryKind,
            )
            ?.progress
            .inSeconds ??
        0;
  }

  void _setOnlineHistoryIdentity(EpisodeRef episode) {
    _playbackHistoryIdentity = PlaybackHistoryIdentity.online(
      bangumiItem: bangumiItem,
      pluginName: currentPlugin.name,
      episodeNumber: episode.historyEpisodeNumber,
      episodeTitle: episode.displayTitle,
      road: episode.originalRoadIndex,
      onlineBangumiSrc: src,
      episodePageUrl: episode.pageUrl,
    );
  }

  void _setOfflineHistoryIdentity(EpisodeRef episode) {
    _playbackHistoryIdentity = PlaybackHistoryIdentity.offline(
      bangumiItem: bangumiItem,
      pluginName: _offlinePluginName,
      episodeNumber: episode.historyEpisodeNumber,
      episodeTitle: episode.displayTitle,
      road: episode.originalRoadIndex,
      episodePageUrl: episode.pageUrl,
    );
  }

  EpisodeRef? _resolveOnlineEpisode(int episode, {int? road}) {
    final targetRoad = road ?? selectedEpisode.road;
    if (roadList.isEmpty || targetRoad < 0 || targetRoad >= roadList.length) {
      return null;
    }
    final roadData = roadList[targetRoad];
    final index = episode - 1;
    if (index < 0 ||
        index >= roadData.data.length ||
        index >= roadData.identifier.length) {
      return null;
    }
    final displayTitle = roadData.identifier[index];
    return EpisodeRef.online(
      listIndex: episode,
      roadIndex: targetRoad,
      displayTitle: displayTitle,
      pageUrl: roadData.data[index],
    );
  }

  EpisodeRef? _resolveOfflineEpisode(int episode, {int? road}) {
    final targetRoad = road ?? selectedEpisode.road;
    if (roadList.isEmpty || targetRoad < 0 || targetRoad >= roadList.length) {
      return null;
    }
    final roadData = roadList[targetRoad];
    final index = episode - 1;
    if (index < 0 ||
        index >= roadData.data.length ||
        index >= roadData.identifier.length) {
      return null;
    }
    final episodeNumber = int.tryParse(roadData.data[index]);
    if (episodeNumber == null) {
      return null;
    }
    final downloadEpisode = _offlineEpisodesByNumber[episodeNumber];
    final titleFromRoad = roadData.identifier[index];
    final episodeTitle = downloadEpisode?.episodeName.isNotEmpty == true
        ? downloadEpisode!.episodeName
        : (titleFromRoad.isNotEmpty ? titleFromRoad : '第$episodeNumber集');
    return EpisodeRef.offline(
      listIndex: episode,
      roadIndex: targetRoad,
      displayTitle: episodeTitle,
      pageUrl: downloadEpisode?.episodePageUrl ?? '',
      episodeNumber: episodeNumber,
      originalRoadIndex: downloadEpisode?.road ??
          _offlineDisplayRoadToOriginalRoad[targetRoad] ??
          targetRoad,
    );
  }

  EpisodeRef? resolveEpisode(VideoEpisodeSelection selection) {
    return isOfflineMode
        ? _resolveOfflineEpisode(selection.episode, road: selection.road)
        : _resolveOnlineEpisode(selection.episode, road: selection.road);
  }

  int commentEpisodeForSelection(VideoEpisodeSelection selection) {
    final resolvedEpisode = resolveEpisode(selection);
    return resolvedEpisode?.danmakuEpisodeNumber ?? selection.episode;
  }

  /// Resets pre-switch state as a single transaction so observers see one
  /// notification instead of one per field.
  @action
  void _beginEpisodeSwitch(VideoEpisodeSelection selection) {
    final targetCommentsEpisode = commentEpisodeForSelection(selection);
    selectedEpisode = selection;
    playingEpisode = null;
    // The comments sheet only re-queries when [commentsEpisode] changes, so
    // resetting comment state here without changing it would blank the sheet
    // permanently.
    if (targetCommentsEpisode != commentsEpisode) {
      commentsEpisode = targetCommentsEpisode;
      _resetEpisodeComments();
    }
    _loading = true;
    _errorMessage = null;
  }

  @action
  void _applyResolvedSelection(EpisodeRef resolvedEpisode) {
    selectedEpisode = VideoEpisodeSelection(
      episode: resolvedEpisode.listIndex,
      road: resolvedEpisode.roadIndex,
    );
    commentsEpisode = commentEpisodeForSelection(selectedEpisode);
  }

  @action
  void _finishLoading() {
    _loading = false;
  }

  @action
  void _failLoading(String message) {
    _loading = false;
    _errorMessage = message;
  }

  Future<void> changeEpisode(
    int episode, {
    int currentRoad = 0,
    int offset = 0,
    required PlayerController playerController,
  }) async {
    final session = _playbackSessions.begin();
    final selection = VideoEpisodeSelection(
      episode: episode,
      road: currentRoad,
    );
    _beginEpisodeSwitch(selection);
    _danmakuSessions.cancel();
    playerController.danmaku.finishDanmakuLoad();
    _videoSourceService?.cancel();

    await playerController.stop();
    if (session.isStale) {
      return;
    }

    if (isOfflineMode) {
      await _changeOfflineEpisode(
        selection,
        offset,
        session: session,
        playerController: playerController,
      );
      return;
    }

    if (isMovieMode) {
      await _changeMovieEpisode(
        selection,
        offset,
        session: session,
        playerController: playerController,
      );
      return;
    }

    final resolvedEpisode = _resolveOnlineEpisode(episode, road: currentRoad);
    if (resolvedEpisode == null) {
      KazumiLogger().e(
          'VideoPageController: failed to resolve online episode. road=$currentRoad, episode=$episode');
      _failLoading('集数解析失败');
      return;
    }

    _applyResolvedSelection(resolvedEpisode);
    _setOnlineHistoryIdentity(resolvedEpisode);

    KazumiLogger()
        .i('VideoPageController: changed to ${resolvedEpisode.displayTitle}');
    final urlItem = normalizeEpisodeUrl(
      currentPlugin.baseUrl,
      resolvedEpisode.pageUrl,
    );

    await _resolveWithVideoSourceService(
      urlItem,
      offset,
      resolvedEpisode: resolvedEpisode,
      session: session,
      playerController: playerController,
    );
  }

  Future<void> _changeOfflineEpisode(
    VideoEpisodeSelection selection,
    int offset, {
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    final resolvedEpisode =
        _resolveOfflineEpisode(selection.episode, road: selection.road);
    if (resolvedEpisode == null) {
      KazumiLogger().e(
          'VideoPageController: failed to resolve offline episode. road=${selection.road}, episode=${selection.episode}');
      _failLoading('集数解析失败');
      return;
    }

    final localPath = _getLocalVideoPath(
      bangumiItem.id,
      _offlinePluginName,
      resolvedEpisode.historyEpisodeNumber,
    );
    if (localPath == null) {
      _failLoading('该集数未下载');
      return;
    }
    _applyResolvedSelection(resolvedEpisode);
    _setOfflineHistoryIdentity(resolvedEpisode);
    if (session.isStale) {
      return;
    }
    _finishLoading();
    final resolvedOffset =
        offset > 0 ? offset : getHistoryOffsetFor(_playbackHistoryIdentity!);

    KazumiLogger().i(
        'VideoPageController: offline episode changed to ${resolvedEpisode.historyEpisodeNumber} (index: ${selection.episode}), path: $localPath');

    final params = PlaybackInitParams(
      videoUrl: localPath,
      offset: resolvedOffset,
      isLocalPlayback: true,
      bangumiId: bangumiItem.id,
      pluginName: _offlinePluginName,
      episode: resolvedEpisode.listIndex,
      danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
      pageUrl: resolvedEpisode.pageUrl,
      sortNumber: resolvedEpisode.sortNumber,
      httpHeaders: {},
      adBlockerEnabled: false,
      episodeTitle: resolvedEpisode.displayTitle,
      referer: '',
      currentRoad: resolvedEpisode.roadIndex,
      coverUrl: bangumiItem.images['large'],
      bangumiName:
          bangumiItem.nameCn.isNotEmpty ? bangumiItem.nameCn : bangumiItem.name,
    );

    final initialized = await playerController.init(params);
    if (session.isActive && initialized) {
      playingEpisode = selection;
      unawaited(_loadPlaybackDanmaku(playerController, params, session));
    } else if (session.isActive) {
      _playbackSessions.cancel();
    }
  }

  Future<void> _loadPlaybackDanmaku(
    PlayerController playerController,
    PlaybackInitParams params,
    AsyncSession session,
  ) async {
    final danmakuSession = _danmakuSessions.begin();
    playerController.danmaku.beginDanmakuLoad();
    try {
      final result = await playerController.danmaku.fetchDanmaku(
        params.bangumiId,
        params.pluginName,
        params.danmakuEpisodeNumber,
      );
      if (session.isActive && danmakuSession.isActive) {
        if (result.hasDanmakus) {
          final bool enableDanmaku =
              GStorage.getSetting(SettingsKeys.danmakuEnabledByDefault);
          playerController.danmaku.applyDanmakuLoad(
            result,
            enableDanmaku: enableDanmaku,
          );
        } else {
          playerController.danmaku.applyUnavailableDanmakuLoad(result);
          if (result.isFailed) {
            KazumiDialog.showToast(message: '弹幕加载失败，可手动检索');
          }
        }
      }
    } catch (e) {
      if (session.isActive && danmakuSession.isActive) {
        playerController.danmaku.finishDanmakuLoad(disableDanmaku: true);
        KazumiDialog.showToast(message: '弹幕加载失败，可手动检索');
      }
      KazumiLogger().w('VideoPageController: failed to load danmaku', error: e);
    }
  }

  void cancelAutomaticDanmakuLoad() {
    _danmakuSessions.cancel();
  }

  String? _getLocalVideoPath(
      int bangumiId, String pluginName, int episodeNumber) {
    final episode =
        downloadRepository.getEpisode(bangumiId, pluginName, episodeNumber);
    return downloadManager.getLocalVideoPath(episode);
  }

  Future<void> _changeMovieEpisode(
    VideoEpisodeSelection selection,
    int offset, {
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    final args = _movieArgs!;
    final resolvedEpisode =
        _resolveOnlineEpisode(selection.episode, road: selection.road);
    if (resolvedEpisode == null) {
      KazumiLogger().e(
          'VideoPageController: failed to resolve movie episode. road=${selection.road}, episode=${selection.episode}');
      _failLoading('集数解析失败');
      return;
    }

    // 源站给的可能是「网页播放页」而不是直链（采集站的 `xxx云` 线路就是）。
    // 那种地址交给播放器只会显示一页 HTML，所以在这里换成真直链。
    //
    // 放在**这一步**（换集时）而不是进播放页之前批量解析：一季几十集，
    // 批量解析要发几十个请求、等上好几分钟；而用户一集一集看，
    // 每次只需要解析当前这一集。自动连播也走这里，所以是无感的。
    //
    // 解析期间 `_loading` 还是 true（由 changeEpisode 的 _beginEpisodeSwitch
    // 设的），界面正好显示加载中；解析不出来就 _failLoading，界面会给出
    // 错误提示和重试按钮，而不是让播放器对着一个网页地址报错。
    var playUrl = resolvedEpisode.pageUrl;
    var httpHeaders = <String, String>{};

    if (!StreamResolver.isDirectUrl(playUrl)) {
      final resolved = await StreamResolver.resolve(playUrl);
      if (session.isStale) {
        return;
      }
      if (resolved == null) {
        KazumiLogger().e(
            'VideoPageController: 无法解析影视地址 $playUrl');
        _failLoading(
          '这一集的地址解析不出来。源站给的是一个网页地址，'
          '没能从里面找到播放链接 —— 换一条线路，或换一个源试试。',
        );
        return;
      }
      KazumiLogger().i(
          'VideoPageController: 影视地址已解析（${resolved.via}）-> ${resolved.url}');
      playUrl = resolved.url;
      httpHeaders = resolved.headers;
    }

    // 影视不写历史：不设 _playbackHistoryIdentity，播放器侧就不会落盘。
    _applyResolvedSelection(resolvedEpisode);
    if (session.isStale) {
      return;
    }
    _finishLoading();

    KazumiLogger().i(
        'VideoPageController: movie episode changed to ${resolvedEpisode.displayTitle}');

    final params = PlaybackInitParams(
      videoUrl: playUrl,
      offset: offset,
      isLocalPlayback: false,
      bangumiId: bangumiItem.id,
      // 空 pluginName = 没有可用的插件规则。弹幕与短评都依赖它，
      // 影视的弹幕留到后续阶段用独立的匹配器接，这里先不给假的。
      pluginName: '',
      episode: resolvedEpisode.listIndex,
      danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
      pageUrl: playUrl,
      sortNumber: resolvedEpisode.sortNumber,
      // 解析出来的地址常按 Referer 做防盗链，必须把它带上
      httpHeaders: httpHeaders,
      adBlockerEnabled: false,
      episodeTitle: resolvedEpisode.displayTitle,
      referer: resolvedEpisode.pageUrl,
      currentRoad: resolvedEpisode.roadIndex,
      coverUrl: args.coverUrl.isEmpty ? null : args.coverUrl,
      bangumiName: args.movieName,
    );

    final initialized = await playerController.init(params);
    if (session.isActive && initialized) {
      playingEpisode = selection;
      // 这里刻意不调 _loadPlaybackDanmaku：影视没有 Bangumi id，
      // 弹幕自动匹配是后续阶段的事。
    } else if (session.isActive) {
      _playbackSessions.cancel();
    }
  }

  /// 影视播放进度写入。
  ///
  /// 播放器的位置回调大约每秒一次，每次都落盘太频繁 —— 这里自己节流。
  /// 换集与退出时用 [flushMovieProgress] 强制补一次，所以最多丢十来秒。
  ///
  /// 位置太小的不写：起播瞬间位置还是 0，写下去会把之前的进度覆盖成 0。
  Future<void> saveMovieProgress(
    Duration position, {
    Duration duration = Duration.zero,
    bool force = false,
  }) async {
    final args = _movieArgs;
    if (args == null) return;

    _movieLastPosition = position;
    if (position.inSeconds < _movieMinRecordSeconds) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (!force && now - _movieLastSavedAtMs < _movieSaveIntervalMs) return;
    _movieLastSavedAtMs = now;

    final selection = playbackEpisode;
    final road = selection.road >= 0 && selection.road < roadList.length
        ? roadList[selection.road]
        : null;
    final index = selection.episode - 1;
    final title = road != null && index >= 0 && index < road.identifier.length
        ? road.identifier[index]
        : '';

    await MovieHistoryService.save(
      MoviePlayProgress(
        sourceKey: args.sourceKey,
        vodId: args.vodId,
        name: args.movieName,
        coverUrl: args.coverUrl,
        routeName: args.routeName,
        episodeIndex: index < 0 ? 0 : index,
        episodeTitle: title,
        positionSeconds: position.inSeconds,
        durationSeconds: duration.inSeconds,
        updatedAt: now,
      ),
    );
  }

  /// 退出/换集时把最后一次位置补写下去。
  Future<void> flushMovieProgress({Duration duration = Duration.zero}) {
    final last = _movieLastPosition;
    if (last == null) return Future.value();
    return saveMovieProgress(last, duration: duration, force: true);
  }

  /// 切换线路/集数后旧线路的位置就没意义了。
  ///
  /// 不需要额外处理：换集后播放器位置回到 0，而
  /// [saveMovieProgress] 对小于 [_movieMinRecordSeconds] 的位置直接不记，
  /// 所以不会拿一个 0 去覆盖上一个进度。

  Future<void> _resolveWithVideoSourceService(
    String url,
    int offset, {
    required EpisodeRef resolvedEpisode,
    required AsyncSession session,
    required PlayerController playerController,
  }) async {
    _videoSourceService ??= WebViewVideoSourceService();

    await _logSubscription?.cancel();
    _logSubscription = _videoSourceService!.onLog.listen((log) {
      if (!_logStreamController.isClosed) {
        _logStreamController.add(log);
      }
    });

    try {
      final source = await _videoSourceService!.resolve(
        url,
        useLegacyParser: currentPlugin.useLegacyParser,
        offset: offset,
      );

      if (session.isStale) {
        return;
      }
      _finishLoading();
      KazumiLogger()
          .i('VideoPageController: resolved video URL: ${source.url}');

      final bool forceAdBlocker =
          GStorage.getSetting(SettingsKeys.forceAdBlocker);

      final params = PlaybackInitParams(
        videoUrl: source.url,
        offset: source.offset,
        isLocalPlayback: false,
        videoSourceFormat: source.format,
        bangumiId: bangumiItem.id,
        pluginName: currentPlugin.name,
        episode: resolvedEpisode.listIndex,
        danmakuEpisodeNumber: resolvedEpisode.danmakuEpisodeNumber,
        pageUrl: resolvedEpisode.pageUrl,
        sortNumber: resolvedEpisode.sortNumber,
        httpHeaders: {
          'user-agent': currentPlugin.userAgent.isEmpty
              ? getRandomUA()
              : currentPlugin.userAgent,
          if (currentPlugin.referer.isNotEmpty)
            'referer': currentPlugin.referer,
        },
        adBlockerEnabled: forceAdBlocker || currentPlugin.adBlocker,
        episodeTitle: resolvedEpisode.displayTitle,
        referer: currentPlugin.referer,
        currentRoad: resolvedEpisode.roadIndex,
        coverUrl: bangumiItem.images['large'],
        bangumiName: bangumiItem.nameCn.isNotEmpty
            ? bangumiItem.nameCn
            : bangumiItem.name,
      );

      final initialized = await playerController.init(params);
      if (session.isActive && initialized) {
        playingEpisode = VideoEpisodeSelection(
          episode: resolvedEpisode.listIndex,
          road: resolvedEpisode.roadIndex,
        );
        unawaited(_loadPlaybackDanmaku(playerController, params, session));
      } else if (session.isActive) {
        _playbackSessions.cancel();
      }
    } on VideoSourceTimeoutException {
      if (session.isStale) {
        return;
      }
      _failLoading('视频解析超时，请重试');
    } on VideoSourceCancelledException {
      KazumiLogger().i('VideoPageController: video URL resolution cancelled');
    } catch (e) {
      if (session.isStale) {
        return;
      }
      _failLoading('视频解析失败：${e.toString()}');
    }
  }

  void _resetEpisodeComments() {
    _commentSessions.cancel();
    episodeInfo.reset();
    episodeCommentsList.clear();
  }

  Future<bool> queryBangumiEpisodeCommentsByID(int id, int episode) async {
    final session = _commentSessions.begin();
    final EpisodeInfo latestEpisodeInfo;
    try {
      latestEpisodeInfo = await BangumiApi.getBangumiEpisodeByID(id, episode);
    } catch (_) {
      if (session.isStale) {
        return false;
      }
      rethrow;
    }
    if (session.isStale) {
      return false;
    }
    final EpisodeCommentResponse value;
    try {
      value =
          await BangumiApi.getBangumiCommentsByEpisodeID(latestEpisodeInfo.id);
    } catch (_) {
      if (session.isStale) {
        return false;
      }
      rethrow;
    }
    if (session.isStale) {
      return false;
    }
    final commentsList = value.commentList;
    if (!isCommentsAscending) {
      commentsList
          .sort((a, b) => b.comment.createdAt.compareTo(a.comment.createdAt));
    } else {
      commentsList
          .sort((a, b) => a.comment.createdAt.compareTo(b.comment.createdAt));
    }
    _applyEpisodeComments(episode, latestEpisodeInfo, commentsList);
    KazumiLogger().i(
        'VideoPageController: loaded comments list length ${episodeCommentsList.length}');
    return true;
  }

  @action
  void _applyEpisodeComments(
    int episode,
    EpisodeInfo info,
    List<EpisodeCommentItem> comments,
  ) {
    commentsEpisode = episode;
    episodeInfo = info;
    episodeCommentsList = ObservableList.of(comments);
  }

  @action
  void toggleSortOrder() {
    isCommentsAscending = !isCommentsAscending;
    episodeCommentsList.sort(
      (a, b) => isCommentsAscending
          ? a.comment.createdAt.compareTo(b.comment.createdAt)
          : b.comment.createdAt.compareTo(a.comment.createdAt),
    );
  }

  /// Called by Modular when the '/video' route scope is disposed.
  @override
  void dispose() {
    unawaited(fullscreen.close());
    _playbackSessions.cancel();
    _danmakuSessions.cancel();
    _commentSessions.cancel();
    _logSubscription?.cancel();
    _logSubscription = null;
    if (!_logStreamController.isClosed) {
      _logStreamController.close();
    }
    final videoSourceService = _videoSourceService;
    _videoSourceService = null;
    if (videoSourceService != null) {
      unawaited(videoSourceService.dispose());
    }
  }
}

class OfflineRoadListSnapshot {
  const OfflineRoadListSnapshot({
    required this.roads,
    required this.episodesByNumber,
    required this.displayRoadToOriginalRoad,
    required this.originalRoadToDisplayRoad,
  });

  final List<Road> roads;
  final Map<int, DownloadEpisode> episodesByNumber;
  final Map<int, int> displayRoadToOriginalRoad;
  final Map<int, int> originalRoadToDisplayRoad;
}

OfflineRoadListSnapshot buildOfflineRoadListSnapshot(
  List<DownloadEpisode> episodes,
) {
  final groupedEpisodes = <int, List<DownloadEpisode>>{};
  final episodesByNumber = <int, DownloadEpisode>{};

  for (final episode in episodes) {
    episodesByNumber[episode.episodeNumber] = episode;
    groupedEpisodes.putIfAbsent(episode.road, () => []).add(episode);
  }

  final originalRoads = groupedEpisodes.keys.toList()..sort();
  final roads = <Road>[];
  final displayRoadToOriginalRoad = <int, int>{};
  final originalRoadToDisplayRoad = <int, int>{};

  for (final originalRoad in originalRoads) {
    final roadEpisodes = groupedEpisodes[originalRoad]!
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    final displayRoad = roads.length;
    displayRoadToOriginalRoad[displayRoad] = originalRoad;
    originalRoadToDisplayRoad[originalRoad] = displayRoad;
    roads.add(Road(
      name: originalRoad >= 0
          ? '播放列表${originalRoad + 1}'
          : '播放列表${displayRoad + 1}',
      data: roadEpisodes.map((e) => e.episodeNumber.toString()).toList(),
      identifier: roadEpisodes
          .map((e) =>
              e.episodeName.isNotEmpty ? e.episodeName : '第${e.episodeNumber}集')
          .toList(),
    ));
  }

  return OfflineRoadListSnapshot(
    roads: roads,
    episodesByNumber: episodesByNumber,
    displayRoadToOriginalRoad: displayRoadToOriginalRoad,
    originalRoadToDisplayRoad: originalRoadToDisplayRoad,
  );
}

class EpisodeRef {
  const EpisodeRef({
    required this.listIndex,
    required this.roadIndex,
    required this.displayTitle,
    required this.pageUrl,
    required this.sortNumber,
    required this.historyEpisodeNumber,
    required this.danmakuEpisodeNumber,
    required this.originalRoadIndex,
  });

  final int listIndex;
  final int roadIndex;
  final String displayTitle;
  final String pageUrl;

  /// Episode sort number.
  /// - Online: parsed from [displayTitle] via [extractEpisodeNumber];
  ///   null when unparsable.
  /// - Offline: always the download record's episodeNumber.
  final int? sortNumber;
  final int historyEpisodeNumber;
  final int danmakuEpisodeNumber;
  final int originalRoadIndex;

  factory EpisodeRef.online({
    required int listIndex,
    required int roadIndex,
    required String displayTitle,
    required String pageUrl,
  }) {
    final parsedEpisodeNumber = extractEpisodeNumber(displayTitle);
    return EpisodeRef(
      listIndex: listIndex,
      roadIndex: roadIndex,
      displayTitle: displayTitle,
      pageUrl: pageUrl,
      sortNumber: parsedEpisodeNumber > 0 ? parsedEpisodeNumber : null,
      historyEpisodeNumber: listIndex,
      danmakuEpisodeNumber:
          parsedEpisodeNumber > 0 ? parsedEpisodeNumber : listIndex,
      originalRoadIndex: roadIndex,
    );
  }

  const factory EpisodeRef.offline({
    required int listIndex,
    required int roadIndex,
    required String displayTitle,
    required String pageUrl,
    required int episodeNumber,
    required int originalRoadIndex,
  }) = _OfflineEpisodeRef;
}

class _OfflineEpisodeRef extends EpisodeRef {
  const _OfflineEpisodeRef({
    required super.listIndex,
    required super.roadIndex,
    required super.displayTitle,
    required super.pageUrl,
    required int episodeNumber,
    required super.originalRoadIndex,
  }) : super(
          sortNumber: episodeNumber,
          historyEpisodeNumber: episodeNumber,
          danmakuEpisodeNumber: episodeNumber,
        );
}
