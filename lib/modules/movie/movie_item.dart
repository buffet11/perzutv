import 'package:perzutv/modules/movie/movie_origin.dart';

/// 跨源聚合后的统一搜索结果条目。
///
/// 苹果CMS 的 `vod_*` 字段全是字符串（包括评分和年份），这里原样保留成 String，
/// 需要数值比较时在用到的地方显式解析 —— 源站的数据质量参差不齐，
/// 提前 parse 会在脏数据上直接抛异常。
class MovieSearchItem {
  /// 来源源的 key，用于回查配置与「换源」
  final String sourceKey;

  /// 来源源的显示名，UI 上标「来自 XX」
  final String sourceName;

  /// 源站内的影片 id
  final String vodId;

  final String name;
  final String pic;

  /// 科幻片 / 连续剧 / 综艺
  final String typeName;

  final String year;
  final String area;

  /// 「HD国语」/「更新至12集」
  final String remarks;

  /// 源站评分，字符串形态
  final String score;

  final bool isAdult;

  /// 从哪个模块点进来的（[MovieOrigin.movie] / [MovieOrigin.anime]）。
  ///
  /// 搜索结果本身不带这个信息，是**入口页**赋的（动漫页会把条目标成 anime），
  /// 一路带到播放页，最终决定这条观看记录归到哪个列表。
  final String origin;

  const MovieSearchItem({
    required this.sourceKey,
    required this.sourceName,
    required this.vodId,
    required this.name,
    this.pic = '',
    this.typeName = '',
    this.year = '',
    this.area = '',
    this.remarks = '',
    this.score = '',
    this.isAdult = false,
    this.origin = MovieOrigin.movie,
  });

  /// 全局唯一键：同一个影片在不同源里是不同条目
  String get uniqueKey => '$sourceKey:$vodId';

  /// 只重新标记来源模块（其余字段原样保留）。
  MovieSearchItem copyWith({String? origin}) => MovieSearchItem(
        sourceKey: sourceKey,
        sourceName: sourceName,
        vodId: vodId,
        name: name,
        pic: pic,
        typeName: typeName,
        year: year,
        area: area,
        remarks: remarks,
        score: score,
        isAdult: isAdult,
        origin: origin ?? this.origin,
      );

  /// 评分解析失败返回 null（源站常有「8.3 分」这类脏数据）
  double? get scoreValue {
    final m = RegExp(r'\d+(\.\d+)?').firstMatch(score);
    if (m == null) return null;
    return double.tryParse(m.group(0)!);
  }

  /// 年份解析，取前四位数字
  int? get yearValue {
    final m = RegExp(r'(19|20)\d{2}').firstMatch(year);
    if (m == null) return null;
    return int.tryParse(m.group(0)!);
  }

  Map<String, dynamic> toJson() => {
        'sourceKey': sourceKey,
        'sourceName': sourceName,
        'vodId': vodId,
        'name': name,
        'pic': pic,
        'typeName': typeName,
        'year': year,
        'area': area,
        'remarks': remarks,
        'score': score,
        'isAdult': isAdult,
        'origin': origin,
      };

  factory MovieSearchItem.fromJson(Map<String, dynamic> json) => MovieSearchItem(
        sourceKey: json['sourceKey'] as String? ?? '',
        sourceName: json['sourceName'] as String? ?? '',
        vodId: json['vodId'] as String? ?? '',
        name: json['name'] as String? ?? '',
        pic: json['pic'] as String? ?? '',
        typeName: json['typeName'] as String? ?? '',
        year: json['year'] as String? ?? '',
        area: json['area'] as String? ?? '',
        remarks: json['remarks'] as String? ?? '',
        score: json['score'] as String? ?? '',
        isAdult: json['isAdult'] == true,
        origin: MovieOrigin.resolve(json['origin']),
      );

  @override
  String toString() => 'MovieSearchItem($sourceName/$vodId, $name, $year, $remarks)';
}

/// 单源搜索的一页结果。
class CmsSearchPage {
  final List<MovieSearchItem> items;

  /// 当前页（1 起）
  final int page;

  /// 总页数（源站给的 `pagecount`，可能为 0 或缺失）
  final int pageCount;

  /// 总条数（源站给的 `total`）
  final int total;

  const CmsSearchPage({
    required this.items,
    this.page = 1,
    this.pageCount = 0,
    this.total = 0,
  });

  static const empty = CmsSearchPage(items: []);

  @override
  String toString() => 'CmsSearchPage(page $page/$pageCount, total $total, ${items.length} 条)';
}
