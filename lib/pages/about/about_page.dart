import 'package:flutter/material.dart';

import 'package:perzutv/bean/settings/settings_detail_scaffold.dart';
import 'package:perzutv/bean/widget/content_section.dart';
import 'package:perzutv/pages/about/about_widgets.dart';
import 'package:perzutv/request/config/api_endpoints.dart';

/// 「关于」页。
///
/// 定位说明：Perzutv 现在是**独立品牌、独立功能面**（影视 + 动漫两条采集源
/// 链路），页面以自己为主语介绍；上游 Kazumi 只在「许可与致谢」里出现。
/// ⚠️ 但那一行**不能删**：本项目是 GPL-3.0 的衍生作品，保留版权署名、许可
/// 文本与来源链接是许可证的强制要求，删掉会有法律风险（原作者可要求纠正）。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key, required this.onCheckUpdate});

  final Future<bool> Function() onCheckUpdate;

  @override
  Widget build(BuildContext context) => SettingsDetailScaffold(
        title: const Text('关于'),
        body: AboutContent(
          children: [
            _ProjectHeader(onCheckUpdate: onCheckUpdate),
            const SizedBox(height: 24),
            LayoutBuilder(builder: (context, constraints) {
              final sections = [
                ContentSection.group(
                  title: '项目',
                  children: [
                    const AboutLinkTile(
                      icon: Icons.code_rounded,
                      title: '源代码',
                      url: ApiEndpoints.sourceUrl,
                    ),
                    const AboutLinkTile(
                      icon: Icons.bug_report_rounded,
                      title: '问题反馈',
                      url: '${ApiEndpoints.sourceUrl}/issues',
                    ),
                    AboutLinkTile(
                      icon: Icons.article_outlined,
                      title: '更新日志',
                      url: '${ApiEndpoints.sourceUrl}/releases',
                    ),
                  ],
                ),
                ContentSection.group(
                  title: '许可与致谢',
                  children: [
                    const AboutLinkTile.route(
                      icon: Icons.favorite_outline_rounded,
                      title: '致谢',
                      subtitle: '用到的开源项目与服务',
                      route: '/settings/about/credits',
                    ),
                    const AboutLinkTile(
                      icon: Icons.account_tree_outlined,
                      title: '本项目的上游基础',
                      subtitle: 'Kazumi（GPL-3.0）· 本项目在其基础上做了大量修改',
                      url: ApiEndpoints.upstreamProjectUrl,
                    ),
                    const AboutLinkTile(
                      icon: Icons.balance_rounded,
                      title: 'GPL-3.0 许可证',
                      subtitle: '本项目遵循同一许可发布',
                      url: '${ApiEndpoints.sourceUrl}/blob/main/LICENSE',
                    ),
                    const AboutLinkTile.route(
                      icon: Icons.description_outlined,
                      title: '第三方许可证',
                      route: '/settings/about/license',
                    ),
                  ],
                ),
              ];
              if (constraints.maxWidth >= 640 &&
                  MediaQuery.textScalerOf(context).scale(14) < 21) {
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: sections[0]),
                    const SizedBox(width: 16),
                    Expanded(child: sections[1]),
                  ],
                );
              }
              return Column(
                children: [
                  sections[0],
                  const SizedBox(height: 24),
                  sections[1]
                ],
              );
            }),
          ],
        ),
      );
}

class _ProjectHeader extends StatelessWidget {
  const _ProjectHeader({required this.onCheckUpdate});

  final Future<bool> Function() onCheckUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Perzutv',
              style: theme.textTheme.displayMedium?.copyWith(
                color: colors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            ApiEndpoints.version,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '影视 · 动漫聚合播放器',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            '聚合多家影视采集源，支持分区浏览、多线路切换与网页解析播放；'
            '内置弹幕服务，观看进度自动记录并可续播，数据全部保存在本机。',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 12),
          // 开源声明：主语是 Perzutv 自己，上游出处如实标注（GPL-3.0 强制保留）
          Text(
            'Perzutv 以 GPL-3.0 许可开源发布，是独立开发维护的项目，'
            '与任何第三方项目及其作者无隶属、合作或授权关系。'
            '项目源自开源项目 Kazumi（GPL-3.0），并做了大量修改与重构，'
            '其版权归原作者所有；相关署名与许可文本已在下方与「第三方许可证」中保留。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              CheckUpdateButton(onCheckUpdate: onCheckUpdate),
            ],
          ),
        ],
      ),
    );
  }
}
