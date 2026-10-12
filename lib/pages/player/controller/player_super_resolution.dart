/// 播放画面处理档位（画质档）。
///
/// 这里的 `storageValue` 是历史持久化值，必须保持稳定：
/// 早期版本只有 关闭(1) / 效率档(2) / 质量档(3)，本版本在保留原编号的基础上
/// 把 2 号档调整为更轻的「标准」，并新增 4 号「流畅」档，因此老用户的设置
/// 不会失效 —— 原本选了效率档的人只会变得更流畅，不会更卡。
///
/// 枚举声明顺序即界面展示顺序，按处理强度从低到高排列。
enum SuperResolutionMode {
  off(
    storageValue: 1,
    label: '关闭',
    description: '不做任何画面处理，直接输出原画，占用最低',
    usesSuperResolution: false,
    performanceWarning: false,
  ),
  smooth(
    storageValue: 4,
    label: '流畅',
    description: 'Anime4K 轻量模型 (S)，核显/笔记本也能长期开启',
    usesSuperResolution: true,
    performanceWarning: false,
  ),
  balance(
    storageValue: 2,
    label: '标准',
    description: 'Anime4K 中等模型（去模糊 + 放大），适合中端独显',
    usesSuperResolution: true,
    performanceWarning: false,
  ),
  quality(
    storageValue: 3,
    label: '高清',
    description: 'Anime4K 高质量模型 (VL)，画质最好但很吃显卡',
    usesSuperResolution: true,
    performanceWarning: true,
  );

  const SuperResolutionMode({
    required this.storageValue,
    required this.label,
    required this.description,
    required this.usesSuperResolution,
    required this.performanceWarning,
  });

  final int storageValue;
  final String label;
  final String description;

  /// 是否会向 mpv 挂载 GLSL 滤镜。需要 GPU 渲染路径才生效，
  /// 因此在仅软解/直通渲染的场景（例如 Android 的 mediacodec_embed）要禁用。
  final bool usesSuperResolution;

  /// 是否需要提前提示可能卡顿。
  final bool performanceWarning;

  /// 画质档强度表：[off] < [smooth] < [balance] < [quality]。
  /// 设备跑不动当前档时，自动降到下一档而不是直接关掉，尽量留住画质提升。
  SuperResolutionMode? get lighterMode {
    switch (this) {
      case SuperResolutionMode.off:
        return null;
      case SuperResolutionMode.smooth:
        return SuperResolutionMode.off;
      case SuperResolutionMode.balance:
        return SuperResolutionMode.smooth;
      case SuperResolutionMode.quality:
        return SuperResolutionMode.balance;
    }
  }

  static SuperResolutionMode fromStorageValue(int value) {
    return SuperResolutionMode.values.firstWhere(
      (mode) => mode.storageValue == value,
      orElse: () => SuperResolutionMode.off,
    );
  }
}
