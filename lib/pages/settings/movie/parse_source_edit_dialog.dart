import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:perzutv/bean/dialog/dialog_helper.dart';
import 'package:perzutv/modules/movie/parse_source.dart';
import 'package:perzutv/request/core/dio_factory.dart';
import 'package:perzutv/services/movie/parse_source_manager.dart';

/// 新建 / 编辑解析源。
///
/// 返回 null 表示取消。[existing] 为 null 时是新建，key 交给
/// ParseSourceManager 生成。
Future<ParseSource?> showParseSourceEditDialog(
  BuildContext context, {
  ParseSource? existing,
}) {
  return showDialog<ParseSource>(
    context: context,
    builder: (context) => _EditDialog(existing: existing),
  );
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({this.existing});

  final ParseSource? existing;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _api;
  late final TextEditingController _referer;
  late bool _post;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _api = TextEditingController(text: widget.existing?.api ?? '');
    _referer = TextEditingController(text: widget.existing?.referer ?? '');
    _post = widget.existing?.post ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _api.dispose();
    _referer.dispose();
    super.dispose();
  }

  /// 实时预览拼出来的请求地址 —— 接口写法各家不同，让用户当场看到结果，
  /// 比事后调试强得多。
  String get _preview {
    final api = _api.text.trim();
    if (api.isEmpty) return '';
    final sample = 'https://v.qq.com/x/cover/xxx.html';
    return ParseSource(key: 'preview', name: 'preview', api: api)
        .buildRequestUrl(sample);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text(_isNew ? '添加解析源' : '编辑解析源'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：某某解析',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _api,
              keyboardType: TextInputType.url,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: '接口地址',
                hintText: 'https://example.com/jx?url=',
                helperText: '两种写法都支持：以 ?url= 结尾（接口会自己拼目标地址），'
                    '或用 {url} 占位符指定目标地址的位置',
                helperMaxLines: 3,
              ),
            ),
            if (_preview.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '实际请求会是：',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _preview,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextField(
              controller: _referer,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Referer（可选）',
                hintText: 'https://example.com',
                helperText: '有些接口会校验请求来源',
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _post,
              onChanged: (v) => setState(() => _post = v),
              title: const Text('用 POST 提交'),
              subtitle: const Text('少数接口要求 POST，目标地址放在表单字段 url 里'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = _name.text.trim();
            final api = _api.text.trim();
            if (name.isEmpty || api.isEmpty) {
              KazumiDialog.showToast(message: '名称和接口地址都不能为空');
              return;
            }
            final base = widget.existing ??
                const ParseSource(key: '', name: '', api: '');
            Navigator.of(context).pop(base.copyWith(
              name: name,
              api: api,
              referer: _referer.text.trim(),
              post: _post,
            ));
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 导入

Future<List<ParseSource>?> showParseSourceImportDialog(BuildContext context) {
  return showDialog<List<ParseSource>>(
    context: context,
    builder: (context) => const _ImportDialog(),
  );
}

class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _text = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  /// 订阅地址在**客户端**拉取，不走服务端 —— 因此不受 CORS 限制。
  Future<void> _loadFromUrl() async {
    final url = _text.text.trim();
    if (!url.startsWith('http')) {
      KazumiDialog.showToast(message: '请填入 http(s) 开头的订阅地址');
      return;
    }
    setState(() => _loading = true);
    try {
      final resp = await DioFactory.apiDio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      _finish(_ImportParser.parse(resp.data ?? '', 'sub'));
    } catch (e) {
      if (!mounted) return;
      KazumiDialog.showToast(message: '订阅拉取失败：${_short(e.toString())}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _parseFromText() {
    _finish(_ImportParser.parse(_text.text, 'pasted'));
  }

  void _finish(List<ParseSource> sources) {
    if (!mounted) return;
    if (sources.isEmpty) {
      KazumiDialog.showToast(
        message: '没解析出可用的解析源 —— 需要 name 和 url 两个字段',
      );
      return;
    }
    Navigator.of(context).pop(sources);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入解析源'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '粘贴 JSON，或填一个订阅地址。\n'
              '支持 TVBOX 配置里的 parses 段，以及 {"parses": [...]} 这种形式。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              maxLines: 6,
              minLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{"parses": [{"name": "...", "url": "..."}]}\n'
                    '或 https://example.com/config.json',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _loading
                      ? null
                      : () async {
                          final data =
                              await Clipboard.getData(Clipboard.kTextPlain);
                          final text = data?.text ?? '';
                          if (text.isEmpty) {
                            KazumiDialog.showToast(message: '剪贴板是空的');
                            return;
                          }
                          _text.text = text;
                        },
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('从剪贴板'),
                ),
                const Spacer(),
                if (_loading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: _loading ? null : _loadFromUrl,
          child: const Text('按订阅地址拉取'),
        ),
        FilledButton(
          onPressed: _loading ? null : _parseFromText,
          child: const Text('解析粘贴内容'),
        ),
      ],
    );
  }
}

/// 解析导入内容 —— TVBOX 配置和纯 parses 列表都试一遍。
class _ImportParser {
  static List<ParseSource> parse(String raw, String prefix) {
    final tvbox = ParseSourceManager.parseTvboxJson(raw, keyPrefix: '${prefix}_tv');
    if (tvbox.isNotEmpty) return tvbox;
    return ParseSourceManager.parseJson(raw, keyPrefix: prefix);
  }
}

String _short(String text) => text.length <= 60 ? text : '${text.substring(0, 60)}…';
