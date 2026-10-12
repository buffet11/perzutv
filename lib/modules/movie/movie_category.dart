/// 采集源的分类条目（苹果CMS `class` 数组里的一项）。
class CmsCategory {
  /// 源站内部的分区 ID，请求分区列表时要原样带回去（`ac=detail&t=<typeId>`）。
  final String typeId;

  /// 源站给的分区名，如「国产动漫」「日韩动漫」。
  final String typeName;

  const CmsCategory({required this.typeId, required this.typeName});
}

/// 「动漫」模块的统一分区。
///
/// 各采集站的分类命名五花八门（动漫片 / 国产动漫 / 动画片 / 日韩动漫 …），
/// 这里把它们归一到几个固定分区，跨源合并时才能对齐。
class AnimePartition {
  /// 稳定 ID，用于持久化选中状态。
  final String id;

  /// 展示名。
  final String label;

  const AnimePartition({required this.id, required this.label});

  /// 全部分区（即「全部动漫」）：匹配各源的「动漫片 / 动漫 / 动画片」这类总类目。
  static const all = AnimePartition(id: 'all', label: '全部动漫');
  static const cn = AnimePartition(id: 'cn', label: '国产动漫');
  static const jpKr = AnimePartition(id: 'jp_kr', label: '日韩动漫');
  static const usEu = AnimePartition(id: 'us_eu', label: '欧美动漫');
  static const hkTw = AnimePartition(id: 'hk_tw', label: '港台动漫');
  static const other = AnimePartition(id: 'other', label: '其他动漫');

  /// 展示顺序（「全部动漫」永远排第一）。
  static const List<AnimePartition> ordered = [
    all,
    cn,
    jpKr,
    usEu,
    hkTw,
    other,
  ];

  /// 把源站的分类名归一化到统一分区；返回 null = 这个分类不是动漫，忽略。
  ///
  /// ⚠️ 两道判断，顺序不能反：
  ///   1. **先确认它确实是动漫类目**（含 动漫/动画/国漫/番剧/剧场版）。
  ///      否则「欧美剧」「日韩剧」这种**电视剧**分类会因为含"欧美/日韩"被
  ///      误当成动漫分区 —— 实测踩过，会把美剧塞进动漫模块。
  ///   2. 再按地区细分。「国产动漫」不能落到 all 上，所以地区判断要在总类目之前。
  static AnimePartition? fromTypeName(String typeName) {
    final name = typeName.trim();
    if (name.isEmpty) return null;

    // 第一道：必须是动漫类目
    const animeCores = ['动漫', '动画', '国漫', '番剧', '剧场版'];
    if (!animeCores.any(name.contains)) return null;

    // 第二道：地区细分
    if (name.contains('国产') || name.contains('大陆') || name.contains('国漫')) {
      return cn;
    }
    if (name.contains('日韩') ||
        name.contains('日本') ||
        name.contains('韩国') ||
        name.contains('日漫')) {
      return jpKr;
    }
    if (name.contains('欧美') || name.contains('美国') || name.contains('欧洲')) {
      return usEu;
    }
    if (name.contains('港台') || name.contains('香港') || name.contains('台湾')) {
      return hkTw;
    }
    if (name.contains('海外') || name.contains('其他')) {
      return other;
    }
    // 只是「动漫片 / 动画片 / 剧场版」这类总类目
    return all;
  }
}

/// 某个源在某个统一分区下对应的具体分类（跨源聚合成一次查询的输入）。
class PartitionTarget {
  final String sourceKey;
  final String typeId;

  const PartitionTarget({required this.sourceKey, required this.typeId});
}
