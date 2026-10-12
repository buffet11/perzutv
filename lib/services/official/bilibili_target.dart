/// B 站外链播放器的播放目标。
///
/// 设计原则：**只解析、不猜测**。用户粘贴什么就识别什么，识别不出来就返回
/// null 让调用方给出提示，绝不"猜一个最接近的"——猜错的代价是用户点了播放
/// 却打不开，而且不知道为什么。
///
/// 支持的输入形态（与官方外链播放器文档的参数一一对应）：
///   * 完整链接：`https://www.bilibili.com/bangumi/play/ep282316`
///   * 完整链接：`https://www.bilibili.com/video/BV1B7411m7LV?spm_id_from=...`
///   * 裸编号：`ep282316` / `ss26801` / `av170001` / `BV1B7411m7LV`
library;

enum BiliTargetType {
  /// UGC 视频，BV 号（新格式）
  videoBvid,

  /// UGC 视频，AV 号（旧格式，官方仍兼容）
  videoAid,

  /// 番剧/影视的**具体一集**。官方文档里 OGV 场景下 `episodeId` 是必填项。
  episode,

  /// 番剧/影视的**整季**。单靠它不一定能起播，需要先换成某一集。
  season;

  String get label {
    switch (this) {
      case BiliTargetType.videoBvid:
      case BiliTargetType.videoAid:
        return '视频';
      case BiliTargetType.episode:
        return '剧集';
      case BiliTargetType.season:
        return '整季';
    }
  }
}

class BiliTarget {
  const BiliTarget({
    required this.type,
    required this.id,
    required this.raw,
  });

  final BiliTargetType type;

  /// 编号本体。BV 号保留 `BV` 前缀，其余为纯数字字符串。
  final String id;

  /// 用户原始输入，仅用于界面回显。
  final String raw;

  bool get isSeason => type == BiliTargetType.season;
  bool get isEpisode => type == BiliTargetType.episode;

  /// 番剧/影视（需要走 OGV 参数）
  bool get isOgv => isSeason || isEpisode;

  /// 官方外链播放器地址。
  ///
  /// `high_quality=1` = 最高「非大会员」清晰度；`danmaku=1` 用 B 站自带弹幕
  /// （本播放路径跑在 WebView 里，项目的 mpv 弹幕层覆盖不到它）。
  String get playerUrl {
    final buffer = StringBuffer('https://player.bilibili.com/player.html?');
    switch (type) {
      case BiliTargetType.videoBvid:
        buffer.write('bvid=$id');
        break;
      case BiliTargetType.videoAid:
        buffer.write('aid=$id');
        break;
      case BiliTargetType.episode:
        buffer.write('episodeId=$id');
        break;
      case BiliTargetType.season:
        buffer.write('seasonId=$id');
        break;
    }
    buffer.write('&autoplay=1&danmaku=1&high_quality=1');
    return buffer.toString();
  }

  /// 从任意用户输入里识别播放目标；识别不出来返回 null。
  static BiliTarget? parse(String input) {    final text = input.trim();
    if (text.isEmpty) {
      return null;
    }

    // 番剧链接：/bangumi/play/ep123  或  /bangumi/play/ss123
    final playMatch =
        RegExp(r'/(ep|ss)(\d+)', caseSensitive: false).firstMatch(text);
    if (playMatch != null) {
      final kind = playMatch.group(1)!.toLowerCase();
      final number = playMatch.group(2)!;
      return BiliTarget(
        type: kind == 'ep' ? BiliTargetType.episode : BiliTargetType.season,
        id: number,
        raw: text,
      );
    }

    // BV 号：BV + 10 位 base58
    final bvMatch = RegExp(r'(BV[0-9A-Za-z]{10})').firstMatch(text);
    if (bvMatch != null) {
      return BiliTarget(
        type: BiliTargetType.videoBvid,
        id: bvMatch.group(1)!,
        raw: text,
      );
    }

    // AV 号：要求 av 后面直接跟数字（词边界），避免命中 av 开头的普通单词
    final avMatch = RegExp(r'\bav(\d+)\b', caseSensitive: false).firstMatch(text);
    if (avMatch != null) {
      return BiliTarget(
        type: BiliTargetType.videoAid,
        id: avMatch.group(1)!,
        raw: text,
      );
    }

    // 裸编号：必须整串匹配，防止把无关文字里的数字当成编号
    final bareEp = RegExp(r'^(ep|ss)(\d+)$', caseSensitive: false).firstMatch(text);
    if (bareEp != null) {
      final kind = bareEp.group(1)!.toLowerCase();
      return BiliTarget(
        type: kind == 'ep' ? BiliTargetType.episode : BiliTargetType.season,
        id: bareEp.group(2)!,
        raw: text,
      );
    }
    final bareBv = RegExp(r'^(BV[0-9A-Za-z]{10})$').firstMatch(text);
    if (bareBv != null) {
      return BiliTarget(
        type: BiliTargetType.videoBvid,
        id: bareBv.group(1)!,
        raw: text,
      );
    }

    return null;
  }
}

/// 跳转播放页时携带的参数。
///
/// 刻意放在这个纯数据文件里，而不是放进路由模块：路由模块要 import 页面，
/// 页面又要用到这个参数类 —— 定义在模块里就形成循环依赖。放在这里，
/// 两边都只依赖它，方向是单向的。
class OfficialPlayerArgs {
  const OfficialPlayerArgs({required this.target, this.title});

  final BiliTarget target;
  final String? title;
}
