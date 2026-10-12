/// 「启动界面」的可选页与容错。
///
/// 为什么需要单独一个 util：番剧相关 Tab（推荐 / 时间表 / 追番）被整体删除后，
/// 设置里可能仍存着 `/tab/popular/` 这类**已失效路径**。直接拿去 navigate 会
/// 落到「无法打开页面」错误页 —— 而且是在启动瞬间，用户完全不知道发生了什么。
/// 所以所有读 `defaultStartupPage` 的地方都必须过一遍 [resolve]。
class StartupPage {
  StartupPage._();

  /// 展示名 → 路径。顺序即设置页菜单里的顺序。
  static const Map<String, String> labels = {
    '/tab/anime/': '动漫',
    '/tab/movie/': '影视',
    '/tab/my/': '我的',
  };

  /// 兜底启动页（动漫是本应用的主入口）。
  static const fallback = '/tab/anime/';

  /// 把存储里的值收敛到合法启动页；非法（或空）一律回落 [fallback]。
  static String resolve(Object? raw) {
    final path = raw is String ? raw : '';
    return labels.containsKey(path) ? path : fallback;
  }
}
