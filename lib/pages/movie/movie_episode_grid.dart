import 'package:flutter/material.dart';
import 'package:perzutv/modules/movie/movie_detail.dart';

/// 剧集网格。
///
/// 电影通常只有一集（标题类似「HD国语」），剧集/综艺会有几十集。
///
/// 三种集：
///   - **直链**：点了直接播。
///   - **网页播放页**：地址是完整网址但指向一页 HTML（采集站的 `xxx云` 线路）。
///     仍然可点 —— 播放页会先把它解析成真直链。用较浅的字色标出来。
///   - **都没有**：源站给了个不完整的地址，点不了。保留展示但禁用 ——
///     直接藏起来会让用户以为「这部剧只有 5 集」，其实只是这个源没给全。
class MovieEpisodeGrid extends StatelessWidget {
  const MovieEpisodeGrid({
    super.key,
    required this.episodes,
    this.currentIndex,
    required this.onSelected,
    this.actionableOnly = false,
  });

  final List<MovieEpisode> episodes;
  final int? currentIndex;
  final ValueChanged<int> onSelected;

  /// 只看能播的（含需要解析的）
  final bool actionableOnly;

  @override
  Widget build(BuildContext context) {
    final visible = actionableOnly
        ? [
            for (var i = 0; i < episodes.length; i++)
              if (episodes[i].actionable) i,
          ]
        : [for (var i = 0; i < episodes.length; i++) i];

    if (visible.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          '这条线路没有能播的剧集，换一条线路试试。',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final i in visible)
          _episodeChip(context, i, episodes[i], i == currentIndex),
      ],
    );
  }

  Widget _episodeChip(
    BuildContext context,
    int index,
    MovieEpisode episode,
    bool selected,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // 需要解析的集：仍然可点，但用更浅的字色标出来
    final needsResolve = !episode.playable && episode.resolvable;

    final button = SizedBox(
      width: 96,
      child: OutlinedButton(
        onPressed: episode.actionable ? () => onSelected(index) : null,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          backgroundColor: selected ? colorScheme.primaryContainer : null,
          side: selected
              ? BorderSide(color: colorScheme.primary, width: 1.5)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          episode.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? colorScheme.onPrimaryContainer
                : (needsResolve ? colorScheme.onSurfaceVariant : null),
          ),
        ),
      ),
    );

    if (!needsResolve) return button;
    return Tooltip(
      message: '这一集来自网页播放页，播放前会先解析出真实地址',
      child: button,
    );
  }
}
