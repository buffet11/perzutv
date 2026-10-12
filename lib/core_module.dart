import 'package:flutter_modular/flutter_modular.dart';
import 'package:perzutv/pages/download/download_controller.dart';
import 'package:perzutv/pages/history/history_controller.dart';
import 'package:perzutv/pages/my/my_controller.dart';
import 'package:perzutv/plugins/plugins_controller.dart';
import 'package:perzutv/repositories/danmaku_shield_repository.dart';
import 'package:perzutv/repositories/download_repository.dart';
import 'package:perzutv/repositories/history_repository.dart';
import 'package:perzutv/services/download/download_manager.dart';
import 'package:perzutv/services/player/audio_controller.dart';
import 'package:perzutv/services/shaders/shader_asset_service.dart';
import 'package:perzutv/services/sync/webdav.dart';

/// Root-owned application data and cross-feature coordinators.
///
/// This module intentionally has no path, so its registrations live for the
/// whole application. Page and feature-local state belongs in route `provide`
/// callbacks or path-bearing modules instead.
///
/// ⚠️ 番剧功能已移除：追番（Collect*）相关仓库、规则同步、番剧历史同步、
/// 番剧历史回放（HistoryPlaybackService）等注册都已删掉。
/// 保留的三类都是**影视 / 动漫 / 播放器仍在用**的：
///   - HistoryController / DownloadController：播放器记录进度、缓存弹幕
///   - WebDav：自动同步观看历史（弹幕屏蔽词同步的传输层）
///   - PluginsController：播放器要按名字回查 Plugin 对象（影视播放用占位对象）
final coreModule = createModule(
  register: (c) {
    c
      // Repository layer.
      ..addSingleton<IHistoryRepository>(HistoryRepository.new)
      ..addSingleton<IDownloadRepository>(DownloadRepository.new)
      ..addSingleton<IDanmakuShieldRepository>(DanmakuShieldRepository.new)
      // Service layer.
      ..addSingleton<IDownloadManager>(DownloadManager.new)
      ..addSingleton<AudioController>(AudioController.new)
      ..addSingleton<ShaderAssetService>(ShaderAssetService.new)
      ..addSingleton<WebDav>(WebDav.new)
      // Cross-feature state and coordinators.
      ..addSingleton<PluginsController>(PluginsController.new)
      ..addSingleton<HistoryController>(HistoryController.new)
      ..addSingleton<MyController>(MyController.new)
      ..addSingleton<DownloadController>(DownloadController.new);
  },
);
