import 'package:flutter_modular/flutter_modular.dart';
import 'package:perzutv/pages/official/bilibili_player_page.dart';
import 'package:perzutv/pages/official/official_page.dart';
import 'package:perzutv/pages/route_error_page.dart';
import 'package:perzutv/services/official/bilibili_target.dart';

/// 「正版番剧」模块，挂在**根**路由上（`/official`），与 `/movie-detail` 同理：
/// 铺满全屏、盖住底部导航，返回时回到原来的 Tab。
///
/// 放在 Tab 内部的话，返回栈会和底部导航的 PopScope 逻辑纠缠在一起
/// （`_handleSystemBack` 只判断 `_selectedIndex != 0`）。
final officialModule = createModule(
  path: '/official',
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => const OfficialPage(),
      )
      ..route(
        '/player',
        child: (context, state) {
          final args = state.arguments;
          if (args is! OfficialPlayerArgs) {
            return const RouteErrorPage(message: '播放参数无效，请返回后重试。');
          }
          return BilibiliPlayerPage(target: args.target, title: args.title);
        },
      );
  },
);
