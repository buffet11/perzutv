import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:perzutv/bean/dialog/dialog_helper.dart';
import 'package:perzutv/pages/my/my_controller.dart';
import 'package:perzutv/services/storage/storage.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:perzutv/services/shaders/shader_asset_service.dart';
import 'package:perzutv/services/platform/windows_shortcut.dart';
import 'package:perzutv/services/platform/platform_environment_service.dart';
import 'package:perzutv/services/update/startup_update_check.dart';
import 'package:perzutv/navigation.dart';
import 'package:perzutv/utils/startup_page.dart';

/// 启动页：做完全部初始化后跳到默认启动页。
///
/// ⚠️ 番剧功能已整体移除，原先的「规则插件初始化 / 首次启动引导安装规则 /
/// 追番数据迁移 / WebDAV 番剧同步 / Bangumi 同步 / 离线下载初始化」都已删掉。
/// 现在这里只保留与影视 + 动漫模块真正相关的启动动作：
/// 超分着色器落盘、弹幕屏蔽词装载、桌面快捷方式询问、自动更新检查、跳默认页。
class InitPage extends StatefulWidget {
  const InitPage({
    super.key,
    required this.shaderAssetService,
    required this.myController,
  });

  final ShaderAssetService shaderAssetService;
  final MyController myController;

  @override
  State<InitPage> createState() => _InitPageState();
}

class _InitPageState extends State<InitPage> {
  MyController get myController => widget.myController;

  @override
  void initState() {
    super.initState();
    unawaited(_initializeApp());
  }

  Future<void> _initializeApp() async {
    _loadShaders();
    unawaited(myController.loadShieldList());

    await _checkRunningOnX11();
    await _showShortcutDialog();

    if (!mounted) {
      return;
    }
    // 首次启动必须先过引导页（使用约定 / 免责声明）。
    if (!GStorage.getSetting(SettingsKeys.onboardingCompleted)) {
      context.navigate('/onboarding');
      return;
    }
    final updateController = myController;
    unawaited(runStartupUpdateCheck(
      isEnabled: () => GStorage.getSetting(SettingsKeys.autoUpdate),
      checkForUpdate: () async {
        await updateController.checkUpdate(type: 'auto');
      },
    ));
    _startDefaultPage();
  }

  void _startDefaultPage() {
    // 过滤掉已失效的启动页（番剧 Tab 已删除，旧设置可能残留）
    final defaultStartupPage = StartupPage.resolve(
        GStorage.getSetting(SettingsKeys.defaultStartupPage));
    if (!mounted) {
      return;
    }
    context.navigate(defaultStartupPage);
  }

  Future<void> _loadShaders() async {
    await widget.shaderAssetService.copyShadersToExternalDirectory();
  }

  Future<void> _checkRunningOnX11() async {
    if (!Platform.isLinux) {
      return;
    }
    bool isRunningOnX11 = await PlatformEnvironmentService.isRunningOnX11();
    if (isRunningOnX11) {
      await KazumiDialog.show(
        clickMaskDismiss: false,
        builder: (context) {
          return PopScope(
            canPop: false,
            child: AlertDialog(
              title: const Text('X11环境检测'),
              content: const Text(
                  '检测到您当前运行在X11环境下，Perzutv在X11环境下可能出现性能问题或界面异常，建议切换到Wayland以获得更好的体验。您是否希望在X11下继续使用Perzutv？'),
              actions: [
                TextButton(
                  onPressed: () {
                    exit(0);
                  },
                  child: Text(
                    '退出',
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.outline),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    KazumiDialog.dismiss();
                  },
                  child: const Text('继续'),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Future<void> _showShortcutDialog() async {
    if (!Platform.isWindows) return;
    if (GStorage.getSetting(SettingsKeys.shortcutDialogShown)) {
      return;
    }

    final create = await KazumiDialog.show<bool>(
      clickMaskDismiss: false,
      builder: (context) => AlertDialog(
        title: const Text('创建桌面快捷方式'),
        content: const Text('是否在桌面创建 Perzutv 的快捷方式？'),
        actions: [
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: false),
            child: Text('暂不创建',
                style: TextStyle(color: Theme.of(context).colorScheme.outline)),
          ),
          TextButton(
            onPressed: () => KazumiDialog.dismiss(popWith: true),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    await GStorage.putSetting(SettingsKeys.shortcutDialogShown, true);
    if (create ?? false) {
      final success = await WindowsShortcut.createDesktopShortcut();
      KazumiDialog.showToast(message: success ? '桌面快捷方式已创建' : '桌面快捷方式创建失败');
    }
  }

  @override
  Widget build(BuildContext context) {
    return const LoadingWidget();
  }
}

class LoadingWidget extends StatelessWidget {
  const LoadingWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: Container());
  }
}
