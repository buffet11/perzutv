import 'package:flutter/material.dart';
import 'package:perzutv/bean/settings/settings_list.dart';
import 'package:perzutv/bean/widget/content_section.dart';
import 'package:perzutv/bean/widget/state_presentation.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

/// 「我的」页里的可跳转目标。
///
/// 番剧相关的 规则设置 / 历史记录 / 离线下载 / 同步备份 四项已随番剧功能
/// 一并移除，只剩影视动漫用得上的通用设置 + 观看记录。
enum MyDestination {
  theme,
  player,
  danmaku,
  records,
  storage,
  about,
}

const _tileRadius = BorderRadius.all(Radius.circular(28));

/// 「观看记录」入口的副标题：影视与动漫分开显示条数。
String _recordsCaption(int movieCount, int animeCount) {
  if (movieCount == 0 && animeCount == 0) return '暂无观看记录';
  return '影视 $movieCount · 动漫 $animeCount';
}

class MySpaceView extends StatelessWidget {
  const MySpaceView({
    super.key,
    required this.movieCount,
    required this.animeCount,
    required this.onOpen,
  });

  /// 影视观看记录条数。
  final int movieCount;

  /// 动漫观看记录条数。
  final int animeCount;

  final ValueChanged<MyDestination> onOpen;

  int get _total => movieCount + animeCount;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final inset = constraints.maxWidth < 600 ? 16.0 : 32.0;
      final width = constraints.maxWidth - inset * 2;
      final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
      final wide = width >= 840 && !largeText;
      return SingleChildScrollView(
        key: const PageStorageKey('my-space'),
        padding: EdgeInsets.fromLTRB(inset, 12, inset, 32),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: wide
                ? _WideSpaceLayout(
                    historyCount: _total,
                    movieCount: movieCount,
                    animeCount: animeCount,
                    onOpen: onOpen,
                  )
                : _CompactSpaceLayout(
                    historyCount: _total,
                    movieCount: movieCount,
                    animeCount: animeCount,
                    onOpen: onOpen,
                    stackTools: width < 280 || largeText,
                  ),
          ),
        ),
      );
    });
  }
}

class _WideSpaceLayout extends StatelessWidget {
  const _WideSpaceLayout({
    required this.historyCount,
    required this.movieCount,
    required this.animeCount,
    required this.onOpen,
  });

  final int historyCount;
  final int movieCount;
  final int animeCount;
  final ValueChanged<MyDestination> onOpen;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AdaptivePair(
          gap: 20,
          first: const _SpaceHeading(),
          second: _WatchStatsPanel(historyCount: historyCount),
        ),
        const SizedBox(height: 28),
        _AdaptivePair(
          first: _ToolTile(
            icon: Icons.history_rounded,
            title: '观看记录',
            caption: _recordsCaption(movieCount, animeCount),
            color: colors.secondaryContainer,
            foreground: colors.onSecondaryContainer,
            onTap: () => onOpen(MyDestination.records),
          ),
          second: _ToolTile(
            icon: Icons.cleaning_services_rounded,
            title: '存储管理',
            caption: '缓存与日志',
            color: colors.surfaceContainer,
            foreground: colors.onSurface,
            onTap: () => onOpen(MyDestination.storage),
          ),
        ),
        const SizedBox(height: 12),
        _PreferencesPanel(onOpen: onOpen),
        const SizedBox(height: 24),
        Align(
          alignment: Alignment.center,
          child: _ExpressiveAction(
            color: colors.surfaceContainerLow,
            foreground: colors.onSurfaceVariant,
            onTap: () => onOpen(MyDestination.about),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.info_outline_rounded, size: 20),
                  SizedBox(width: 8),
                  Flexible(child: Text('关于 Perzutv')),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CompactSpaceLayout extends StatelessWidget {
  const _CompactSpaceLayout({
    required this.historyCount,
    required this.movieCount,
    required this.animeCount,
    required this.onOpen,
    required this.stackTools,
  });

  final int historyCount;
  final int movieCount;
  final int animeCount;
  final ValueChanged<MyDestination> onOpen;
  final bool stackTools;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WatchStatsPanel(historyCount: historyCount, compact: true),
        const SizedBox(height: 24),
        ContentSection.group(
          title: '内容与偏好',
          children: [
            _entry('观看记录', Icons.history_rounded, MyDestination.records,
                caption: _recordsCaption(movieCount, animeCount)),
            _entry('外观设置', Icons.palette_rounded, MyDestination.theme),
            _entry('播放设置', Icons.play_circle_rounded, MyDestination.player),
            _entry('弹幕设置', Icons.subtitles_rounded, MyDestination.danmaku),
          ],
        ),
        const SizedBox(height: 24),
        ContentSection.group(
          title: '数据与应用',
          children: [
            _entry(
                '存储管理', Icons.cleaning_services_rounded, MyDestination.storage),
            _entry(
                '关于 Perzutv', Icons.info_outline_rounded, MyDestination.about),
          ],
        ),
      ],
    );
  }

  Widget _entry(
    String title,
    IconData icon,
    MyDestination destination, {
    String? caption,
  }) =>
      SettingsTile(
        title: Text(title),
        description: caption == null ? null : Text(caption),
        leading: icon,
        trailing: const Icon(Icons.chevron_right_rounded, size: 20),
        onPressed: (_) => onOpen(destination),
      );
}

class _WatchStatsPanel extends StatelessWidget {
  const _WatchStatsPanel({required this.historyCount, this.compact = false});

  /// 影视 / 动漫的观看记录条数。
  final int historyCount;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: compact ? colors.primaryContainer : colors.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(compact ? 28 : 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (compact)
              Row(
                children: [
                  _ShapeIcon(
                    shape: _SpaceShape.sun,
                    icon: Icons.sentiment_satisfied_alt_rounded,
                    size: 32,
                    color: colors.primary,
                    foreground: colors.onPrimary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text('观看足迹',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(
                                  color: colors.onPrimaryContainer,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              )
            else
              Text('观看记录',
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _StatCount(
                    value: historyCount,
                    label: '影视与动漫',
                    foreground: compact ? colors.onPrimaryContainer : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCount extends StatelessWidget {
  const _StatCount({required this.value, required this.label, this.foreground});

  final int value;
  final String label;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Scale large totals without shrinking their labels.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text('$value',
              style: theme.textTheme.displaySmall?.copyWith(
                  color: foreground ?? theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
                color: foreground ?? theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _SpaceHeading extends StatelessWidget {
  const _SpaceHeading();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text(
            '个人中心',
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: colors.onSurface,
                  height: 1.2,
                ),
          ),
        ),
        const SizedBox(width: 12),
        _ShapeIcon(
          shape: _SpaceShape.sun,
          icon: Icons.sentiment_satisfied_alt_rounded,
          size: 64,
          color: colors.tertiaryContainer,
          foreground: colors.onTertiaryContainer,
        ),
      ],
    );
  }
}

class _ToolTile extends StatelessWidget {
  const _ToolTile({
    required this.icon,
    required this.title,
    required this.caption,
    required this.color,
    required this.foreground,
    required this.onTap,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String caption;
  final Color color;
  final Color foreground;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _ExpressiveAction(
      color: color,
      foreground: foreground,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.all(compact ? 16 : 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, size: compact ? 24 : 30),
                const Spacer(),
                const Icon(Icons.arrow_forward_rounded, size: 20),
              ],
            ),
            SizedBox(height: compact ? 12 : 26),
            Text(title,
                style: text.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700, color: foreground)),
            SizedBox(height: compact ? 4 : 6),
            Text(caption,
                style:
                    text.bodySmall?.copyWith(color: foreground, height: 1.4)),
          ],
        ),
      ),
    );
  }
}

class _PreferencesPanel extends StatelessWidget {
  const _PreferencesPanel({required this.onOpen});

  final ValueChanged<MyDestination> onOpen;

  static const _entries = [
    ('外观', Icons.palette_rounded, MyDestination.theme),
    ('播放', Icons.play_circle_rounded, MyDestination.player),
    ('弹幕', Icons.subtitles_rounded, MyDestination.danmaku),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: _tileRadius,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              header: true,
              child: Text('偏好设置',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700, color: colors.onSurface)),
            ),
            const SizedBox(height: 16),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < _entries.length; i++) ...[
                    if (i > 0) const SizedBox(width: 4),
                    Expanded(child: _button(i)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(int index) {
    final (label, icon, destination) = _entries[index];
    return _PreferenceAction(
      icon: icon,
      label: label,
      first: index == 0,
      last: index == _entries.length - 1,
      onTap: () => onOpen(destination),
    );
  }
}

class _PreferenceAction extends StatelessWidget {
  const _PreferenceAction({
    required this.icon,
    required this.label,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return _ExpressiveAction(
      color: colors.secondaryContainer,
      foreground: colors.onSecondaryContainer,
      radius: BorderRadius.horizontal(
        left: Radius.circular(first ? 24 : 8),
        right: Radius.circular(last ? 24 : 8),
      ),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28),
            const SizedBox(height: 10),
            Text(label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.onSecondaryContainer)),
          ],
        ),
      ),
    );
  }
}

class MySettingsButton extends StatelessWidget {
  const MySettingsButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: '全部设置',
      child: FilledButton.tonalIcon(
        style: StateActionButton.styleOf(context).copyWith(
          backgroundColor: WidgetStatePropertyAll(colors.surfaceContainerHigh),
          foregroundColor: WidgetStatePropertyAll(colors.onSurface),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
        ),
        onPressed: onTap,
        icon: const Icon(Icons.tune_rounded, size: 20),
        label: const Text('设置'),
      ),
    );
  }
}

enum _SpaceShape { sun, clover }

class _ShapeIcon extends StatelessWidget {
  const _ShapeIcon({
    required this.shape,
    required this.icon,
    required this.size,
    required this.color,
    required this.foreground,
  });

  final _SpaceShape shape;
  final IconData icon;
  final double size;
  final Color color;
  final Color foreground;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: ClipPath(
          clipper: _SpaceShapeClipper(shape),
          child: ColoredBox(
            color: color,
            child: SizedBox.square(
              dimension: size,
              child: Icon(icon, color: foreground, size: size * .44),
            ),
          ),
        ),
      );
}

class _SpaceShapeClipper extends CustomClipper<Path> {
  const _SpaceShapeClipper(this.shape);

  final _SpaceShape shape;
  static final _paths = {
    _SpaceShape.sun: MaterialShapes.sunny.toPath(),
    _SpaceShape.clover: MaterialShapes.clover4Leaf.toPath(),
  };

  @override
  Path getClip(Size size) => _paths[shape]!
      .transform(Matrix4.diagonal3Values(size.width, size.height, 1).storage);

  @override
  bool shouldReclip(_SpaceShapeClipper oldClipper) => oldClipper.shape != shape;
}

class _ExpressiveAction extends StatefulWidget {
  const _ExpressiveAction({
    required this.color,
    required this.foreground,
    required this.onTap,
    required this.child,
    this.radius = _tileRadius,
  });

  final Color color;
  final Color foreground;
  final VoidCallback onTap;
  final Widget child;
  final BorderRadius radius;

  @override
  State<_ExpressiveAction> createState() => _ExpressiveActionState();
}

class _ExpressiveActionState extends State<_ExpressiveAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final reducedMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reducedMotion
        ? Duration.zero
        : Duration(milliseconds: _pressed ? 150 : 300);
    return Semantics(
      button: true,
      child: AnimatedScale(
        scale: _pressed && !reducedMotion ? .97 : 1,
        duration: duration,
        curve: _pressed ? Curves.easeOutCubic : Curves.easeOutBack,
        child: AnimatedContainer(
          duration: duration,
          curve: Curves.easeOutCubic,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: _pressed ? BorderRadius.circular(16) : widget.radius,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: widget.onTap,
              onHighlightChanged: (value) => setState(() => _pressed = value),
              overlayColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.pressed)) {
                  return widget.foreground.withValues(alpha: .10);
                }
                if (states.contains(WidgetState.focused)) {
                  return widget.foreground.withValues(alpha: .12);
                }
                if (states.contains(WidgetState.hovered)) {
                  return widget.foreground.withValues(alpha: .08);
                }
                return null;
              }),
              child: IconTheme.merge(
                data: IconThemeData(color: widget.foreground),
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: widget.foreground,
                      ),
                  child: widget.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdaptivePair extends StatelessWidget {
  const _AdaptivePair({
    required this.first,
    required this.second,
    this.stack = false,
    this.gap = 12,
  });

  final Widget first;
  final Widget second;
  final bool stack;
  final double gap;

  @override
  Widget build(BuildContext context) {
    if (stack) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, SizedBox(height: gap), second],
      );
    }
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: first),
          SizedBox(width: gap),
          Expanded(child: second),
        ],
      ),
    );
  }
}
