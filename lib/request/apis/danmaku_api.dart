import 'package:perzutv/modules/danmaku/danmaku_ch_convert.dart';
import 'package:perzutv/modules/danmaku/danmaku_episode_response.dart';
import 'package:perzutv/modules/danmaku/danmaku_module.dart';
import 'package:perzutv/modules/danmaku/danmaku_search_response.dart';
import 'package:perzutv/request/clients/danmaku_client.dart';
import 'package:perzutv/request/config/api_endpoints.dart';
import 'package:perzutv/services/danmaku/danmaku_service_host.dart';
import 'package:perzutv/services/logging/logger.dart';
import 'package:perzutv/services/storage/storage.dart';

class DanmakuApi {
  static final DanmakuClient _client = DanmakuClient.instance;

  /// 是否走弹弹play 兼容的自定义链路（内置服务 > 手填的自建地址）。
  static bool get useCustomApi =>
      DanmakuServiceHost.instance.isEnabled ||
      GStorage.getSetting(SettingsKeys.customDanmakuApi).trim().isNotEmpty;

  /// 弹幕 API 域名。优先级：内置服务 → 手填自定义地址 → 官方。
  static String get _domain {
    if (DanmakuServiceHost.instance.isEnabled) {
      return DanmakuServiceHost.baseUrl;
    }
    final custom = GStorage.getSetting(SettingsKeys.customDanmakuApi).trim();
    if (custom.isEmpty) {
      return ApiEndpoints.dandanAPIDomain;
    }
    return custom.endsWith('/') ? custom.substring(0, custom.length - 1) : custom;
  }

  /// 统一的「番剧 ID 解析」入口：
  /// - 官方 API：走 bgmtv ID 映射端点。
  /// - 自定义 API：不支持 bgmtv 映射，改用标题搜索选最佳匹配。
  static Future<int> resolveDanDanBangumiID({
    required int bgmBangumiID,
    String title = '',
  }) async {
    if (useCustomApi) {
      if (title.trim().isEmpty) {
        KazumiLogger().w(
            'Danmaku: custom API enabled but no bangumi title provided, cannot match');
        return 0;
      }
      return getDanDanBangumiIDByTitle(title);
    }
    return getDanDanBangumiIDByBgmBangumiID(bgmBangumiID);
  }

  /// 官方端点：通过 bgmtv 番剧 ID 查 DanDan 番剧 ID。
  static Future<int> getDanDanBangumiIDByBgmBangumiID(int bgmBangumiID) async {
    final path = ApiEndpoints.formatUrl(
      ApiEndpoints.dandanAPIInfoByBgmBangumiId,
      [bgmBangumiID],
    );
    final endPoint = _domain + path;
    final jsonData = await _client.get(endPoint);
    return DanmakuEpisodeResponse.fromJson(jsonData).bangumiId;
  }

  /// 自定义 API 端点：标题搜索 → 选最佳匹配的番剧 ID。
  ///
  /// 匹配优先级：归一化标题完全一致 > 第一个结果。
  static Future<int> getDanDanBangumiIDByTitle(String title) async {
    await DanmakuServiceHost.instance.ensureStarted();
    final response = await searchAnimes(title);
    if (response.animes.isEmpty) {
      KazumiLogger().i('Danmaku: title search found no anime for "$title"');
      return 0;
    }
    final normalized = _normalizeTitle(title);
    for (final anime in response.animes) {
      if (_normalizeTitle(anime.animeTitle) == normalized) {
        KazumiLogger()
            .i('Danmaku: title match "${anime.animeTitle}" (${anime.animeId})');
        return anime.animeId;
      }
    }
    final fallback = response.animes.first;
    KazumiLogger().i(
        'Danmaku: no exact title match, fallback to "${fallback.animeTitle}" (${fallback.animeId})');
    return fallback.animeId;
  }

  static String _normalizeTitle(String title) =>
      title.toLowerCase().replaceAll(RegExp(r'\s+'), '');

  static Future<DanmakuEpisodeResponse> getDanDanEpisodesByDanDanBangumiID(
    int bangumiID,
  ) async {
    final path = ApiEndpoints.dandanAPIInfo + bangumiID.toString();
    final endPoint = _domain + path;
    final jsonData = await _client.get(endPoint);
    return DanmakuEpisodeResponse.fromJson(jsonData);
  }

  // v2 episode search avoids the anime search's 25-result cap.
  // Fetch full episode lists separately; search results can truncate them.
  static Future<DanmakuSearchResponse> searchAnimes(String title) async {
    await DanmakuServiceHost.instance.ensureStarted();
    final endPoint = _domain + ApiEndpoints.dandanAPISearchEpisodes;
    final jsonData = await _client.get(
      endPoint,
      queryParameters: {'anime': title, 'v2': 'true'},
    );
    return DanmakuSearchResponse.fromJson(jsonData);
  }

  static Future<List<DanmakuEntry>> getDanDanmaku(
    int bangumiID,
    int episode,
  ) async {
    if (bangumiID == 0) {
      return [];
    }
    if (useCustomApi) {
      // 自建服务不遵循官方「bangumiID+集数」的 episodeId 约定，
      // 必须先取剧集列表，按集数选出真实 episodeId。
      final detail = await getDanDanEpisodesByDanDanBangumiID(bangumiID);
      final target = _pickEpisode(detail.episodes, episode);
      if (target == null) {
        KazumiLogger().w(
            'Danmaku: episode $episode not found in ${detail.episodes.length} episodes');
        return [];
      }
      return getDanDanmakuByEpisodeID(target.episodeId);
    }
    // Automatic matching relies on an undocumented episode ID convention.
    return _getComments('$bangumiID${episode.toString().padLeft(4, '0')}');
  }

  /// 从剧集列表中挑选目标集：先按标题里的集数数字精确匹配，
  /// 匹配不到再按位置取第 [episode] 个（1-based）。
  static DanmakuEpisode? _pickEpisode(List<DanmakuEpisode> episodes, int episode) {
    if (episodes.isEmpty) return null;
    for (final ep in episodes) {
      final match = RegExp(r'(\d+)').allMatches(ep.episodeTitle);
      for (final m in match) {
        if (int.tryParse(m.group(1)!) == episode) {
          return ep;
        }
      }
    }
    if (episode >= 1 && episode <= episodes.length) {
      return episodes[episode - 1];
    }
    return null;
  }

  static Future<List<DanmakuEntry>> getDanDanmakuByEpisodeID(int episodeID) =>
      _getComments(episodeID.toString());

  static Future<List<DanmakuEntry>> _getComments(String episodeID) async {
    await DanmakuServiceHost.instance.ensureStarted();
    final endPoint = '$_domain${ApiEndpoints.dandanAPIComment}$episodeID';
    final conversion = DanmakuChConvert.fromValue(
      GStorage.getSetting(SettingsKeys.danmakuChConvert),
    );
    KazumiLogger().i('Danmaku: final request URL $endPoint');
    final jsonData = await _client.get(
      endPoint,
      queryParameters: {
        'withRelated': 'true',
        'chConvert': conversion.value.toString(),
      },
    );
    final List<dynamic> comments = jsonData['comments'];
    return [for (final comment in comments) DanmakuEntry.fromJson(comment)];
  }
}
