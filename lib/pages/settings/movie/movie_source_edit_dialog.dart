import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:perzutv/bean/dialog/dialog_helper.dart';
import 'package:perzutv/modules/movie/movie_source.dart';
import 'package:perzutv/request/core/dio_factory.dart';
import 'package:perzutv/services/movie/movie_source_manager.dart';

/// 新建 / 编辑影视源。
///
/// 返回 null 表示取消；返回 [MovieSource] 表示确认。
/// 新建时 [existing] 为 null，key 交给 MovieSourceManager 生成。
Future<MovieSource?> showMovieSourceEditDialog(
  BuildContext context, {
  MovieSource? existing,
}) {
  return showDialog<MovieSource>(
    context: context,
    builder: (context) => _EditDialog(existing: existing),
  );
}

class _EditDialog extends StatefulWidget {
  const _EditDialog({this.existing});

  final MovieSource? existing;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _name;
  late final TextEditingController _api;
  late final TextEditingController _detail;
  late bool _isAdult;

  bool get _isNew => widget.existing == null;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.existing?.name ?? '');
    _api = TextEditingController(text: widget.existing?.api ?? '');
    _detail = TextEditingController(text: widget.existing?.detail ?? '');
    _isAdult = widget.existing?.isAdult ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _api.dispose();
    _detail.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? '添加影视源' : '编辑影视源'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '名称',
                hintText: '例如：某某资源站',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _api,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '接口地址',
                hintText: 'https://example.com/api.php/provide/vod',
                helperText: '苹果CMS 采集接口。只填域名也可以，会自动补全路径',
                helperMaxLines: 2,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _detail,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: '详情地址（可选）',
                hintText: 'https://example.com',
                helperText: '部分源校验 Referer，填了更稳',
              ),
            ),
            const SizedBox(height: 4),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isAdult,
              onChanged: (v) => setState(() => _isAdult = v),
              title: const Text('标记为成人内容'),
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
                MovieSource(key: '', name: '', api: '');
            Navigator.of(context).pop(base.copyWith(
              name: name,
              api: api,
              detail: _detail.text.trim(),
              isAdult: _isAdult,
            ));
          },
          child: const Text('确定'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- 导入

/// 导入方式：[ImportPayload] 携带解析结果。
class ImportPayload {
  final List<MovieSource> sources;

  /// 来自 URL 订阅时为该地址，用户可保存为订阅
  final String fromUrl;

  const ImportPayload({required this.sources, this.fromUrl = ''});
}

Future<ImportPayload?> showMovieSourceImportDialog(BuildContext context) {
  return showDialog<ImportPayload>(
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

  /// URL 订阅在**客户端**拉取解析，不走服务端 —— 因此不受 CORS 限制。
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
      final sources = MovieSourceManager.parseAnyJson(
        resp.data ?? '',
        keyPrefix: 'sub',
      );
      if (!mounted) return;
      if (sources.isEmpty) {
        KazumiDialog.showToast(message: '订阅内容里没解析出可用的源');
        return;
      }
      Navigator.of(context).pop(
        ImportPayload(sources: sources, fromUrl: url),
      );
    } catch (e) {
      if (!mounted) return;
      KazumiDialog.showToast(message: '订阅拉取失败：${_short(e.toString())}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _parseFromText() {
    final sources = MovieSourceManager.parseAnyJson(
      _text.text,
      keyPrefix: 'pasted',
    );
    if (sources.isEmpty) {
      KazumiDialog.showToast(message: '没解析出可用的源，检查一下 JSON 格式');
      return;
    }
    Navigator.of(context).pop(ImportPayload(sources: sources));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入影视源'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '粘贴 JSON，或填一个订阅地址。\n'
              '支持 LibreTV 源列表与 TVBOX 配置（只取 type=1 的 CMS 源）。',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _text,
              maxLines: 6,
              minLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: '{"sources": [ ... ]}\n或 https://example.com/sources.json',
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

String _short(String text) => text.length <= 60 ? text : '${text.substring(0, 60)}…';
