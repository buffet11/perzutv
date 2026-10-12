import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:perzutv/bean/appbar/sys_app_bar.dart';
import 'package:perzutv/bean/widget/empty_state_widget.dart';
import 'package:perzutv/bean/widget/loading_indicator.dart';
import 'package:perzutv/modules/movie/movie_category.dart';
import 'package:perzutv/modules/movie/movie_item.dart';
import 'package:perzutv/modules/movie/movie_origin.dart';
import 'package:perzutv/pages/anime/anime_controller.dart';
import 'package:perzutv/pages/movie/movie_result_grid.dart';

/// 「动漫」Tab：顶部分区条 + 分区动漫网格。
///
/// 数据来自苹果 CMS 采集源的动漫分区（见 `AnimeCatalogService`），
/// 点条目直接进影视详情页选线路播放，所以不需要番剧插件那一套。
class AnimePage extends StatefulWidget {
  const AnimePage({super.key, required this.controller});

  final AnimeController controller;

  @override
  State<AnimePage> createState() => _AnimePageState();
}

class _AnimePageState extends State<AnimePage> {
  AnimeController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // 控制器是单例，init() 内部保证只跑一次。
    _controller.init();
  }

  void _openDetail(MovieSearchItem item) {
    // 与影视模块一致：详情页挂在根路由上，点进去即可选线路播放。
    // 标记来源模块 —— 观看记录要靠它区分「动漫」和「影视」两个列表。
    context.pushNamed(
      '/movie-detail/',
      arguments: item.copyWith(origin: MovieOrigin.anime),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        needTopOffset: false,
        toolbarHeight: 72,
        title: Text(
          '动漫',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          // 正版入口：不走采集源，直接用 B 站官方外链播放器（不消耗本机解码）。
          // 对这台核显机器来说，这条路的观看体验比开超分滤镜好得多。
          IconButton(
            tooltip: '正版番剧',
            icon: const Icon(Icons.verified_outlined),
            onPressed: () => context.pushNamed('/official/'),
          ),
          IconButton(
            tooltip: '刷新分区',
            icon: const Icon(Icons.refresh),
            // 内部先让分区缓存失效再重取，用户改完源开关后可手动刷。
            onPressed: () => _controller.refresh(),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        child: ListenableBuilder(
          listenable: _controller,
          builder: (context, _) => Column(
            children: [
              _partitionBar(context),
              _sourceCaption(context),
              if (_controller.loadingMore)
                const LinearProgressIndicator(minHeight: 3),
              Expanded(child: _body(context)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 分区条

  Widget _partitionBar(BuildContext context) {
    final partitions = _controller.partitions;
    if (partitions.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          for (final partition in partitions)
            _partitionChip(context, partition),
          // 右侧余量，横滑到最后一项不至于贴边
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _partitionChip(BuildContext context, AnimePartition partition) {
    final colorScheme = Theme.of(context).colorScheme;
    final selected = partition.id == _controller.selected.id;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: ChoiceChip(
          label: Text(partition.label),
          selected: selected,
          onSelected: (_) => _controller.selectPartition(partition),
          labelStyle: TextStyle(
            fontSize: 12,
            color: selected ? colorScheme.onSecondaryContainer : null,
          ),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  /// 分区条下的小字：说明这次列表来自几个采集源。
  Widget _sourceCaption(BuildContext context) {
    final count = _controller.sourceCount;
    if (count <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '来自 $count 个采集源',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------- 主体

  Widget _body(BuildContext context) {
    if (_controller.loading && _controller.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LoadingIndicator(size: 44),
            const SizedBox(height: 16),
            Text('正在加载动漫…', style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }

    if (_controller.errorMessage != null && _controller.items.isEmpty) {
      return GeneralEmptyState(
        icon: Icons.error_outline,
        title: '加载失败\n${_controller.errorMessage}',
        actions: [
          FilledButton.tonal(
            onPressed: () => _controller.refresh(),
            child: const Text('重试'),
          ),
        ],
      );
    }

    if (_controller.items.isEmpty) {
      return GeneralEmptyState(
        icon: Icons.animation_outlined,
        title: '暂时没有拿到动漫列表\n'
            '部分采集站的分类接口不稳定，可点右上角刷新重试；\n'
            '也可以到 设置 → 影视源 启用更多源。',
        actions: [
          FilledButton.tonal(
            onPressed: () => _controller.refresh(),
            child: const Text('刷新试试'),
          ),
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _controller.refresh,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          // 距底部 200px 内预取下一页（阈值与 popular_page 的 scroll listener 一致）
          if (notification.metrics.pixels >=
              notification.metrics.maxScrollExtent - 200) {
            _controller.loadMore();
          }
          return false;
        },
        child: MovieResultGrid(items: _controller.items, onTap: _openDetail),
      ),
    );
  }
}
