import 'package:perzutv/services/storage/storage.dart';
import 'package:perzutv/utils/bangumi_mirror_credentials.dart';

enum BangumiAcceleration {
  direct,
  ech,
  mirror;

  /// 用户**选择**的模式（原样读设置）。
  static BangumiAcceleration get requested => switch (GStorage.getSetting(
    SettingsKeys.bangumiAcceleration,
  )) {
    'direct' => direct,
    'ech' => ech,
    'mirror' => mirror,
    _ => GStorage.getSetting(SettingsKeys.enableBangumiProxy) ? mirror : direct,
  };

  /// 不考虑自愈覆盖时的**有效**模式。
  ///
  /// ⚠️ 镜像不能用于「没有签名凭据」的构建：搜索与评论要求 `X-Signature`，
  /// 而签名密钥来自上游 CI（本地构建是空串），一到签名那关就 401。
  /// 这种情况**整体升级**到 ECH。
  ///
  /// 为什么必须整体升级、而不是只在传输层把签名请求绕开：镜像还有自己的缓存
  /// 端点（`/kazumi/v1/popular/subjects`、`/kazumi/v1/calendar/season`，
  /// 见 popular / timeline 控制器按 `current == mirror` 选路）。那些路径**只存在于
  /// 镜像域名上** —— 只换传输不改路径，就会拿着 `/kazumi/v1/*` 去求官方域名，得到 404。
  ///
  /// 为什么是 ECH 而不是直连：ECH 本就是为「直连不通」的网络准备的。
  /// 实测中直连 api.bgm.tv 会长时间转圈最终失败，而 ECH 可通。
  static BangumiAcceleration get effective =>
      requested == mirror && !hasMirrorCredentials ? ech : requested;

  /// 自愈/探测期间临时覆盖的模式（**仅内存，不写设置**）。
  ///
  /// 为什么不直接改设置：探测是"试试看"，试错过程不该反复落盘，更不该在中途
  /// 把用户原本的选择改坏 —— 只有确认能通的那一个才会写回去。
  static BangumiAcceleration? _override;

  /// **实际使用**的模式（见 [effective] 与 [_override]）。
  static BangumiAcceleration get current => _override ?? effective;

  /// 在指定模式下执行一段代码。自愈探测用。
  static Future<T> withMode<T>(
    BangumiAcceleration mode,
    Future<T> Function() body,
  ) async {
    final previous = _override;
    _override = mode;
    try {
      return await body();
    } finally {
      _override = previous;
    }
  }

  /// 自愈时的候选顺序。
  ///
  /// ECH 优先：它本就是为「直连不通」的网络准备的，实测在直连长时间超时的
  /// 环境下可用。镜像垫底，而且只在有签名凭据时才算候选（见
  /// [hasMirrorCredentials]）。
  static List<BangumiAcceleration> get candidates => [
    for (final mode in const [ech, direct, mirror])
      if (mode.usable) mode,
  ];

  /// 镜像的「受保护请求」是否可用。
  ///
  /// 镜像对一部分请求要求 `X-Signature`，而签名密钥（`KAZUMI_APPID` /
  /// `KAZUMI_KEY`）是**上游 CI 从 GitHub Secrets 注入的**，源码里是空串。
  /// 于是任何本地编译 / 三分支构建都签不出有效签名，这类请求打到镜像只会拿到
  /// `401 invalid request signature` —— 而异常在调用处被 try/catch 吞掉，
  /// 表现成「搜索没有找到番剧」这种极难定位的现象。
  ///
  /// 所以没有凭据时必须承认镜像用不了，让这类请求绕开镜像。
  static bool get hasMirrorCredentials {
    final id = bangumiMirrorCredentials['id'] ?? '';
    final key = bangumiMirrorCredentials['value'] ?? '';
    return id.isNotEmpty && key.isNotEmpty;
  }

  /// 镜像要求签名的请求：搜索（POST）与三类评论（GET `/p1/*/comments`）。
  ///
  /// 判定集中放在这里，因为有两个地方要用它：拦截器（决定是否改写到镜像）
  /// 与 `bangumi_client`（决定是否加签名头）。分散成两份一定会漂移。
  static bool needsMirrorSignature(String method, String path) {
    if (method == 'POST' && path == '/v0/search/subjects') return true;
    if (method != 'GET') return false;
    final isComments = path.endsWith('/comments');
    return isComments &&
        (path.startsWith('/p1/subjects/') ||
            path.startsWith('/p1/episodes/') ||
            path.startsWith('/p1/characters/'));
  }

  /// 这个模式是否真的可用（镜像无凭据时不算可用）
  bool get usable => this != mirror || hasMirrorCredentials;

  String get label => switch (this) {
    direct => '直连',
    ech => 'ECH',
    mirror => '镜像',
  };
}
