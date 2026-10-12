import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';
import 'package:perzutv/bean/widget/error_widget.dart';
import 'package:perzutv/bean/widget/image_preview.dart';
import 'package:perzutv/pages/anime/anime_module.dart';
import 'package:perzutv/pages/index_page.dart';
import 'package:perzutv/pages/init_page.dart';
import 'package:perzutv/pages/movie/movie_module.dart';
import 'package:perzutv/pages/my/my_module.dart';
import 'package:perzutv/pages/official/official_module.dart';
import 'package:perzutv/pages/onboarding/onboarding_page.dart';
import 'package:perzutv/pages/route_error_page.dart';
import 'package:perzutv/pages/settings/settings_module.dart';
import 'package:perzutv/pages/video/video_module.dart';
import 'package:perzutv/services/storage/storage.dart';
import 'package:perzutv/pages/my/my_controller.dart';
import 'package:perzutv/services/shaders/shader_asset_service.dart';
import 'package:perzutv/utils/startup_page.dart';

final _tabTransition = CustomTransition(
  duration: const Duration(milliseconds: 70),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return FadeTransition(opacity: animation, child: child);
  },
);

final _imagePreviewTransition = CustomTransition(
  duration: const Duration(milliseconds: 220),
  transitionsBuilder: (context, animation, secondaryAnimation, child) {
    return FadeTransition(opacity: animation, child: child);
  },
);

final tabModule = createModule(
  path: '/tab',
  register: (c) {
    c
      // Tab state survives tab switches, but is released with the whole shell.
      //
      // 番剧相关的 PopularController / TimelineController 已随功能移除，
      // 剩下的三个 Tab 只有动漫一个需要常驻控制器（在 animeModule 里注册）。
      ..route(
        '/',
        child: (context, state) => IndexPage(location: state.uri.path),
        transition: _tabTransition,
        children: (sub) {
          sub
            ..route(
              '/',
              guards: [
                // 存储里的启动页可能已被删除（番剧 Tab 没了），必须过滤
                (state) => StartupPage.resolve(
                    GStorage.getSetting(SettingsKeys.defaultStartupPage)),
              ],
              child: (context, state) => const SizedBox.shrink(),
            )
            ..module(animeModule)
            ..module(movieModule)
            ..module(myModule);
        },
      );
  },
);

final indexModule = createModule(
  register: (c) {
    c
      ..route(
        '/',
        child: (context, state) => InitPage(
          shaderAssetService: inject<ShaderAssetService>(),
          myController: inject<MyController>(),
        ),
        transition: TransitionType.none,
      )
      ..route(
        '/onboarding',
        child: (context, state) => OnboardingPage(
          myController: inject<MyController>(),
        ),
        transition: TransitionType.none,
      )
      ..route(
        '/error',
        child: (context, state) => Scaffold(
          appBar: AppBar(title: const Text('Perzutv')),
          body: const GeneralErrorWidget(
            title: '初始化失败',
            errMsg: '请重新启动应用后再试。',
          ),
        ),
      )
      ..module(tabModule)
      ..module(videoModule)
      ..module(movieDetailModule)
      ..module(officialModule)
      ..route(
        ImageViewer.routePath,
        child: (context, state) {
          final args = state.arguments;
          if (args is! ImageViewerRouteArgs) {
            return const RouteErrorPage(message: '图片预览参数无效，请返回后重试。');
          }
          return ImageViewer(
            imageUrls: args.imageUrls,
            initialIndex: args.initialIndex,
            heroTag: args.heroTag,
          );
        },
        transition: _imagePreviewTransition,
      )
      ..module(settingsModule);
  },
);
