import 'package:flutter/material.dart';

import 'package:perzutv/bean/settings/settings_detail_scaffold.dart';
import 'package:perzutv/bean/widget/content_section.dart';
import 'package:perzutv/pages/about/about_widgets.dart';
import 'package:perzutv/request/config/api_endpoints.dart';

/// 「致谢」：列出本项目**真正还在用**的开源项目与第三方服务。
///
/// 维护原则：番剧模块移除后，Bangumi 元数据、以图搜番（trace.moe）这些服务
/// 已经不再被请求，继续挂在致谢里等于不实声明 —— 所以一并去掉，换成实际在用的
/// 采集协议（MacCMS）与自建弹幕服务（danmu_api）。
class CreditsPage extends StatelessWidget {
  const CreditsPage({super.key});

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('致谢'),
        body: AboutContent(
          children: [
            ContentSection.group(
              title: '本项目',
              children: const [
                AboutLinkTile(
                  icon: Icons.people_outline_rounded,
                  title: '贡献者',
                  url: '${ApiEndpoints.sourceUrl}/graphs/contributors',
                ),
                AboutLinkTile(
                  icon: Icons.account_tree_outlined,
                  title: 'Kazumi（上游基础）',
                  subtitle: '本项目在其基础上做了大量修改 · GPL-3.0',
                  url: ApiEndpoints.upstreamProjectUrl,
                ),
                AboutLinkTile(
                  icon: Icons.brush_rounded,
                  title: '图标作者',
                  subtitle: '上游图标资源 · Pixiv',
                  url: ApiEndpoints.iconUrl,
                ),
              ],
            ),
            const SizedBox(height: 24),
            ContentSection.group(
              title: '服务',
              children: const [
                AboutLinkTile(
                  icon: Icons.subtitles_rounded,
                  title: '弹弹play',
                  subtitle: '弹幕协议与索引',
                  url: ApiEndpoints.dandanIndex,
                ),
                AboutLinkTile(
                  icon: Icons.dns_rounded,
                  title: 'danmu_api',
                  subtitle: '内置的自建弹幕聚合服务',
                  url: 'https://github.com/huangxd-/danmu_api',
                ),
                AboutLinkTile(
                  icon: Icons.movie_filter_rounded,
                  title: 'MacCMS（苹果CMS）',
                  subtitle: '影视源采集接口协议',
                  url: 'https://www.maccms.la/',
                ),
              ],
            ),
            const SizedBox(height: 24),
            ContentSection.group(
              title: '开源项目',
              children: const [
                AboutLinkTile(
                  icon: Icons.live_tv_rounded,
                  title: 'LibreTV',
                  subtitle: '影视源聚合思路与源清单参考',
                  url: 'https://github.com/LibreSpark/LibreTV',
                ),
                AboutLinkTile(
                  icon: Icons.flutter_dash_rounded,
                  title: 'Flutter',
                  subtitle: '应用框架',
                  url: 'https://flutter.dev',
                ),
                AboutLinkTile(
                  icon: Icons.play_circle_outline_rounded,
                  title: 'media-kit',
                  subtitle: '视频播放',
                  url: 'https://github.com/media-kit/media-kit',
                ),
                AboutLinkTile(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Anime4K',
                  subtitle: '实时超分辨率',
                  url: 'https://github.com/bloc97/Anime4K',
                ),
                AboutLinkTile(
                  icon: Icons.sync_rounded,
                  title: 'Syncplay',
                  subtitle: '播放同步',
                  url: 'https://github.com/Syncplay/syncplay',
                ),
                AboutLinkTile(
                  icon: Icons.account_tree_rounded,
                  title: 'XpathSelector',
                  subtitle: 'XPath 解析',
                  url: 'https://github.com/simonkimi/xpath_selector',
                ),
                AboutLinkTile(
                  icon: Icons.video_settings_rounded,
                  title: 'avbuild',
                  subtitle: '非标准视频流支持',
                  url: 'https://github.com/wang-bin/avbuild',
                ),
                AboutLinkTile(
                  icon: Icons.storage_rounded,
                  title: 'Hive CE',
                  subtitle: '本地存储',
                  url: 'https://github.com/IO-Design-Team/hive_ce',
                ),
              ],
            ),
          ],
        ),
      );
}
