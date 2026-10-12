import 'package:flutter_modular/flutter_modular.dart';
import 'package:perzutv/pages/anime/anime_controller.dart';
import 'package:perzutv/pages/anime/anime_page.dart';

/// 「动漫」Tab，挂在 `/tab` 下 → 完整路径 `/tab/anime`。
///
/// [AnimeController] 在模块里注册成单例（和 `movieModule` 注册 `MovieController`
/// 同一套路，不用 MobX 的 `Bind.singleton`，避免 codegen 依赖），
/// Tab 状态在切换 Tab 之间保留。
final animeModule = createModule(
  path: '/anime',
  register: (c) {
    c
      ..addSingleton<AnimeController>(AnimeController.new)
      ..route(
        '/',
        transition: TransitionType.none,
        child: (context, state) => AnimePage(
          controller: inject<AnimeController>(),
        ),
      );
  },
);
