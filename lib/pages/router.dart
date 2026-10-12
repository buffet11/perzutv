class MenuRouteItem {
  const MenuRouteItem({required this.path});

  final String path;
}

class MenuRoute {
  const MenuRoute(this.menuList);

  final List<MenuRouteItem> menuList;

  String getPath(int index) => menuList[index].path;

  int indexForPath(String path) {
    final index = menuList.indexWhere(
      (item) =>
          path == '/tab${item.path}' ||
          path == '/tab${item.path}/' ||
          path.startsWith('/tab${item.path}/'),
    );
    return index < 0 ? 0 : index;
  }
}

const MenuRoute menu = MenuRoute([
  // 「动漫」放最前（也是默认启动页）。
  // ⚠️ 这里的顺序 = 所有 Tab 的下标，改动必须同步改 menu.dart 里
  // _bottomMenu / _sideMenu 的 destinations 顺序，否则点击会跳到错误路由。
  //
  // 番剧相关的「推荐 / 时间表 / 追番」三个 Tab 已整体移除（本项目只保留
  // 影视 + 动漫两条采集源链路），所以下标只剩 0/1/2。
  MenuRouteItem(path: '/anime'),
  MenuRouteItem(path: '/movie'),
  MenuRouteItem(path: '/my'),
]);

