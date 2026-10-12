import 'package:flutter/material.dart';
import 'package:perzutv/bean/settings/settings_detail_scaffold.dart';
import 'package:perzutv/bean/settings/settings_list.dart';
import 'package:perzutv/services/storage/storage.dart';
import 'package:perzutv/utils/device.dart';
import 'package:perzutv/utils/startup_page.dart';

class InterfaceSettingsPage extends StatefulWidget {
  const InterfaceSettingsPage({super.key});

  @override
  State<InterfaceSettingsPage> createState() => _InterfaceSettingsPageState();
}

class _InterfaceSettingsPageState extends State<InterfaceSettingsPage> {
  late bool showRating;
  late String defaultPage;
  final _exitBehaviorMenuController = MenuController();
  static const _exitBehaviorTitles = ['退出 Perzutv', '最小化至托盘', '每次都询问'];
  int _exitBehavior = GStorage.getSetting(SettingsKeys.exitBehavior)
      .clamp(0, _exitBehaviorTitles.length - 1);
  final MenuController defaultPageMenuController = MenuController();

  /// 可选启动页（动漫 / 影视 / 我的）统一由 [StartupPage] 维护，
  /// 避免"这里有 4 项、那边白名单只有 3 项"的漂移。
  static const Map<String, String> defaultPageMap = StartupPage.labels;

  @override
  void initState() {
    super.initState();
    showRating = GStorage.getSetting(SettingsKeys.showRating);
    defaultPage = StartupPage.resolve(
        GStorage.getSetting(SettingsKeys.defaultStartupPage));
  }

  void updateDefaultPage(String page) {
    final resolved = StartupPage.resolve(page);
    GStorage.putSetting(SettingsKeys.defaultStartupPage, resolved);
    setState(() {
      defaultPage = resolved;
    });
  }

  Widget _menuItem({
    required String label,
    required bool selected,
    required VoidCallback? onPressed,
  }) =>
      MenuItemButton(
        requestFocusOnHover: false,
        onPressed: onPressed,
        child: Container(
          height: 48,
          constraints: const BoxConstraints(minWidth: 112),
          alignment: Alignment.centerLeft,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Theme.of(context).colorScheme.primary : null,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: Text('界面设置'),
      body: SettingsList(
        sections: [
          SettingsSection(title: Text('启动'), tiles: [
            SettingsTile(
              leading: Icons.home_rounded,
              onPressed: (_) async {
                if (defaultPageMenuController.isOpen) {
                  defaultPageMenuController.close();
                } else {
                  defaultPageMenuController.open();
                }
              },
              title: Text('启动界面设置'),
              description: Text('设置应用开启时的默认页面'),
              value: MenuAnchor(
                consumeOutsideTap: true,
                controller: defaultPageMenuController,
                builder: (_, __, ___) {
                  return Text(
                    defaultPageMap[defaultPage] ?? StartupPage.labels[StartupPage.fallback]!,
                  );
                },
                menuChildren: [
                  for (final entry in defaultPageMap.entries)
                    _menuItem(
                      label: entry.value,
                      selected: entry.key == defaultPage,
                      onPressed: () => updateDefaultPage(entry.key),
                    ),
                ],
              ),
            ),
          ]),
          SettingsSection(title: Text('展示信息'), tiles: [
            SettingsTile.switchTile(
              leading: Icons.star_rounded,
              onToggle: (value) async {
                showRating = value ?? !showRating;
                await GStorage.putSetting(SettingsKeys.showRating, showRating);
                setState(() {});
              },
              title: Text('显示评分'),
              description: Text('关闭后隐藏影视 / 动漫列表中的评分信息'),
              initialValue: showRating,
            ),
          ]),
          if (isDesktop())
            SettingsSection(
              title: const Text('窗口行为'),
              tiles: [
                SettingsTile(
                  leading: Icons.exit_to_app_rounded,
                  title: const Text('关闭窗口时'),
                  description: const Text('设置点击窗口关闭按钮后的行为'),
                  onPressed: (_) => _exitBehaviorMenuController.isOpen
                      ? _exitBehaviorMenuController.close()
                      : _exitBehaviorMenuController.open(),
                  value: MenuAnchor(
                    controller: _exitBehaviorMenuController,
                    consumeOutsideTap: true,
                    builder: (_, __, ___) =>
                        Text(_exitBehaviorTitles[_exitBehavior]),
                    menuChildren: [
                      for (var i = 0; i < _exitBehaviorTitles.length; i++)
                        _menuItem(
                          label: _exitBehaviorTitles[i],
                          selected: i == _exitBehavior,
                          onPressed: () {
                            setState(() => _exitBehavior = i);
                            GStorage.putSetting(SettingsKeys.exitBehavior, i);
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
