/// B 站公开接口的最小封装。
///
/// 只做两件必需的事：把「季号」换成「集列表」，以及尽量拿到一个可读标题。
/// 所有方法**失败即返回 null**，绝不抛异常给上层 —— 这条路径是锦上添花，
/// 拿不到数据时的正确行为是降级提示用户"直接粘贴某一集的链接"，而不是崩。
///
/// 只用 `dart:io`，不引入新的 HTTP 依赖。
library;

import 'dart:convert';
import 'dart:io';

import 'package:perzutv/services/logging/logger.dart';

class BiliEpisode {
  const BiliEpisode({
    required this.epId,
    required this.title,
    required this.longTitle,
    this.durationSeconds,
  });

  /// 官方外链播放器的 `episodeId`
  final int epId;

  /// 序号标题，如「1」
  final String title;

  /// 副标题，如「踏上旅途」
  final String longTitle;

  final int? durationSeconds;

  /// 界面上优先显示副标题，没有就退回序号。
  String get displayTitle {
    if (longTitle.isNotEmpty && title.isNotEmpty) {
      return '$title $longTitle';
    }
    if (longTitle.isNotEmpty) return longTitle;
    if (title.isNotEmpty) return title;
    return '第 $epId 集';
  }
}

class BiliSeason {
  const BiliSeason({
    required this.seasonId,
    required this.title,
    required this.episodes,
  });

  final int seasonId;
  final String title;
  final List<BiliEpisode> episodes;
}

class BilibiliApi {
  BilibiliApi._();

  static const String _ua =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

  static const Duration _timeout = Duration(seconds: 10);

  /// 取季信息与集列表。失败返回 null。
  static Future<BiliSeason?> fetchSeason(int seasonId) async {
    final json = await _getJson(
      'https://api.bilibili.com/pgc/view/web/season?season_id=$seasonId',
    );
    if (json == null || json['code'] != 0) {
      KazumiLogger().i('BilibiliApi: 季信息不可用 season_id=$seasonId');
      return null;
    }
    final result = json['result'];
    if (result is! Map) {
      return null;
    }

    final episodes = <BiliEpisode>[];
    final rawEpisodes = result['episodes'];
    if (rawEpisodes is List) {
      for (final item in rawEpisodes) {
        if (item is! Map) continue;
        final epId = _asInt(item['id']) ?? _asInt(item['ep_id']);
        if (epId == null) continue;
        final durationMs = _asInt(item['duration']);
        episodes.add(
          BiliEpisode(
            epId: epId,
            title: '${item['title'] ?? ''}'.trim(),
            longTitle: '${item['long_title'] ?? ''}'.trim(),
            durationSeconds:
                durationMs == null || durationMs <= 0 ? null : durationMs ~/ 1000,
          ),
        );
      }
    }
    if (episodes.isEmpty) {
      KazumiLogger().i('BilibiliApi: 季信息里没有集列表 season_id=$seasonId');
      return null;
    }

    return BiliSeason(
      seasonId: _asInt(result['season_id']) ?? seasonId,
      title: '${result['title'] ?? ''}'.trim(),
      episodes: episodes,
    );
  }

  /// 取 UGC 视频标题。拿不到就返回 null（不影响播放）。
  static Future<String?> fetchVideoTitle(String bvid) async {
    final json = await _getJson(
      'https://api.bilibili.com/x/web-interface/view?bvid=$bvid',
    );
    if (json == null || json['code'] != 0) {
      return null;
    }
    final data = json['data'];
    if (data is! Map) {
      return null;
    }
    final title = '${data['title'] ?? ''}'.trim();
    return title.isEmpty ? null : title;
  }

  static Future<Map<String, dynamic>?> _getJson(String url) async {
    final client = HttpClient()..connectionTimeout = _timeout;
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, _ua);
      // 带上 Referer：B 站对 api 的裸访问偶有拦截，加上更稳。
      request.headers.set(HttpHeaders.refererHeader, 'https://www.bilibili.com/');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(_timeout);
      if (response.statusCode != 200) {
        return null;
      }
      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_timeout);
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry('$key', value));
      }
      return null;
    } catch (e) {
      KazumiLogger().w('BilibiliApi: 请求失败 $url', error: e);
      return null;
    } finally {
      try {
        client.close(force: true);
      } catch (_) {}
    }
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}
