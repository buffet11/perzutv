import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kazutv/bean/dialog/dialog_helper.dart';
import 'package:kazutv/bean/settings/settings_detail_scaffold.dart';
import 'package:kazutv/bean/settings/settings_list.dart';
import 'package:kazutv/modules/movie/parse_source.dart';
import 'package:kazutv/pages/settings/movie/parse_source_edit_dialog.dart';
import 'package:kazutv/services/movie/parse_source_manager.dart';
import 'package:kazutv/services/movie/stream_resolver.dart';

/// 解析源管理。
///
/// 解析源用来把「视频平台的播放页」换成能播的地址
/// （`v.qq.com` / `iqiyi.com` / `youku.com` 这类）。
///
/// **本条不内置任何接口** —— 这类接口大多是第三方搭的、生命周期短，
/// 而且合法性存疑（本质是绕过平台会员）。我们不提供也不推荐，
/// 用不用、用哪个，用户自己决定。
///
/// 需要说明的是：采集站自己的「云线路」播放页**不需要**这里配任何东西，
/// 网页解析是内置的，会自动处理。这一页只管平台页。
class ParseSourceSettingsPage extends StatefulWidget {
  const ParseSourceSettingsPage({super.key});

  @override
  State<ParseSourceSettingsPage> createState() => _ParseSourceSettingsPageState();
}

class _ParseSourceSettingsPageState extends State<ParseSourceSettingsPage> {
  List<ParseSource> _sources = const [];

  /// 正在测试的源 key
  final Set<String> _testing = {};

  /// 测试结果（key -> 文案）
  final Map<String, String> _testLabels = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    setState(() => _sources = ParseSourceManager.all());
  }

  // ---------------------------------------------------------------- 操作

  Future<void> _add() async {
    final result = await showParseSourceEditDialog(context);
    if (result == null) return;
    final created = ParseSourceManager.add(
      name: result.name,
      api: result.api,
      post: result.post,
      referer: result.referer,
    );
    if (created == null) {
      KazumiDialog.showToast(message: '添加失败：该接口地址已存在');
      return;
    }
    _reload();
  }

  Future<void> _edit(ParseSource source) async {
    final result =
        await showParseSourceEditDialog(context, existing: source);
    if (result == null) return;
    ParseSourceManager.update(result);
    _reload();
  }

  Future<void> _remove(ParseSource source) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除解析源'),
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
    ParseSourceManager.remove(source.key);
    _reload();
  }

  Future<void> _import() async {
    final sources = await showParseSourceImportDialog(context);
    if (sources == null) return;
    final added = ParseSourceManager.mergeImport(sources);
    _reload();
    KazumiDialog.showToast(
      message: added > 0 ? '已导入 $added 个解析源' : '没有新解析源可导入（都已存在）',
    );
  }

  Future<void> _export() async {
    await Clipboard.setData(
      ClipboardData(text: ParseSourceManager.exportJson()),
    );
    if (!mounted) return;
    KazumiDialog.showToast(message: '已复制到剪贴板');
  }

  /// 测一个解析源。
  ///
  /// 让用户填一个**视频页地址**，然后真的走一遍解析 —— 只测「接口通不通」
  /// 没意义，重要的是它到底能不能把地址换出来。
  Future<void> _test(ParseSource source) async {
    final url = await showDialog<String>(
      context: context,
      builder: (context) => const _TestUrlDialog(),
    );
    if (url == null || url.isEmpty) return;

    setState(() => _testing.add(source.key));
    final result = await StreamResolver.test(source, url);
    ParseSourceManager.noteResult(
      source.key,
      ok: result.ok,
      latencyMs: 0,
    );
    if (!mounted) return;
    setState(() {
      _testing.remove(source.key);
      _testLabels[source.key] = result.ok
          ? '成功 → ${result.url}'
          : result.message;
    });
    _reload();
  }

  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final enabledCount = _sources.where((s) => s.enabled).length;

    return SettingsDetailScaffold(
      title: const Text('解析源'),
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
              case 'import':
                _import();
              case 'export':
                _export();
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'import', child: Text('导入…')),
            PopupMenuItem(value: 'export', child: Text('导出到剪贴板')),
          ],
        ),
      ],
      body: SettingsList(
        sections: [
          SettingsSection(
            title: Text('${_sources.length} 个，$enabledCount 个启用'),
            bottomInfo: const Text(
              '解析源用于播放视频平台的页面（腾讯/爱奇艺/优酷等）。\n'
              '采集站自己的「云线路」不需要这里配置 —— 那是内置的网页解析，自动生效。\n'
              '本应用不提供任何解析接口，请自行填写并自行判断其可用性与合规性。',
              style: TextStyle(fontSize: 12),
            ),
            tiles: [
              if (_sources.isEmpty)
                const SettingsTile(
                  title: Text('还没有解析源'),
                  description: Text(
                    '点右上角「+」添加，或从 TVBOX 配置导入 parses 段。',
                  ),
                ),
              for (final source in _sources)
                _ParseSourceTile(
                  source: source,
                  testing: _testing.contains(source.key),
                  testLabel: _testLabels[source.key],
                  onToggle: (value) {
                    ParseSourceManager.setEnabled(source.key, value);
                    StreamResolver.clearCache();
                    _reload();
                  },
                  onTap: () => _edit(source),
                  onTest: () => _test(source),
                  onDelete: () => _remove(source),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ParseSourceTile extends StatelessWidget {
  const _ParseSourceTile({
    required this.source,
    required this.testing,
    required this.onToggle,
    required this.onTap,
    required this.onTest,
    required this.onDelete,
    this.testLabel,
  });

  final ParseSource source;
  final bool testing;
  final String? testLabel;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;
  final VoidCallback onTest;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final String status;
    if (testing) {
      status = '测试中…';
    } else if (testLabel != null) {
      status = testLabel!;
    } else if (source.lastLatencyMs == -1 && source.lastOkAt == 0) {
      status = '未测试';
    } else if (source.lastLatencyMs == -1) {
      status = '上次失败';
    } else {
      status = '上次成功';
    }

    return SettingsTile(
      title: Text(source.name),
      description: Text('${source.api}\n$status'),
      onPressed: (context) => onTap(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: '测试',
            onPressed: testing ? null : onTest,
            icon: testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.science_outlined, size: 20),
          ),
          Switch(value: source.enabled, onChanged: onToggle),
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

/// 让用户填一个视频页地址作为测试目标。
class _TestUrlDialog extends StatefulWidget {
  const _TestUrlDialog();

  @override
  State<_TestUrlDialog> createState() => _TestUrlDialogState();
}

class _TestUrlDialogState extends State<_TestUrlDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('测试解析源'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '填一个**视频播放页**的地址，会用它走一遍真实解析。',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: '视频页地址',
              hintText: 'https://v.qq.com/x/cover/....html',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final url = _text.text.trim();
            if (!url.startsWith('http')) {
              KazumiDialog.showToast(message: '请填入 http(s) 开头的地址');
              return;
            }
            Navigator.of(context).pop(url);
          },
          child: const Text('开始测试'),
        ),
      ],
    );
  }
}
