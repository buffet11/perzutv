import 'package:flutter/material.dart';
import 'package:perzutv/bean/card/network_img_layer.dart';
import 'package:perzutv/modules/movie/movie_item.dart';

/// 搜索结果网格。
///
/// 用 [SliverGridDelegateWithMaxCrossAxisExtent] 而不是固定列数：
/// 窗口宽度从手机竖屏到桌面横屏跨得很厉害，固定列数在某一端一定难看。
class MovieResultGrid extends StatelessWidget {
  const MovieResultGrid({
    super.key,
    required this.items,
    required this.onTap,
  });

  final List<MovieSearchItem> items;
  final ValueChanged<MovieSearchItem> onTap;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 168,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 0.52,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) => MovieResultCard(
        item: items[index],
        onTap: () => onTap(items[index]),
      ),
    );
  }
}

/// 单张结果卡片：海报 + 标题 + 源标签 + 年份/备注。
class MovieResultCard extends StatelessWidget {
  const MovieResultCard({super.key, required this.item, required this.onTap});

  final MovieSearchItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _poster(context)),
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
            _subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  String get _subtitle {
    final parts = <String>[];
    if (item.year.isNotEmpty) parts.add(item.year);
    if (item.remarks.isNotEmpty) parts.add(item.remarks);
    if (item.scoreValue != null) parts.add('${item.score}分');
    return parts.join(' · ');
  }

  Widget _poster(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const radius = BorderRadius.all(Radius.circular(10));
    return ClipRRect(
      borderRadius: radius,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 必须传真实尺寸：NetworkImgLayer 内部会做
          // `(尺寸 * devicePixelRatio).round()` 来算解码缓存，
          // 传 double.infinity 会直接抛 UnsupportedError。
          LayoutBuilder(
            builder: (context, constraints) => NetworkImgLayer(
              src: item.pic,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              fit: BoxFit.cover,
              borderRadius: radius,
            ),
          ),
          // 源标签：多源是这套方案的核心价值，用户得一眼看出这条来自哪个源
          Positioned(
            left: 4,
            top: 4,
            child: _badge(
              context,
              text: item.sourceName,
              background: colorScheme.primary,
              foreground: colorScheme.onPrimary,
            ),
          ),
          if (item.isAdult)
            Positioned(
              right: 4,
              top: 4,
              child: _badge(
                context,
                text: '18+',
                background: colorScheme.errorContainer,
                foreground: colorScheme.onErrorContainer,
              ),
            ),
        ],
      ),
    );
  }

  Widget _badge(
    BuildContext context, {
    required String text,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          height: 1.3,
          fontWeight: FontWeight.w600,
          color: foreground,
        ),
      ),
    );
  }
}
