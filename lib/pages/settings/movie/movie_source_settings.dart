import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:perzutv/bean/dialog/dialog_helper.dart';
import 'package:perzutv/bean/settings/settings_detail_scaffold.dart';
import 'package:perzutv/bean/settings/settings_list.dart';
import 'package:perzutv/modules/movie/builtin_movie_sources.dart';
import 'package:perzutv/modules/movie/movie_source.dart';
import 'package:perzutv/pages/settings/movie/movie_source_edit_dialog.dart';
import 'package:perzutv/services/movie/movie_source_manager.dart';

/// 影视源管理。
///
/// 能力：增 / 删 / 改、启用停用、单源探活、批量导入导出、URL 订阅。
/// 拖拽排序暂未做（列表较长时拖拽体验不稳，先按 order 展示，靠「置顶」按钮调）。
class MovieSourceSettingsPage extends StatefulWidget {
  const MovieSourceSettingsPage({super.key});

  @override
  State<MovieSourceSettingsPage> createState() => _MovieSourceSettingsPageState();
}

class _MovieSourceSettingsPageState extends State<MovieSourceSettingsPage> {
  List<MovieSource> _sources = const [];

  /// 高画质源总开关（默认关）
  bool _highQualityEnabled = false;

  /// 正在探活的源 key
  final Set<String> _probing = {};

  /// 探活结果（key -> 显示文案）
  final Map<String, String> _probeLabels = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() {
      _sources = MovieSourceManager.all();
      _highQualityEnabled = MovieSourceManager.highQualityEnabled;
    });
  }

  Future<void> _toggleHighQuality(bool value) async {
    await MovieSourceManager.setHighQualityEnabled(value);
    if (!mounted) return;
    _reload();
  }

  // ---------------------------------------------------------------- 操作

  Future<void> _add() async {
    final result = await showMovieSourceEditDialog(context);
    if (result == null) return;
    final created = MovieSourceManager.add(
      name: result.name,
      api: result.api,
      detail: result.detail,
      isAdult: result.isAdult,
    );
    if (created == null) {
      KazumiDialog.showToast(message: '添加失败：该接口地址已存在');
      return;
    }
    _reload();
  }

  Future<void> _edit(MovieSource source) async {
    final result = await showMovieSourceEditDialog(context, existing: source);
    if (result == null) return;
    MovieSourceManager.update(result);
    _reload();
  }

  Future<void> _remove(MovieSource source) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除影视源'),
        content: Text('确定删除「${source.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    MovieSourceManager.remove(source.key);
    _reload();
  }

  Future<void> _probe(MovieSource source) async {
    setState(() => _probing.add(source.key));
    final result = await MovieSourceManager.probe(source);
    if (!mounted) return;
    setState(() {
      _probing.remove(source.key);
      _probeLabels[source.key] = result.label;
    });
  }

  Future<void> _probeAll() async {
    final targets = _sources.where((s) => s.enabled).toList();
    if (targets.isEmpty) {
      KazumiDialog.showToast(message: '没有启用的源');
      return;
    }
    setState(() => _probing.addAll(targets.map((s) => s.key)));
    final results = await MovieSourceManager.probeAll(targets);
    if (!mounted) return;
    setState(() {
      _probing.removeAll(targets.map((s) => s.key));
      results.forEach((key, r) => _probeLabels[key] = r.label);
    });
    _reload();
  }

  Future<void> _import() async {
    final payload = await showMovieSourceImportDialog(context);
    if (payload == null) return;
    final added = MovieSourceManager.mergeImport(payload.sources);
    _reload();
    KazumiDialog.showToast(
      message: added > 0 ? '已导入 $added 个源' : '没有新源可导入（都已存在）',
    );
  }

  Future<void> _export() async {
    final json = MovieSourceManager.toSourceListJson(_sources);
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) return;
    KazumiDialog.showToast(message: '已复制到剪贴板（LibreTV 兼容格式）');
  }

  void _restoreBuiltin() {
    MovieSourceManager.restoreBuiltin();
    _reload();
    KazumiDialog.showToast(message: '已恢复内置源');
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final normal = _sources.where((s) => !s.highQuality).toList();
    final highQuality = _sources.where((s) => s.highQuality).toList();

    // 实际参与搜索的源：普通源按自己的开关，高画质源还要过总开关
    int participating(List<MovieSource> list) => list
        .where((s) => s.enabled && (!s.highQuality || _highQualityEnabled))
        .length;
    final enabledCount = participating(normal) + participating(highQuality);

    return SettingsDetailScaffold(
      title: const Text('影视源'),
      actions: [
        IconButton(
          tooltip: '添加',
          onPressed: _add,
          icon: const Icon(Icons.add_rounded),
        ),
        PopupMenuButton<String>(
          tooltip: '更多',
          onSelected: (value) {
            switch (value) {
              case 'probe':
                _probeAll();
              case 'import':
                _import();
              case 'export':
                _export();
              case 'restore':
                _restoreBuiltin();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'probe', child: Text('批量探活')),
            PopupMenuItem(value: 'import', child: Text('导入…')),
            PopupMenuItem(value: 'export', child: Text('导出到剪贴板')),
            PopupMenuItem(value: 'restore', child: Text('恢复内置源')),
          ],
        ),
      ],
      body: SettingsList(
        sections: [
          SettingsSection(
            title: Text('普通源 · ${normal.length} 个，${participating(normal)} 个参与搜索'),
            bottomInfo: const Text(
              '搜索会并发请求所有启用的源；某个源失败不影响其它源，'
              '失败情况会在搜索结果页列出。\n'
              '采集站的「云线路」给的是网页播放页，应用会自动从页面里解析出'
              '真实地址，不需要额外配置。平台页面（腾讯/爱奇艺等）需要'
              '「解析源」—— 那要自己填接口。',
              style: TextStyle(fontSize: 12),
            ),
            tiles: [
              for (final source in normal)
                _SourceTile(
                  source: source,
                  probing: _probing.contains(source.key),
                  probeLabel: _probeLabels[source.key],
                  onToggle: (value) {
                    MovieSourceManager.setEnabled(source.key, value);
                    _reload();
                  },
                  onTap: () => _edit(source),
                  onProbe: () => _probe(source),
                  onDelete: builtinMovieSourceKeys.contains(source.key)
                      ? null
                      : () => _remove(source),
                ),
            ],
          ),
          SettingsSection(
            title: Text(
              '高画质源 · ${highQuality.length} 个，'
              '${participating(highQuality)} 个参与搜索',
            ),
            bottomInfo: const Text(
              '这些源实测能给到 1080p 及以上（只有「光速资源」是每部片都能到，'
              '其余几个是部分内容能到）。代价是响应更慢、更费流量，所以默认关闭。\n'
              '关掉时它们完全不参与搜索；打开后仍可逐个停用。',
              style: TextStyle(fontSize: 12),
            ),
            tiles: [
              SettingsTile(
                title: const Text('启用高画质源'),
                description: Text(
                  _highQualityEnabled
                      ? '已启用 —— 搜索会多查这几个源，稍微慢一点'
                      : '当前关闭，搜索只用上面的普通源',
                ),
                trailing: Switch(
                  value: _highQualityEnabled,
                  onChanged: _toggleHighQuality,
                ),
              ),
              for (final source in highQuality)
                _SourceTile(
                  source: source,
                  probing: _probing.contains(source.key),
                  probeLabel: _probeLabels[source.key],
                  // 总开关关着时，单个开关操作了也不生效，直观上容易误解，
                  // 所以直接禁用它（打开总开关后就能单独调）。
                  enabledOverride: _highQualityEnabled,
                  onToggle: (value) {
                    MovieSourceManager.setEnabled(source.key, value);
                    _reload();
                  },
                  onTap: () => _edit(source),
                  onProbe: () => _probe(source),
                  onDelete: builtinMovieSourceKeys.contains(source.key)
                      ? null
                      : () => _remove(source),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({
    required this.source,
    required this.probing,
    required this.onToggle,
    required this.onTap,
    required this.onProbe,
    this.probeLabel,
    this.onDelete,
    this.enabledOverride,
  });

  final MovieSource source;
  final bool probing;
  final String? probeLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final VoidCallback onProbe;

  /// 内置源不允许删除（传 null）
  final VoidCallback? onDelete;

  /// 上层总开关的状态。为 false 时这个源的开关不可操作。
  final bool? enabledOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isBuiltin = builtinMovieSourceKeys.contains(source.key);
    final interactive = enabledOverride ?? true;

    final String status;
    if (probing) {
      status = '探活中…';
    } else if (probeLabel != null) {
      status = probeLabel!;
    } else if (source.lastLatencyMs >= 0 && source.lastOkAt > 0) {
      status = '上次 ${source.lastLatencyMs} ms';
    } else if (source.lastLatencyMs == -1 && source.lastOkAt == 0) {
      status = '未探活';
    } else {
      status = '上次失败';
    }

    final title = isBuiltin ? '${source.name}（内置）' : source.name;

    return SettingsTile(
      title: Text(title),
      description: Text(
        '${source.api}\n${interactive ? status : "高画质源已关闭"}',
      ),
      onPressed: (context) => onTap(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '探活',
            onPressed: probing ? null : onProbe,
            icon: probing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering_rounded, size: 20),
          ),
          Switch(
            value: source.enabled,
            onChanged: interactive ? onToggle : null,
          ),
          if (onDelete != null)
            IconButton(
              tooltip: '删除',
              onPressed: onDelete,
              icon: Icon(
                Icons.delete_outline_rounded,
                size: 20,
                color: theme.colorScheme.error,
              ),
            ),
        ],
      ),
    );
  }
}
