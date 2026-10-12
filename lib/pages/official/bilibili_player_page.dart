import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:perzutv/bean/dialog/dialog_helper.dart';
import 'package:perzutv/services/logging/logger.dart';
import 'package:perzutv/services/official/bilibili_target.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_windows/webview_windows.dart';

/// 应用内播放 B 站官方外链播放器。
///
/// 这里**刻意不解析视频流**：页面就是官方的播放器，解码与鉴权都在 B 站侧完成。
/// 这样既避开了「提取 m3u8 绕过正版保护」的合规问题，也顺带绕开了本地解码的
/// 性能开销 —— 核显机器上这一点比什么都重要。
///
/// 仅 Windows 走 WebView2；其它平台给出明确提示并退回系统浏览器。
class BilibiliPlayerPage extends StatefulWidget {
  const BilibiliPlayerPage({super.key, required this.target, this.title});

  final BiliTarget target;
  final String? title;

  @override
  State<BilibiliPlayerPage> createState() => _BilibiliPlayerPageState();
}

class _BilibiliPlayerPageState extends State<BilibiliPlayerPage> {
  WebviewController? _controller;
  StreamSubscription<WebErrorStatus>? _errorSubscription;
  StreamSubscription<LoadingState>? _loadingSubscription;

  bool _initializing = true;
  bool _loading = true;
  String? _errorMessage;

  String get _displayTitle {
    final title = widget.title?.trim();
    if (title != null && title.isNotEmpty) {
      return title;
    }
    return '${widget.target.type.label}：${widget.target.id}';
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      unawaited(_bootstrap());
    } else {
      _initializing = false;
      _loading = false;
      _errorMessage = '当前平台暂未接入应用内播放器';
    }
  }

  @override
  void dispose() {
    _errorSubscription?.cancel();
    _loadingSubscription?.cancel();
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      // 释放是异步的，但页面已经在销毁路径上，不能 await。
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final controller = WebviewController();
    try {
      await controller.initialize();
      await controller.setBackgroundColor(const Color(0xFF000000));
      // 站内跳转可能弹新窗口；直接拒绝，避免用户掉进一个没有地址栏的窗口。
      await controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);

      _errorSubscription = controller.onLoadError.listen((status) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _errorMessage = '页面加载失败：$status';
        });
      });
      _loadingSubscription = controller.loadingState.listen((state) {
        if (!mounted) return;
        setState(() => _loading = state == LoadingState.loading);
      });

      await controller.loadUrl(widget.target.playerUrl);
      if (!mounted) {
        unawaited(controller.dispose());
        return;
      }
      setState(() {
        _controller = controller;
        _initializing = false;
      });
    } catch (e) {
      KazumiLogger().e('BilibiliPlayer: 初始化失败', error: e);
      try {
        await controller.dispose();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _loading = false;
        _errorMessage = '播放器初始化失败：$e';
      });
    }
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.target.playerUrl);
    if (uri == null) return;
    try {
      // 这里刻意用外部浏览器打开 player.html 而不是原始链接：
      // 用户要的是"能看"，官方播放器页在任何浏览器里都能跑。
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        KazumiDialog.showToast(message: '无法打开系统浏览器');
      }
    } catch (e) {
      if (mounted) {
        KazumiDialog.showToast(message: '打开浏览器失败：$e');
      }
    }
  }

  Future<void> _reload() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      await controller.loadUrl(widget.target.playerUrl);
      if (mounted) {
        setState(() {
          _loading = true;
          _errorMessage = null;
        });
      }
    } catch (e) {
      KazumiLogger().w('BilibiliPlayer: 重新加载失败', error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_displayTitle, overflow: TextOverflow.ellipsis),
        actions: [
          if (_controller != null)
            IconButton(
              tooltip: '重新加载',
              onPressed: _reload,
              icon: const Icon(Icons.refresh_rounded),
            ),
          IconButton(
            tooltip: '用系统浏览器打开',
            onPressed: _openInBrowser,
            icon: const Icon(Icons.open_in_browser_rounded),
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_errorMessage != null) {
      return _buildError(context, _errorMessage!);
    }
    if (_initializing) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在启动播放器…', style: TextStyle(color: Colors.white70)),
          ],
        ),
      );
    }

    final controller = _controller;
    if (controller == null) {
      return _buildError(context, '播放器未能创建');
    }

    return Stack(
      children: [
        Positioned.fill(child: Webview(controller)),
        if (_loading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),
      ],
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 44, color: Colors.white54),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            const Text(
              '正版内容需要登录或会员时，请用系统浏览器打开并登录后观看。',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('用系统浏览器打开'),
            ),
          ],
        ),
      ),
    );
  }
}
