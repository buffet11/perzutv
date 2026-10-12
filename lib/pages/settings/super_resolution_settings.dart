import 'package:flutter/material.dart';
import 'package:perzutv/bean/settings/settings_detail_scaffold.dart';
import 'package:perzutv/pages/player/controller/player_super_resolution.dart';
import 'package:perzutv/services/storage/storage.dart';
import 'package:perzutv/bean/settings/settings_list.dart';
import 'package:perzutv/utils/constants.dart';
import 'package:perzutv/utils/device.dart';

class SuperResolutionSettings extends StatefulWidget {
  const SuperResolutionSettings({super.key});

  @override
  State<SuperResolutionSettings> createState() =>
      _SuperResolutionSettingsState();
}

class _SuperResolutionSettingsState extends State<SuperResolutionSettings> {
  late bool disableWarning;
  late SuperResolutionMode superResolutionMode;
  late String desktopGpuApi;
  final MenuController gpuApiMenuController = MenuController();

  @override
  void initState() {
    super.initState();
    disableWarning = GStorage.getSetting<bool>(
      SettingsKeys.disableSuperResolutionWarning,
    );
    superResolutionMode = SuperResolutionMode.fromStorageValue(
      GStorage.getSetting<int>(SettingsKeys.defaultSuperResolutionMode),
    );
    desktopGpuApi = GStorage.getSetting<String>(SettingsKeys.desktopGpuApi);
  }

  void updateDesktopGpuApi(String value) {
    GStorage.putSetting<String>(SettingsKeys.desktopGpuApi, value);
    setState(() {
      desktopGpuApi = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SettingsDetailScaffold(
      title: const Text('画质处理'),
      body: SettingsList(
        sections: [
          SettingsRadioSection<SuperResolutionMode>(
            title: Text(isDesktop()
                ? '画质处理靠 GPU 实时运算，档位越高越吃显卡。\n'
                    '核显设备建议从「流畅」开始试，真的卡顿会自动降档。'
                : '超分辨率需要启用硬件解码, 若启用硬件解码后仍然不生效, 尝试切换视频渲染器为 gpu'),
            groupValue: superResolutionMode,
            onChanged: (SuperResolutionMode? value) {
              if (value == null) return;
              GStorage.putSetting<int>(
                SettingsKeys.defaultSuperResolutionMode,
                value.storageValue,
              );
              setState(() {
                superResolutionMode = value;
              });
            },
            tiles: [
              for (final mode in SuperResolutionMode.values)
                SettingsTile<SuperResolutionMode>.radioTile(
                  title: Text(mode.label),
                  description: Text(mode.description),
                  radioValue: mode,
                ),
            ],
          ),
          SettingsSection(
            title: Text('说明'),
            tiles: [
              SettingsTile(
                leading: Icons.tips_and_updates_rounded,
                title: const Text('想要更清晰，先换源再谈超分'),
                description: Text(isDesktop()
                    ? '超分是把低分辨率画面「算」清楚，效果有上限。片源本身只有 360P/480P 时，'
                        '优先在影片详情里换一条更清晰的线路，或打开设置中的「高画质源」，'
                        '通常比开滤镜更划算。'
                    : '超分是把低分辨率画面「算」清楚，效果有上限。片源本身清晰度低时，'
                        '优先换一条更清晰的线路。'),
              ),
              if (isDesktop())
                SettingsTile(
                  leading: Icons.speed_rounded,
                  title: const Text('卡顿会自动降档'),
                  description: const Text('开启画质处理后，若实测渲染帧率持续跟不上视频帧率，'
                      '会自动降低一档并提示，避免卡到没法看。'),
                ),
            ],
          ),
          if (isDesktop())
            SettingsSection(
              title: Text('高级'),
              tiles: [
                SettingsTile(
                  leading: Icons.memory_rounded,
                  onPressed: (_) {
                    if (gpuApiMenuController.isOpen) {
                      gpuApiMenuController.close();
                    } else {
                      gpuApiMenuController.open();
                    }
                  },
                  title: Text('GPU 后端'),
                  description: Text('GLSL 滤镜在不同后端上的编译与渲染开销差别很大，'
                      '卡顿时可以换一个试试；若出现异常或黑屏，改回「自动」即可'),
                  value: MenuAnchor(
                    consumeOutsideTap: true,
                    controller: gpuApiMenuController,
                    builder: (_, __, ___) {
                      return Text(
                        desktopGpuApiList[desktopGpuApi] ?? desktopGpuApi,
                      );
                    },
                    menuChildren: [
                      for (final entry in desktopGpuApiList.entries)
                        MenuItemButton(
                          requestFocusOnHover: false,
                          onPressed: () => updateDesktopGpuApi(entry.key),
                          child: Container(
                            height: 48,
                            constraints: BoxConstraints(minWidth: 112),
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                entry.value,
                                style: TextStyle(
                                  color: entry.key == desktopGpuApi
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          SettingsSection(
            title: Text('默认行为'),
            tiles: [
              SettingsTile.switchTile(
                leading: Icons.notifications_off_rounded,
                title: Text('关闭提示'),
                description: Text('关闭每次启用画质处理时的提示'),
                initialValue: disableWarning,
                onToggle: (value) async {
                  disableWarning = value ?? !disableWarning;
                  await GStorage.putSetting<bool>(
                    SettingsKeys.disableSuperResolutionWarning,
                    disableWarning,
                  );
                  if (mounted) setState(() {});
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
