import 'package:flutter/material.dart';
import 'package:flutter_modular/flutter_modular.dart';

import 'package:perzutv/bean/appbar/sys_app_bar.dart';
import 'package:perzutv/pages/menu/route_visibility.dart';
import 'package:perzutv/pages/my/my_controller.dart';
import 'package:perzutv/pages/my/my_space_view.dart';
import 'package:perzutv/modules/movie/movie_origin.dart';
import 'package:perzutv/services/movie/movie_history_service.dart';

class MyPage extends StatefulWidget {
  const MyPage({super.key, required this.controller});

  final MyController controller;

  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  bool _attached = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _setAttached(!RouteVisibility.isCoveredOf(context));
  }

  @override
  void didUpdateWidget(covariant MyPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_attached && oldWidget.controller != widget.controller) {
      oldWidget.controller.detach();
      widget.controller.attach();
    }
  }

  @override
  void dispose() {
    _setAttached(false);
    super.dispose();
  }

  void _setAttached(bool value) {
    if (_attached == value) return;
    _attached = value;
    if (value) {
      widget.controller.attach();
    } else {
      widget.controller.detach();
    }
  }

  void _open(MyDestination destination) =>
      context.pushNamed(switch (destination) {
        MyDestination.theme => '/settings/theme',
        MyDestination.player => '/settings/player',
        MyDestination.danmaku => '/settings/danmaku/',
        MyDestination.records => '/settings/records',
        MyDestination.storage => '/settings/storage',
        MyDestination.about => '/settings/about/',
      });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: SysAppBar(
        toolbarHeight: 72,
        title: Text(
          '我的',
          style: Theme.of(context)
              .textTheme
              .headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        needTopOffset: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: MySettingsButton(
              onTap: () => context.pushNamed('/settings/'),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        bottom: false,
        // 观看记录：影视与动漫分开统计（两套内容共用同一份历史，靠 origin 区分）
        child: Builder(builder: (context) {
          final counts = MovieHistoryService.countByOrigin();
          return MySpaceView(
            movieCount: counts[MovieOrigin.movie] ?? 0,
            animeCount: counts[MovieOrigin.anime] ?? 0,
            onOpen: _open,
          );
        }),
      ),
    );
  }
}
