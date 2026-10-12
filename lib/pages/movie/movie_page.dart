import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:perzutv/bean/appbar/sys_app_bar.dart';
import 'package:perzutv/bean/card/network_img_layer.dart';
import 'package:perzutv/bean/widget/empty_state_widget.dart';
import 'package:perzutv/bean/widget/loading_indicator.dart';
import 'package:perzutv/modules/movie/movie_history.dart';
import 'package:perzutv/modules/movie/movie_item.dart';
import 'package:perzutv/pages/movie/movie_controller.dart';
import 'package:perzutv/pages/movie/movie_result_grid.dart';
import 'package:perzutv/pages/movie/movie_source_chips.dart';

/// 影视 Tab：搜索框 + 搜索历史 + 结果网格。
///
/// 与番剧走的是两条完全不同的链路（苹果CMS JSON API vs Bangumi 元数据），
/// 所以做成独立 Tab 而不是并进番剧搜索 —— 并进去两套数据会互相污染排序与筛选。
class MoviePage extends StatefulWidget {
  const MoviePage({super.key, required this.controller});

  final MovieController controller;

  @override
  State<MoviePage> createState() => _MoviePageState();
}

class _MoviePageState extends State<MoviePage> {
  final _input = TextEditingController();
  final _focus = FocusNode();

  /// 「继续观看」横向卡片的固定高度：封面 160 + 片名两行 + 源名 + 间距。
  static const double _watchCardHeight = 236;

  MovieController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    // 首次进入先读一次观看历史，初始态才能显示「继续观看」。
    _controller.loadWatchHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit([String? value]) async {
    final kw = (value ?? _input.text).trim();
    if (kw.isEmpty) {
      _focus.requestFocus();
      return;
    }
    if (_input.text != kw) {
      _input.value = TextEditingValue(
        text: kw,
        selection: TextSelection.collapsed(offset: kw.length),
      );
    }
    _focus.unfocus();
    await _controller.search(kw);
  }

  /// 进入详情页；等它（以及叠在上面的播放页）整体返回后再刷新观看历史。
  ///
  /// 用「await push 的 Future」而不是 RouteObserver：影视 Tab 的页面挂在
  /// `RouterOutlet` 的**嵌套** Navigator 上，而源码里那个 rootRouteObserver
  /// 只跟踪根 Navigator —— 详情页是推到根上的，嵌套页签收不到 `didPopNext`。
  /// 等 push 返回是唯一不依赖导航层级、又最简单的做法。
  Future<void> _openDetail(MovieSearchItem item) async {
    await context.pushNamed('/movie-detail/', arguments: item);
    if (!mounted) return;
    // 刚看完一集回来，进度/新记录都可能变了，「继续观看」要立刻反映出来。
    await _controller.loadWatchHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        needTopOffset: false,
        toolbarHeight: 72,
        title: Text(
          '影视',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: '管理影视源',
            icon: const Icon(Icons.dns_outlined),
            onPressed: () => context.pushNamed('/settings/movie-source'),
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
              _searchField(context),
              if (_controller.hasSearched) _filterRow(context),
              Expanded(child: _body(context)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 搜索框

  Widget _searchField(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: TextField(
        controller: _input,
        focusNode: _focus,
        textInputAction: TextInputAction.search,
        onSubmitted: _submit,
        decoration: InputDecoration(
          hintText: '搜索电影、剧集、综艺',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _input.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空',
                  icon: const Icon(Icons.close),
                  onPressed: () {
                    _input.clear();
                    setState(() {});
                  },
                ),
          filled: true,
          fillColor: colorScheme.surfaceContainerHigh,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(28),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
        ),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  // ------------------------------------------------------- 筛选条 / 失败提示

  Widget _filterRow(BuildContext context) {
    final sources = _controller.searchedSources;
    if (sources.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        MovieSourceChips(
          sources: sources,
          counts: _controller.countBySource,
          failedKeys: _controller.failures.map((e) => e.sourceKey).toSet(),
          selectedKey: _controller.sourceFilter,
          totalCount: _controller.outcome?.items.length ?? 0,
          onSelected: _controller.setSourceFilter,
        ),
        if (_controller.failures.isNotEmpty) _failuresBar(context),
      ],
    );
  }

  /// 失败的源必须显示出来。
  ///
  /// 否则用户看到「没有结果」会以为这部片不存在，实际可能只是某个源超时了。
  Widget _failuresBar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final failures = _controller.failures;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.wifi_off_rounded,
              size: 18, color: colorScheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${failures.length} 个源未响应：'
              '${failures.map((f) => f.sourceName).join('、')}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------- 主体

  Widget _body(BuildContext context) {
    if (_controller.searching) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LoadingIndicator(size: 44),
            const SizedBox(height: 16),
            Text(
              '正在搜索 ${_controller.sources.length} 个源…',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (_controller.errorMessage != null) {
      return GeneralEmptyState(
        icon: Icons.error_outline,
        title: '搜索失败\n${_controller.errorMessage}',
        actions: [
          FilledButton.tonal(
            onPressed: () => _submit(_controller.keyword),
            child: const Text('重试'),
          ),
        ],
      );
    }

    if (_controller.noSourceEnabled) {
      return const GeneralEmptyState(
        icon: Icons.dns_outlined,
        title: '没有启用的影视源\n请先到「管理影视源」里启用至少一个。',
      );
    }

    if (!_controller.hasSearched) return _initialState(context);

    final items = _controller.items;
    if (items.isEmpty) {
      return GeneralEmptyState(
        icon: Icons.search_off,
        title: _controller.allFailed
            ? '所有源都没有响应\n可能是网络问题，稍后再试。'
            : '没找到「${_controller.keyword}」\n换个关键词，或到「管理影视源」多启用几个源。',
        actions: [
          FilledButton.tonal(
            onPressed: () => _submit(_controller.keyword),
            child: const Text('重试'),
          ),
        ],
      );
    }

    return MovieResultGrid(items: items, onTap: _openDetail);
  }

  /// 还没搜过时的首页：观看历史（继续观看）+ 搜索历史。
  ///
  /// 两样都为空才显示空状态 —— 只要有「看过的片子」就先把它们列出来，
  /// 用户不必再手动搜一遍。
  Widget _initialState(BuildContext context) {
    final watch = _controller.watchHistory;
    final history = _controller.history;

    if (watch.isEmpty && history.isEmpty) {
      return const GeneralEmptyState(
        icon: Icons.movie_outlined,
        title: '搜一部电影试试\n聚合了多个影视源，同一个片子可以换源播放。',
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (watch.isNotEmpty) _continueWatching(context, watch),
          if (watch.isNotEmpty && history.isNotEmpty) const SizedBox(height: 24),
          if (history.isNotEmpty) _searchHistory(context, history),
        ],
      ),
    );
  }

  /// 「继续观看」：横向卡片列表。
  ///
  /// 用横向 ListView（固定高度）而不是把 MovieResultGrid 塞进来 —— 后者内部
  /// 是纵向 GridView，套在外层 SingleChildScrollView 里会变成嵌套纵向滚动。
  /// 横向滚动与纵向互不干扰，窄窗口下也能正常滑。
  Widget _continueWatching(BuildContext context, List<MoviePlayProgress> list) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '继续观看',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 8),
            Text(
              '${list.length}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _watchCardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final progress = list[index];
              final item = _controller.toSearchItem(progress);
              return _WatchHistoryCard(
                item: item,
                progressLabel: _progressText(progress),
                onTap: () => _openDetail(item),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 搜索历史 chips：点击回填搜索、单删、清空。
  Widget _searchHistory(BuildContext context, List<String> history) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '搜索历史',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            TextButton(
              onPressed: _controller.clearHistory,
              child: const Text('清空'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final kw in history)
              // 用 InputChip 而不是 ActionChip：ActionChip 没有 onDeleted，
              // 单删能力只有 Chip / InputChip 支持（且 InputChip 同样可点）。
              InputChip(
                label: Text(kw),
                onPressed: () {
                  _input.text = kw;
                  _submit(kw);
                },
                onDeleted: () => _controller.removeHistory(kw),
                deleteIcon: const Icon(Icons.close, size: 16),
              ),
          ],
        ),
      ],
    );
  }

  /// 进度文案：基本播到结尾算「已看完」，否则显示「看到 mm:ss / h:mm:ss」。
  ///
  /// 「已看完」的门槛与 [MoviePlayProgress.resumable] 的尾部判定一致（距结尾 30s 内）。
  String _progressText(MoviePlayProgress progress) {
    if (progress.durationSeconds > 0 &&
        progress.positionSeconds >= progress.durationSeconds - 30) {
      return '已看完';
    }
    return '看到 ${progress.positionLabel}';
  }
}

/// 「继续观看」横向卡片：封面 + 片名 + 进度标签 + 来源源名。
class _WatchHistoryCard extends StatelessWidget {
  const _WatchHistoryCard({
    required this.item,
    required this.progressLabel,
    required this.onTap,
  });

  final MovieSearchItem item;
  final String progressLabel;
  final VoidCallback onTap;

  static const double _width = 120;
  static const double _coverHeight = 160;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    const radius = BorderRadius.all(Radius.circular(10));

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: _width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                // 传真实尺寸：NetworkImgLayer 会按 (尺寸 * dpr) 算解码缓存，
                // double.infinity 会抛 UnsupportedError（同 MovieResultGrid）。
                NetworkImgLayer(
                  src: item.pic,
                  width: _width,
                  height: _coverHeight,
                  fit: BoxFit.cover,
                  borderRadius: radius,
                ),
                // 进度标签压在封面底部，一眼看出看到哪了
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: colorScheme.scrim.withValues(alpha: 0.72),
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(10),
                      ),
                    ),
                    child: Text(
                      progressLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.2,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onInverseSurface,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              item.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.sourceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
