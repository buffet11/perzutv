import 'package:flutter/material.dart';
import 'package:kazutv/modules/movie/movie_detail.dart';

/// 线路选择器。
///
/// 传入的 [routes] 应当已经排好序（`MovieDetail.availableRoutes`），
/// 第一个就是默认该选的那条。顺序不能按源站给的来 —— 实测电影天堂的
/// 「流浪地球2」第一条线路是网页播放页，交给播放器只会黑屏。
///
/// 两种线路都会出现在这里：
///   - **直链线路**（`xxxm3u8`）：点了直接播。
///   - **网页线路**（`xxx云`，地址是播放页）：也能播 —— 播放页会先解析出
///     真直链。测下来每个采集源都有这么一条，不该因为「不是直链」就藏起来。
class MovieRouteSelector extends StatelessWidget {
  const MovieRouteSelector({
    super.key,
    required this.routes,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<MovieRoute> routes;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    if (routes.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: routes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) => _routeChip(context, index),
      ),
    );
  }

  Widget _routeChip(BuildContext context, int index) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final route = routes[index];
    final selected = index == selectedIndex;

    // 完全不能用的线路（只在异常情况下出现）保持不可用的样式，
    // 免得点进去才发现播不了。
    final usable = route.actionable;
    final foreground = usable
        ? (selected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant)
        : colorScheme.outline;

    final String subtitle;
    if (route.playable) {
      subtitle = '${route.episodes.length} 集';
    } else if (usable) {
      subtitle = '网页线路 · 需解析';
    } else {
      subtitle = '来源页 · 不可播';
    }

    return Center(
      child: InkWell(
        onTap: () => onSelected(index),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected
                ? colorScheme.primary
                : colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border:
                usable ? null : Border.all(color: colorScheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                route.name,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: usable
                      ? (selected ? colorScheme.onPrimary : null)
                      : colorScheme.outline,
                  decoration: usable ? null : TextDecoration.lineThrough,
                ),
              ),
              Text(
                subtitle,
                style: theme.textTheme.labelSmall?.copyWith(color: foreground),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
