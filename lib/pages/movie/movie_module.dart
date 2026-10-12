import 'package:flutter_modular/flutter_modular.dart';
import 'package:perzutv/modules/movie/movie_item.dart';
import 'package:perzutv/pages/movie/movie_controller.dart';
import 'package:perzutv/pages/movie/movie_detail_page.dart';
import 'package:perzutv/pages/movie/movie_page.dart';
import 'package:perzutv/pages/route_error_page.dart';

/// 影视 Tab，挂在 `/tab` 下 → 完整路径 `/tab/movie`。
///
/// [MovieController] 在这里注册（和 `tabModule` 注册 `PopularController` 同一套路），
/// Tab 状态在切换 Tab 之间保留。
final movieModule = createModule(
  path: '/movie',
  register: (c) {
    c
      ..addSingleton<MovieController>(MovieController.new)
      ..route(
        '/',
        transition: TransitionType.none,
        child: (context, state) => MoviePage(
          controller: inject<MovieController>(),
        ),
      );
  },
);

/// 详情页，挂在**根**上（`/movie-detail`）而不是 Tab 内。
///
/// 跟 `/info/` 一致：详情页铺满全屏、盖住底部导航，返回时回到原来的 Tab。
/// 放在 Tab 内部的话，返回栈和底部导航的 PopScope 逻辑会纠缠在一起
/// （`_handleSystemBack` 只判断 `_selectedIndex != 0`）。
final movieDetailModule = createModule(
  path: '/movie-detail',
  register: (c) {
    c.route(
      '/',
      child: (context, state) {
        final item = state.arguments;
        if (item is! MovieSearchItem) {
          return const RouteErrorPage(message: '影视详情参数无效，请返回后重试。');
        }
        return MovieDetailPage(item: item);
      },
    );
  },
);
