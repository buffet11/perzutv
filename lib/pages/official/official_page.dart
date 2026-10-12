import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:perzutv/bean/dialog/dialog_helper.dart';
import 'package:perzutv/services/official/bilibili_api.dart';
import 'package:perzutv/services/official/bilibili_target.dart';

/// 「正版番剧」入口页。
///
/// 只做一件事：把一段 B 站链接变成一次应用内播放。
///
/// 为什么不把 B 站塞进现有的采集源体系？因为两者根本不是一回事 ——
/// 采集源返回的是「给 mpv 播的流地址」，而这里是「给 WebView 加载的官方播放器页」。
/// 硬塞进同一个接口只会让两边都别扭，不如单开一条干净的路。
class OfficialPage extends StatefulWidget {
  const OfficialPage({super.key});

  @override
  State<OfficialPage> createState() => _OfficialPageState();
}

class _OfficialPageState extends State<OfficialPage> {
  final TextEditingController _inputController = TextEditingController();

  BiliTarget? _target;
  String? _hint;

  bool _loadingDetail = false;
  BiliSeason? _season;
  String? _resolvedTitle;

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  Future<void> _pasteFromClipboard() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty) {
        KazumiDialog.showToast(message: '剪贴板里没有文字');
        return;
      }
      _inputController.text = text;
      await _resolve();
    } catch (e) {
      KazumiDialog.showToast(message: '读取剪贴板失败：$e');
    }
  }

  Future<void> _resolve() async {
    final raw = _inputController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _target = null;
        _hint = '请先粘贴一个 B 站链接或编号';
      });
      return;
    }

    final target = BiliTarget.parse(raw);
    if (target == null) {
      setState(() {
        _target = null;
        _season = null;
        _resolvedTitle = null;
        _hint = '没认出来。支持的形态：番剧链接（…/bangumi/play/ep123456）、'
            '视频链接（BV 号）、或直接写 ep123456 / ss12345';
      });
      return;
    }

    setState(() {
      _target = target;
      _hint = null;
      _season = null;
      _resolvedTitle = null;
      _loadingDetail = !target.isEpisode && target.isSeason;
    });

    final seasonId = target.isSeason ? int.tryParse(target.id) : null;
    if (seasonId == null) {
      // UGC 视频：顺手取个标题，失败就不管（不影响播放）。
      if (target.type == BiliTargetType.videoBvid) {
        final title = await BilibiliApi.fetchVideoTitle(target.id);
        if (!mounted) return;
        setState(() => _resolvedTitle = title);
      }
      return;
    }

    final season = await BilibiliApi.fetchSeason(seasonId);
    if (!mounted) return;
    setState(() {
      _loadingDetail = false;
      _season = season;
      _resolvedTitle = season?.title;
      if (season == null) {
        _hint = '拿不到这一季的剧集列表（接口可能改版或需要登录）。\n'
            '可以直接粘贴**具体某一集**的链接（…/bangumi/play/ep123456）来播放。';
      }
    });
  }

  void _play(BiliTarget target, {String? title}) {
    // 注意：这个项目用的是 flutter_modular 7.x，顶层 `Modular` 类不在导出范围内，
    // 全项目统一走 `context.pushNamed` 这个扩展（见 anime_page / movie_page）。
    context.pushNamed(
      '/official/player',
      arguments: OfficialPlayerArgs(target: target, title: title),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('正版番剧')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _buildIntroCard(theme),
          const SizedBox(height: 16),
          _buildInputCard(theme),
          if (_hint != null) ...[
            const SizedBox(height: 12),
            _buildHint(theme, _hint!),
          ],
          if (_target != null) ...[
            const SizedBox(height: 12),
            _buildTargetCard(theme, _target!),
          ],
          if (_loadingDetail) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            Center(
              child: Text('正在取剧集列表…',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.outline)),
            ),
          ],
          if (_season != null) ...[
            const SizedBox(height: 20),
            _buildEpisodeGrid(theme, _season!),
          ],
        ],
      ),
    );
  }

  Widget _buildIntroCard(ThemeData theme) {
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.verified_rounded,
                    size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 6),
                Text('正版内容，官方播放器',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '这里加载的是 B 站官方外链播放器，解码和鉴权都在 B 站那边完成 —— '
              '所以既不消耗本机显卡（超分辨率那套滤镜完全用不上），'
              '也不涉及解析视频流。\n\n'
              '代价是：需要登录或会员的内容，得用系统浏览器打开并登录后才能看。',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputCard(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _inputController,
          minLines: 1,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: 'B 站链接或编号',
            hintText: '例：https://www.bilibili.com/bangumi/play/ep282316',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              tooltip: '从剪贴板粘贴',
              onPressed: _pasteFromClipboard,
              icon: const Icon(Icons.content_paste_rounded),
            ),
          ),
          onSubmitted: (_) => _resolve(),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _resolve,
              icon: const Icon(Icons.search_rounded),
              label: const Text('识别'),
            ),
            const SizedBox(width: 10),
            TextButton(
              onPressed: () {
                _inputController.clear();
                setState(() {
                  _target = null;
                  _season = null;
                  _resolvedTitle = null;
                  _hint = null;
                });
              },
              child: const Text('清空'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildHint(ThemeData theme, String hint) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(hint, style: theme.textTheme.bodySmall?.copyWith(height: 1.5)),
    );
  }

  Widget _buildTargetCard(ThemeData theme, BiliTarget target) {
    final canPlayDirectly = !target.isSeason || _season != null;
    return Card(
      elevation: 0,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  label: Text(target.type.label),
                  visualDensity: VisualDensity.compact,
                  side: BorderSide.none,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _resolvedTitle?.isNotEmpty == true
                        ? _resolvedTitle!
                        : target.id,
                    style: theme.textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: canPlayDirectly
                      ? () => _play(
                            target.isSeason && _season != null
                                ? BiliTarget(
                                    type: BiliTargetType.episode,
                                    id: '${_season!.episodes.first.epId}',
                                    raw: target.raw,
                                  )
                                : target,
                            title: _resolvedTitle,
                          )
                      : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text(
                    target.isSeason && _season != null ? '从第 1 集开始' : '开始播放',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodeGrid(ThemeData theme, BiliSeason season) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '共 ${season.episodes.length} 集',
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final episode in season.episodes)
              ActionChip(
                label: Text(
                  episode.title.isEmpty ? '${episode.epId}' : episode.title,
                  style: const TextStyle(fontSize: 12),
                ),
                tooltip: episode.displayTitle,
                onPressed: () => _play(
                  BiliTarget(
                    type: BiliTargetType.episode,
                    id: '${episode.epId}',
                    raw: season.title,
                  ),
                  title: season.title.isEmpty
                      ? episode.displayTitle
                      : '${season.title} · ${episode.displayTitle}',
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          '提示：点集数即可播放。若提示需要登录/会员，右上角可用系统浏览器打开。',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.outline,
            height: 1.5,
          ),
        ),
      ],
    );
  }
}
