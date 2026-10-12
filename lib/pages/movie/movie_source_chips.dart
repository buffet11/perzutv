import 'package:flutter/material.dart';
import 'package:perzutv/modules/movie/movie_source.dart';

/// 结果筛选条：按源过滤。
///
/// 为什么必须有：多源聚合出来的是「同一部片的好几条重复结果」，
/// 不给筛的话用户得在几十条里自己认。顺带也是失败的可见位置之一。
class MovieSourceChips extends StatelessWidget {
  const MovieSourceChips({
    super.key,
    required this.sources,
    required this.counts,
    required this.failedKeys,
    required this.selectedKey,
    required this.totalCount,
    required this.onSelected,
  });

  final List<MovieSource> sources;

  /// sourceKey -> 命中条数
  final Map<String, int> counts;

  /// 本次失败的源 key
  final Set<String> failedKeys;

  final String? selectedKey;
  final int totalCount;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _chip(
            context,
            label: '全部 $totalCount',
            selected: selectedKey == null,
            onTap: () => onSelected(null),
          ),
          for (final source in sources)
            _chip(
              context,
              label: _labelFor(source),
              selected: selectedKey == source.key,
              // 失败的源仍然可点（能看到失败详情），但显示成弱化样式
              muted: failedKeys.contains(source.key),
              onTap: () => onSelected(source.key),
            ),
          // 留出右侧余量，横滑到最后一项不至于贴边
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  String _labelFor(MovieSource source) {
    if (failedKeys.contains(source.key)) return '${source.name} 失败';
    final count = counts[source.key] ?? 0;
    return '${source.name} $count';
  }

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool muted = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Center(
        child: ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => onTap(),
          labelStyle: TextStyle(
            fontSize: 12,
            color: muted
                ? colorScheme.onSurfaceVariant
                : (selected ? colorScheme.onSecondaryContainer : null),
          ),
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }
}
