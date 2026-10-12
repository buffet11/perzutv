import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:perzutv/bean/card/network_img_layer.dart';
import 'package:perzutv/bean/dialog/dialog_helper.dart';
import 'package:perzutv/bean/settings/settings_detail_scaffold.dart';
import 'package:perzutv/bean/widget/empty_state_widget.dart';
import 'package:perzutv/modules/movie/movie_history.dart';
import 'package:perzutv/modules/movie/movie_item.dart';
import 'package:perzutv/modules/movie/movie_origin.dart';
import 'package:perzutv/services/movie/movie_history_service.dart';
import 'package:perzutv/services/movie/movie_source_manager.dart';

/// 「我的 → 观看记录」：影视与动漫各自的观看记录。
///
/// 为什么两个列表能分开：动漫模块与影视模块走的是**同一套**采集源播放链路，
/// 历史都写在 `MovieHistoryService` 里；记录里带了 [MoviePlayProgress.origin]
/// （入口页赋的），这里按它分成两组。
///
/// 交互：点条目 → 直接进详情页（可续播）；每条右侧可单独删除；
/// 右上角可清空当前列表（有二次确认）。
class WatchRecordsPage extends StatefulWidget {
  const WatchRecordsPage({super.key});

  @override
  State<WatchRecordsPage> createState() => _WatchRecordsPageState();
}

class _WatchRecordsPageState extends State<WatchRecordsPage> {
  /// 当前展示哪个来源模块的列表。
  String _origin = MovieOrigin.movie;

  /// 全量记录（一次读盘，切换列表只是过滤，不再读盘）。
  List<MoviePlayProgress> _all = const [];

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    List<MoviePlayProgress> list;
    try {
      list = MovieHistoryService.all();
    } catch (_) {
      // 读盘失败只降级为空列表 —— 记录读不出来不该把整个页面搞崩
      list = const <MoviePlayProgress>[];
    }
    if (!mounted) return;
    setState(() {
      _all = list;
      _loading = false;
    });
  }

  List<MoviePlayProgress> get _visible =>
      _all.where((r) => r.origin == _origin).toList();

  int _countOf(String origin) =>
      _all.where((r) => r.origin == origin).length;

  /// 把一条记录还原成详情页需要的 arguments（详情页会自己拉详情并续播）。
  MovieSearchItem _toItem(MoviePlayProgress record) => MovieSearchItem(
        sourceKey: record.sourceKey,
        sourceName: MovieSourceManager.displayNameOf(record.sourceKey),
        vodId: record.vodId,
        name: record.name,
        pic: record.coverUrl,
        // 保持原来的来源模块，回来后写入的记录仍归到同一个列表
        origin: record.origin,
      );

  Future<void> _open(MoviePlayProgress record) async {
    await context.pushNamed('/movie-detail/', arguments: _toItem(record));
    if (!mounted) return;
    // 刚看完回来，进度/时间都变了，刷新一次
    await _load();
  }

  Future<void> _remove(MoviePlayProgress record) async {
    try {
      await MovieHistoryService.removeRecord(record);
    } catch (_) {}
    if (!mounted) return;
    // 本地先摘掉，界面立刻有反馈（读盘结果随后覆盖）
    setState(() {
      _all = _all
          .where((r) => r.key != record.key)
          .toList(growable: false);
    });
    KazumiDialog.showToast(message: '已删除「${record.name}」的观看记录');
    await _load();
  }

  Future<void> _clearCurrent() async {
    final current = _visible;
    if (current.isEmpty) return;
    final confirmed = await KazumiDialog.show<bool>(
      builder: (context) => AlertDialog(
        title: Text('清空${MovieOrigin.label(_origin)}记录？'),
        content: Text('将删除这 ${current.length} 条观看记录（不含另一个列表）。'
            '删除后无法恢复，但重新观看会重新记录。'),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: false),
            child: Text(
              '取消',
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await MovieHistoryService.clearOrigin(_origin);
    } catch (_) {}
    if (!mounted) return;
    KazumiDialog.showToast(message: '已清空${MovieOrigin.label(_origin)}记录');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('观看记录'),
      body: Column(
        children: [
          _header(context),
          const Divider(height: 1),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final items = _visible;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      child: Row(
        children: [
          Expanded(
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(
                  value: MovieOrigin.movie,
                  icon: const Icon(Icons.movie_outlined, size: 18),
                  label: Text('影视 ${_countOf(MovieOrigin.movie)}'),
                ),
                ButtonSegment(
                  value: MovieOrigin.anime,
                  icon: const Icon(Icons.animation, size: 18),
                  label: Text('动漫 ${_countOf(MovieOrigin.anime)}'),
                ),
              ],
              selected: {_origin},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                if (selection.isEmpty) return;
                setState(() => _origin = selection.first);
              },
            ),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: items.isEmpty ? null : _clearCurrent,
            icon: const Icon(Icons.delete_sweep_outlined, size: 20),
            label: const Text('清空'),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = _visible;
    if (items.isEmpty) {
      return GeneralEmptyState(
        icon: _origin == MovieOrigin.anime
            ? Icons.animation_outlined
            : Icons.movie_outlined,
        title: '还没有${MovieOrigin.label(_origin)}观看记录\n'
            '看过之后会自动出现在这里，点条目可以直接续播。',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 4),
      itemBuilder: (context, index) => _recordTile(context, items[index]),
    );
  }

  Widget _recordTile(BuildContext context, MoviePlayProgress record) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return InkWell(
      onTap: () => _open(record),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              // 必须给真实尺寸：NetworkImgLayer 内部按尺寸算解码缓存
              child: NetworkImgLayer(
                src: record.coverUrl.isEmpty ? null : record.coverUrl,
                width: 64,
                height: 88,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _progressLine(record),
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${MovieSourceManager.displayNameOf(record.sourceKey)}'
                    ' · ${_timeLabel(record.updatedAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: colors.outline),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '删除这条记录',
              onPressed: () => _remove(record),
              icon: Icon(Icons.delete_outline_rounded, color: colors.outline),
            ),
          ],
        ),
      ),
    );
  }

  /// 「第 3 集 · 看到 12:34」/「已看完」—— 集数只在有分集标题时显示。
  static String _progressLine(MoviePlayProgress record) {
    final buffer = StringBuffer();
    if (record.episodeTitle.isNotEmpty) {
      buffer.write(record.episodeTitle);
      buffer.write(' · ');
    } else if (record.episodeIndex > 0) {
      buffer.write('第 ${record.episodeIndex + 1} 集 · ');
    }
    if (record.durationSeconds > 0 && record.percent >= 0.98) {
      buffer.write('已看完');
    } else if (record.positionSeconds > 0) {
      buffer.write('看到 ${record.positionLabel}');
    } else {
      buffer.write('还没开始');
    }
    return buffer.toString();
  }

  /// 相对时间；超过一周就直接给日期。
  static String _timeLabel(int updatedAtMs) {
    if (updatedAtMs <= 0) return '';
    final at = DateTime.fromMillisecondsSinceEpoch(updatedAtMs);
    final diff = DateTime.now().difference(at);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    if (diff.inDays == 1) return '昨天';
    if (diff.inDays < 7) return '${diff.inDays} 天前';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-'
        '${at.day.toString().padLeft(2, '0')}';
  }
}
