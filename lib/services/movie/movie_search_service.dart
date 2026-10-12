import 'dart:async';

import 'package:perzutv/modules/movie/builtin_movie_sources.dart';
import 'package:perzutv/modules/movie/movie_item.dart';
import 'package:perzutv/modules/movie/movie_source.dart';
import 'package:perzutv/request/apis/apple_cms_api.dart';

/// 某个源在这次搜索里失败了。
///
/// **UI 必须把它展示出来** —— 否则用户会以为「搜不到就是没有这部电影」，
/// 而实际可能只是某个源超时了。这是 LibreTV 已经做对的事。
class SourceFailure {
  final String sourceKey;
  final String sourceName;
  final String message;

  const SourceFailure({
    required this.sourceKey,
    required this.sourceName,
    required this.message,
  });

  @override
  String toString() => '$sourceName: $message';
}

/// 一次聚合搜索的结果。
class SearchOutcome {
  final String keyword;
  final List<MovieSearchItem> items;
  final List<SourceFailure> failures;

  /// 参与本次搜索的源数量
  final int sourceCount;

  const SearchOutcome({
    required this.keyword,
    required this.items,
    required this.failures,
    required this.sourceCount,
  });

  bool get isEmpty => items.isEmpty;

  /// 全部源都失败了（区别于「都成功但没结果」）
  bool get allFailed => sourceCount > 0 && failures.length == sourceCount;

  @override
  String toString() =>
      'SearchOutcome("$keyword", ${items.length} 条, '
      '${failures.length}/$sourceCount 源失败)';
}

/// 跨源聚合搜索。
class MovieSearchService {
  MovieSearchService._();

  /// 每个源最多翻几页。
  ///
  /// LibreTV 用 5。这里默认 3 —— 苹果CMS 的搜索质量一般，第一页通常就有
  /// 十几条，再往后翻多为同片的不同清晰度/年份版本；而每多一页就多一轮请求，
  /// 对慢源（实测暴风资源单次 17s）是成倍的等待。需要更多时传参即可。
  static const defaultMaxPages = 3;

  /// 并发搜索所有启用的源。
  ///
  /// 单源失败只记入 [SearchOutcome.failures]，不影响其它源。
  static Future<SearchOutcome> searchAll(
    String keyword, {
    List<MovieSource>? sources,
    int maxPages = defaultMaxPages,
  }) async {
    final kw = keyword.trim();
    if (kw.isEmpty) {
      return const SearchOutcome(
        keyword: '',
        items: [],
        failures: [],
        sourceCount: 0,
      );
    }

    final active = (sources ?? builtinMovieSources())
        .where((s) => s.enabled && s.isUsable)
        .toList();

    final collected = <MovieSearchItem>[];
    final failures = <SourceFailure>[];

    await Future.wait(active.map((source) async {
      try {
        collected.addAll(await _searchOneSource(source, kw, maxPages));
      } catch (e) {
        failures.add(SourceFailure(
          sourceKey: source.key,
          sourceName: source.name,
          message: _describeError(e),
        ));
      }
    }));

    return SearchOutcome(
      keyword: kw,
      items: _dedupeAndSort(collected, kw),
      failures: failures,
      sourceCount: active.length,
    );
  }

  /// 单个源拉前 N 页。
  static Future<List<MovieSearchItem>> _searchOneSource(
    MovieSource source,
    String keyword,
    int maxPages,
  ) async {
    final first = await AppleCmsApi.search(source, keyword, 1);
    final result = <MovieSearchItem>[...first.items];

    // pagecount 缺失（0）时按 maxPages 走 —— 有的源不返回这个字段
    final limit = first.pageCount > 0
        ? (first.pageCount < maxPages ? first.pageCount : maxPages)
        : maxPages;

    for (var page = 2; page <= limit; page++) {
      final next = await AppleCmsApi.search(source, keyword, page);
      if (next.items.isEmpty) break;
      result.addAll(next.items);
    }

    return result;
  }

  /// 去重 + 排序。
  ///
  /// 去重键是 `sourceKey:vodId` —— 同一个影片在不同源里是不同条目，
  /// 我们保留它们（这本来就是「多源」的价值：一条线路挂了还能换源）。
  /// 真正要去的是同源内的重复。
  static List<MovieSearchItem> _dedupeAndSort(
    List<MovieSearchItem> items,
    String keyword,
  ) {
    final seen = <String>{};
    final unique = <MovieSearchItem>[];
    for (final item in items) {
      if (seen.add(item.uniqueKey)) unique.add(item);
    }

    final exact = keyword.toLowerCase();

    unique.sort((a, b) {
      // 1. 标题精确命中优先
      final aExact = a.name.toLowerCase() == exact;
      final bExact = b.name.toLowerCase() == exact;
      if (aExact != bExact) return aExact ? -1 : 1;

      // 2. 标题以关键词开头次之
      final aStarts = a.name.toLowerCase().startsWith(exact);
      final bStarts = b.name.toLowerCase().startsWith(exact);
      if (aStarts != bStarts) return aStarts ? -1 : 1;

      // 3. 有评分的优先
      final aScore = a.scoreValue;
      final bScore = b.scoreValue;
      if ((aScore != null) != (bScore != null)) return aScore != null ? -1 : 1;

      // 4. 有海报的优先（无海报的条目在 UI 上是空白块，观感很差）
      final aPic = a.pic.isNotEmpty;
      final bPic = b.pic.isNotEmpty;
      if (aPic != bPic) return aPic ? -1 : 1;

      // 5. 年份新的优先
      final aYear = a.yearValue ?? 0;
      final bYear = b.yearValue ?? 0;
      if (aYear != bYear) return bYear.compareTo(aYear);

      return a.name.compareTo(b.name);
    });

    return unique;
  }

  static String _describeError(Object error) {
    final text = error.toString();
    if (text.length <= 120) return text;
    return '${text.substring(0, 120)}…';
  }
}
