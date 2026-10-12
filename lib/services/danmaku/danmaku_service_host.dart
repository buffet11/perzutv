import 'dart:async';
import 'dart:io';

import 'package:perzutv/services/logging/logger.dart';
import 'package:perzutv/services/storage/storage.dart';

/// 内置弹幕服务宿主（Windows 桌面端专用）。
///
/// 以 detached 子进程方式拉起 danmu_api（弹弹play 兼容协议、免签名的弹幕
/// 聚合服务，Node.js 实现）：
/// - App 启动时若开关开启：先健康检查端口，已在跑（如上次退出残留/用户手动开）
///   则直接复用，否则拉起新进程。
/// - App 正常退出时：只杀掉本次会话自己拉起的进程；崩溃残留的实例留给下次复用。
/// - Node 解析顺序：部署目录内置 `runtime/node.exe`（绿色版零依赖）→ PATH 里的 node。
/// - 服务不可用（缺 Node / 目录不存在）时静默降级 + 一次性弹窗引导，弹幕走原有
///   官方/自定义链路。
class DanmakuServiceHost {
  DanmakuServiceHost._();

  static final DanmakuServiceHost instance = DanmakuServiceHost._();

  static const host = '127.0.0.1';
  static const port = 9321;
  static const token = '87654321';

  /// 填进 Perzutv「自定义弹幕 API」同款链路的本机服务地址。
  static const baseUrl = 'http://$host:$port/$token';

  Process? _spawnedProcess;
  bool _checkedThisSession = false;

  /// 开关是否打开（仅 Windows 桌面有意义）。
  bool get isEnabled =>
      Platform.isWindows &&
      GStorage.getSetting(SettingsKeys.danmakuEmbeddedService);

  /// 本次会话是否已确认服务可用（避免每次弹幕请求都做健康检查）。
  bool get isConfirmedAlive => _checkedThisSession;

  /// App 启动时的预热入口：fire-and-forget，不阻塞主流程。
  void warmup() {
    if (!isEnabled) return;
    unawaited(ensureStarted());
  }

  /// 确保服务在线。返回 false = 本次未能提供本机服务（调用方自行降级）。
  Future<bool> ensureStarted() async {
    if (!isEnabled) return false;
    if (_checkedThisSession) return true;
    if (await isAlive()) {
      KazumiLogger().i('DanmakuService: local service already running, reuse it');
      _checkedThisSession = true;
      return true;
    }
    final dir = resolveServiceDir();
    if (dir == null) {
      KazumiLogger().w(
          'DanmakuService: service directory not found (danmu_api/server.js)');
      _notifyUnavailable('未找到内置弹幕服务目录（danmu-api），弹幕将走备用源');
      return false;
    }
    final node = resolveNodeExecutable(dir);
    if (node == null) {
      KazumiLogger().w(
          'DanmakuService: no Node.js available (neither bundled runtime/node.exe nor PATH)');
      _notifyUnavailable('缺少 Node.js 运行时，内置弹幕服务无法启动');
      return false;
    }
    try {
      // detached：App 崩溃时服务不陪葬；正常退出时由 shutdown() 显式回收。
      _spawnedProcess = await Process.start(
        node,
        ['danmu_api/server.js'],
        workingDirectory: dir,
        environment: {
          ...Platform.environment,
          'PORT': '$port',
          'TOKEN': token,
        },
        mode: ProcessStartMode.detached,
      );
      KazumiLogger().i(
          'DanmakuService: spawned $node (pid ${_spawnedProcess!.pid}) in $dir');
    } catch (e) {
      KazumiLogger().w('DanmakuService: failed to spawn node',
          error: e);
      _notifyUnavailable('内置弹幕服务启动失败（Node.js 异常）');
      return false;
    }
    // 服务启动需要几秒，轮询端口直至就绪。
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      if (await isAlive()) {
        _checkedThisSession = true;
        KazumiLogger().i('DanmakuService: local service ready at $baseUrl');
        return true;
      }
    }
    KazumiLogger().w('DanmakuService: service did not become ready in time');
    return false;
  }

  /// 关闭本次会话拉起的服务进程（App 退出 / 关闭开关时调用）。
  void shutdown() {
    final process = _spawnedProcess;
    _spawnedProcess = null;
    _checkedThisSession = false;
    if (process == null) return;
    KazumiLogger().i('DanmakuService: stopping local service');
    process.kill();
  }

  /// 定位 danmu_api 部署目录（含 package.json 与 danmu_api/server.js）。
  /// 优先级：exe 同级 `danmu-api` → 从 exe 目录逐级向上找 `tools/danmu-api`
  /// （开发构建天然命中仓库部署；打包后放 exe 旁即可）。
  static String? resolveServiceDir() {
    bool isServiceDir(String dir) =>
        File('$dir/danmu_api/server.js').existsSync() &&
        File('$dir/package.json').existsSync();

    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final sibling = '$exeDir/danmu-api';
    if (isServiceDir(sibling)) return sibling;

    var current = Directory(exeDir);
    for (var depth = 0; depth < 6; depth++) {
      final candidate = '${current.path}/tools/danmu-api';
      if (isServiceDir(candidate)) return candidate;
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
    return null;
  }

  /// 解析 Node 可执行文件：内置绿色版优先（`<服务目录>/runtime/node.exe`，
  /// 绿色版分发零依赖），否则交给 PATH 里的 `node`。
  static String? resolveNodeExecutable(String serviceDir) {
    final bundled = '$serviceDir/runtime/node.exe';
    if (File(bundled).existsSync()) return bundled;
    // PATH 查找：放 Process.start 让系统解析；找不到会在 spawn 时抛异常，
    // 这里先用 where 探测一次以区分「缺 Node」和「启动失败」。
    try {
      final result = Process.runSync('where', ['node.exe']);
      if (result.exitCode == 0) return 'node';
    } catch (_) {}
    return null;
  }

  /// 环境缺失时的一次性用户提示（去重：每次 App 会话最多弹一次）。
  static bool _notifiedUnavailable = false;
  static void Function(String message)? onUnavailable;

  static void _notifyUnavailable(String message) {
    if (_notifiedUnavailable) return;
    _notifiedUnavailable = true;
    onUnavailable?.call(message);
  }

  /// 健康检查：GET / 返回 200 即认为服务在线（短超时，不打网络）。
  static Future<bool> isAlive() async {
    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final request = await client
          .getUrl(Uri.parse('http://$host:$port/'))
          .timeout(const Duration(seconds: 2));
      final response = await request.close().timeout(const Duration(seconds: 2));
      await response.drain<void>().timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client?.close(force: true);
    }
  }
}
