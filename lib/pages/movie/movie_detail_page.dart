import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:kazutv/bean/appbar/sys_app_bar.dart';
import 'package:kazutv/bean/card/network_img_layer.dart';
import 'package:kazutv/bean/dialog/dialog_helper.dart';
import 'package:kazutv/bean/widget/empty_state_widget.dart';
import 'package:kazutv/bean/widget/loading_indicator.dart';
import 'package:kazutv/modules/movie/movie_detail.dart';
import 'package:kazutv/modules/movie/movie_history.dart';
import 'package:kazutv/modules/movie/movie_item.dart';
import 'package:kazutv/modules/movie/movie_source.dart';
import 'package:kazutv/navigation.dart';
import 'package:kazutv/pages/movie/movie_episode_grid.dart';
import 'package:kazutv/pages/movie/movie_route_selector.dart';
import 'package:kazutv/pages/video/video_playback_args.dart';
import 'package:kazutv/request/apis/apple_cms_api.dart';
import 'package:kazutv/services/movie/movie_history_service.dart';
import 'package:kazutv/services/movie/movie_source_manager.dart';
import 'package:kazutv/services/movie/stream_resolver.dart';

/// 影视详情页。
///
/// 从搜索结果进来（动画参数是 [MovieSearchItem]），自己拉详情 —— 不复用
/// 番剧的 InfoPage：那边整套都建立在 Bangumi 元数据上（评分/话数/角色/评论），
/// 影视这边一个都没有。
class MovieDetailPage extends StatefulWidget {
  const MovieDetailPage({super.key, required this.item});

  final MovieSearchItem item;

  @override
  State<MovieDetailPage> createState() => _MovieDetailPageState();
}

class _MovieDetailPageState extends State<MovieDetailPage> with RouteAware {
  MovieDetail? _detail;
  bool _loading = true;
  String? _error;

  /// 当前选中的线路（在 `_routes` 里的下标）
  int _routeIndex = 0;

  /// 播放进度**每次读实时数据**而不是缓存一份。
  ///
  /// 缓存的话，从播放页返回后 banner 还显示着进去之前的旧时间 —— 看着就像坏了。
  /// 后面用 [didPopNext] 补一次 rebuild 就够了。Hive 的读是内存操作，很便宜。
  MoviePlayProgress? get _progress => MovieHistoryService.find(
        widget.item.sourceKey,
        widget.item.vodId,
      );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<void>) {
      rootRouteObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    rootRouteObserver.unsubscribe(this);
    super.dispose();
  }

  /// 从播放页返回时刷新一下，让「继续观看」显示的是刚看到的位置。
  @override
  void didPopNext() {
    if (mounted) setState(() {});
  }

  MovieSource? get _source {
    for (final s in MovieSourceManager.all()) {
      if (s.key == widget.item.sourceKey) return s;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final source = _source;
    if (source == null) {
      setState(() {
        _loading = false;
        _error = '这个源已被删除或停用，无法获取详情。';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await AppleCmsApi.detail(source, widget.item.vodId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
        _routeIndex = 0;
        _error = detail == null ? '源站里找不到这部片（可能已下架）。' : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '详情加载失败：$e';
      });
    }
  }

  /// 展示的线路。
  ///
  /// 用 `availableRoutes` 而不是 `playableRoutes`：后者只算**直链**线路，
  /// 而实测每个采集源都有一条「网页播放页」线路（`dytt` / `gsyun` …），
  /// 那些现在能靠网页解析换成直链 —— 不列出来等于白扔一半的线路。
  List<MovieRoute> get _routes => _detail?.availableRoutes ?? const [];

  MovieRoute? get _currentRoute {
    final routes = _routes;
    if (routes.isEmpty) return null;
    return routes[_routeIndex.clamp(0, routes.length - 1)];
  }

  /// 上次看到的位置，前提是它还能对得上**现在的**线路结构。
  ///
  /// 源站的线路名会变、某条线路可能下架，所以记录里的 `routeName` /
  /// `episodeIndex` 有可能对不上。对不上就返回 null（不显示「继续观看」），
  /// 而不是硬套一个位置上去 —— 那会让人一打开就跳到莫名其妙的地方。
  ({MovieRoute route, int routeIndex, int episodeIndex})? get _resumeTarget {
    final progress = _progress;
    if (progress == null || !progress.resumable) return null;

    final routes = _routes;
    if (routes.isEmpty) return null;

    var routeIndex = routes.indexWhere((r) => r.name == progress.routeName);
    if (routeIndex < 0) routeIndex = 0; // 线路名对不上就退回第一条可用线路
    final route = routes[routeIndex];

    final list = _playableOf(route);
    final index = progress.episodeIndex;
    if (index < 0 || index >= list.length) return null;

    // 下标还得指向**同一集**。这里必须查一次：线路的可播集组成会变
    // （源站加了新集、或者我们把「可解析」的集也算进来之后列表变长了），
    // 光看下标的范围可能落在别的集上，硬套上去就是「接着看」看错集。
    if (progress.episodeTitle.isNotEmpty &&
        list[index].title != progress.episodeTitle) {
      return null;
    }

    return (route: route, routeIndex: routeIndex, episodeIndex: index);
  }

  /// 这条线路里会进播放页的集（直链 + 可解析）。
  ///
  /// 与 [_play] 用的是同一个口径 —— 两处不一致的话，续播的下标就会错位。
  static List<MovieEpisode> _playableOf(MovieRoute route) =>
      [for (final e in route.episodes) if (e.actionable) e];

  /// 从上次的位置接着看。
  void _resume() {
    final target = _resumeTarget;
    final progress = _progress;
    if (target == null || progress == null) return;

    setState(() => _routeIndex = target.routeIndex);
    final list = _playableOf(target.route);
    _play(list[target.episodeIndex],
        offsetSeconds: progress.positionSeconds);
  }

  /// 播放某一集。
  ///
  /// 把这条线路**能播的剧集**一起带过去：播放页要用它构造 Road（换集、自动
  /// 连播、选集高亮都在那边做），只传一个 URL 的话换集就没有依据了。
  ///
  /// 「能播的」= 直链 + 网页播放页（可解析）。网页播放页那种不在这里解析，
  /// 而是交给播放页在换集时解析（见 `_changeMovieEpisode`）—— 一季几十集，
  /// 进播放页前批量解析要等好几分钟，而用户一次只看一集。
  /// 两处口径必须一致，否则续播下标会错位，所以统一走 [_playableOf]。
  ///
  /// [offsetSeconds] > 0 表示续播（从上次的位置接着看）。
  void _play(MovieEpisode episode, {int offsetSeconds = 0}) {
    final route = _currentRoute;
    final detail = _detail;
    if (route == null || detail == null) return;

    if (!episode.actionable) {
      KazumiDialog.showToast(
        message: '这一集的地址源站没给全（不是完整网址），播不了。换一条线路试试。',
        context: context,
      );
      return;
    }

    // 平台播放页（腾讯/爱奇艺/优酷）没法靠网页解析拿地址，必须有解析源。
    // 提前说清楚，免得用户进了播放页只看到一句「解析不出来」。
    if (!episode.playable &&
        StreamResolver.isPlatformPage(episode.url) &&
        !StreamResolver.canResolve(episode.url)) {
      KazumiDialog.showToast(
        message: '这一集来自视频平台的播放页，需要在「设置 → 资源 → 解析源」里'
            '配置一个解析接口才能播。',
        context: context,
      );
      return;
    }

    final list = _playableOf(route);
    if (list.isEmpty) {
      KazumiDialog.showToast(
        message: '这条线路没有能播的剧集，换一条试试。',
        context: context,
      );
      return;
    }

    final index = list.indexOf(episode);
    context.pushNamed(
      '/video/',
      arguments: MovieVideoPlaybackArgs(
        sourceKey: widget.item.sourceKey,
        vodId: widget.item.vodId,
        movieName: detail.name,
        sourceName: widget.item.sourceName,
        routeName: route.name,
        episodes: list,
        startIndex: index < 0 ? 0 : index,
        coverUrl: detail.pic.isNotEmpty ? detail.pic : widget.item.pic,
        year: detail.year,
        startOffsetSeconds: offsetSeconds,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return Scaffold(
      appBar: SysAppBar(
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context)
              .textTheme
              .titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: LoadingIndicator(size: 48));
    }
    if (_error != null) {
      return GeneralEmptyState(
        icon: Icons.error_outline,
        title: _error!,
        actions: [
          FilledButton.tonal(onPressed: _load, child: const Text('重试')),
        ],
      );
    }

    final detail = _detail!;
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _header(context, detail),
          if (_resumeTarget != null) _resumeBanner(context),
          const SizedBox(height: 12),
          _routesSection(context, detail),
          const Divider(height: 24, indent: 16, endIndent: 16),
          _episodesSection(context),
          const SizedBox(height: 16),
          _introSection(context, detail),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------- 头部

  Widget _header(BuildContext context, MovieDetail detail) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: NetworkImgLayer(
              src: detail.pic.isNotEmpty ? detail.pic : widget.item.pic,
              width: 116,
              height: 174,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (_metaLine.isNotEmpty)
                  Text(
                    _metaLine,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                if (detail.remarks.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _tag(context, detail.remarks,
                      colorScheme.secondaryContainer,
                      colorScheme.onSecondaryContainer),
                ],
                const SizedBox(height: 10),
                if (_directorLine.isNotEmpty)
                  _creditLine(context, '导演', _directorLine),
                if (_actorLine.isNotEmpty) _creditLine(context, '主演', _actorLine),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () {
                    final route = _currentRoute;
                    final episode = route?.firstActionable;
                    if (episode == null) {
                      KazumiDialog.showToast(
                        message: '这条线路没有能播的剧集，换一条试试。',
                        context: context,
                      );
                      return;
                    }
                    _play(episode);
                  },
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('播放'),
                ),
                const SizedBox(height: 4),
                Text(
                  '来自 ${widget.item.sourceName}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 「继续观看」入口。
  ///
  /// 做成独立一条而不是把主按钮改成「继续观看」：用户可能就是想从头再看，
  /// 主按钮得保持「从头播」的确定含义，续播是个额外的、可选的入口。
  Widget _resumeBanner(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final progress = _progress!;
    final target = _resumeTarget!;

    final list = _playableOf(target.route);
    // 只有一集（电影）就别报「第 1 集」，用集名更自然
    final episodeLabel = progress.episodeTitle.isNotEmpty
        ? '${progress.episodeTitle} · '
        : (list.length > 1 ? '第 ${target.episodeIndex + 1} 集 · ' : '');

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Material(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _resume,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(Icons.history_rounded,
                    size: 20, color: colors.onSecondaryContainer),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '继续观看',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$episodeLabel看到 ${progress.positionLabel}'
                        '${progress.remainingLabel.isEmpty ? '' : ' · 剩 ${progress.remainingLabel}'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.onSecondaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${(progress.percent * 100).round()}%',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSecondaryContainer,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _metaLine {
    final d = _detail!;
    final parts = <String>[];
    if (d.year.isNotEmpty) parts.add(d.year);
    if (d.area.isNotEmpty) parts.add(d.area);
    if (d.typeName.isNotEmpty) parts.add(d.typeName);
    if (d.score > 0) parts.add('${d.score} 分');
    return parts.join(' · ');
  }

  String get _directorLine => _detail!.directors.join(' / ');

  String get _actorLine {
    final actors = _detail!.actors;
    if (actors.length <= 5) return actors.join(' / ');
    return '${actors.take(5).join(' / ')} 等';
  }

  Widget _creditLine(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        '$label：$value',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall
            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  Widget _tag(
    BuildContext context,
    String text,
    Color background,
    Color foreground,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }

  // -------------------------------------------------------------------- 线路

  Widget _routesSection(BuildContext context, MovieDetail detail) {
    final theme = Theme.of(context);
    final routes = _routes;

    if (routes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '这个源给的地址都不完整（不是完整网址），一条都拼不出来。'
            '回上一页换一个源试试。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onErrorContainer,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Row(
            children: [
              Text(
                '线路',
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(width: 8),
              Text(
                '共 ${detail.routes.length} 条，${routes.length} 条可用',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        MovieRouteSelector(
          routes: routes,
          selectedIndex: _routeIndex.clamp(0, routes.length - 1),
          onSelected: (index) => setState(() => _routeIndex = index),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- 选集

  Widget _episodesSection(BuildContext context) {
    final theme = Theme.of(context);
    final route = _currentRoute;
    if (route == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            '选集（${route.episodes.length}）',
            style:
                theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        if (route.resolvableCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              '其中 ${route.resolvableCount} 集来自网页播放页，'
              '播放前会先解析出真实地址（可能要等几秒）。',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: MovieEpisodeGrid(
            // key 带上线路名：换线路时重建，避免复用上一线路的滚动/选中状态
            key: ValueKey('episodes-${route.name}'),
            episodes: route.episodes,
            onSelected: (index) => _play(route.episodes[index]),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- 简介

  Widget _introSection(BuildContext context, MovieDetail detail) {
    if (detail.content.trim().isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '简介',
            style:
                theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          _ExpandableText(text: detail.content),
        ],
      ),
    );
  }
}

/// 简介默认只显示 3 行，点「展开」看全部。
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          maxLines: _expanded ? null : 3,
          overflow: _expanded ? null : TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
        ),
        TextButton(
          onPressed: () => setState(() => _expanded = !_expanded),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(_expanded ? '收起' : '展开'),
        ),
      ],
    );
  }
}
