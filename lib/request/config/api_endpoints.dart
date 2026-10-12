import 'package:flutter/services.dart' show appBuildName;

class ApiEndpoints {
  /// 当前版本
  static const String version = appBuildName ?? '0.0.0';

  /// 规则API级别
  static const int apiLevel = 8;

  /// 项目主页
  static const String projectUrl = "https://github.com/buffet11/perzutv";

  /// Github 项目主页
  static const String sourceUrl = "https://github.com/buffet11/perzutv";

  /// 上游开源项目（GPL-3.0）。
  ///
  /// 本项目在其基础上做了大量修改与重构，依许可要求**保留署名与出处链接**，
  /// 但「关于」页以 Perzutv 自己为主语介绍，不再把自己描述成上游的附庸。
  static const String upstreamProjectUrl = "https://github.com/Predidit/Kazumi";

  /// 图标作者
  static const String iconUrl = "https://www.pixiv.net/users/66219277";

  /// 规则仓库
  static const String pluginShop =
      'https://raw.githubusercontent.com/Predidit/KazumiRules/main/';

  /// 规则仓库镜像
  static const String pluginShopMirror =
      'https://raw.gitcode.com/gh_mirrors/ka/KazumiRules/raw/main/';

  /// 在线升级
  ///
  /// ⚠️ 二开注意：这里**必须**指向本分支自己的 release。
  /// 上游 Kazumi 的更新源（releases/latest + api.kazumi.fyi 镜像后端）返回的是
  /// Kazumi 的版本号，而本分支版本独立编号（从 0.1.0 起）。
  /// 一旦沿用上游源，`needUpdate()` 会拿 0.1.0 去比 2.3.7 判定"有新版本"，
  /// 然后把用户引导去下载**原版 Kazumi**，等于覆盖掉本分支。
  static const String latestApp =
      'https://api.github.com/repos/buffet11/perzutv/releases/latest';

  /// 更新检查地址。
  /// 本分支暂无自建镜像后端，直接走 GitHub Release API。
  static const String latestAppMirror = latestApp;

  /// 本分支是否已经开始发布版本。
  ///
  /// 为 false 时：不做自动检查，手动检查给出明确提示，
  /// 而不是因为 GitHub 上还没有 release（404）而报"检查更新失败"。
  /// 开始发版后把这里改成 true，并同步维护上面的仓库地址。
  static const bool updateChannelReady = false;

  /// Bangumi 镜像测试后端
  static const String bangumiMirrorDomain = 'https://api.kazumi.fyi';

  /// 弹弹官网
  static const String dandanIndex = 'https://www.dandanplay.com/';

  /// Bangumi 官网
  static const String bangumiIndex = 'https://bangumi.tv/';

  /// bangumi API
  static const String bangumiAPIDomain = 'https://api.bgm.tv';

  /// Bangumi 鉴权 API
  static const String bangumiAuthAPIMirrorDomain = 'https://api.bgmapi.com';

  /// ⚠️ 这是**上游 Kazumi 的** Telegram 群，不是本项目的社群。
  ///
  /// 本项目目前没有自己的社群入口，所以「关于」页不再展示它 ——
  /// 否则等于把用户引到别人的群里去问我们的问题。常量保留是为了记录出处，
  /// 名字里带 upstream 以免日后被误当成"我们的群"接回去。
  static const String upstreamTelegramGroup = 'https://t.me/kazumi_app';

  /// 番剧信息
  static const String bangumiInfoByID = '/v0/subjects/{0}';

  /// 条目关联信息
  static const String bangumiRelationsByID = '/v0/subjects/{0}/subjects';

  /// 条目搜索
  static const String bangumiRankSearch =
      '/v0/search/subjects?limit={0}&offset={1}';

  /// 从条目ID获取角色信息
  static const String bangumiCharacterByID = '/v0/subjects/{0}/characters';

  /// 从条目ID获取工作人员信息
  static const String bangumiStaffByID = '/v0/subjects/{0}/persons';

  /// 从条目ID获取剧集ID
  static const String bangumiEpisodeByID = '/v0/episodes';

  /// 返回当前 Access Token 对应的用户信息
  static const String bangumiUsernameByToken = '/v0/me';

  /// 新增或修改用户单个条目收藏
  static const String bangumiSetCollection = '/v0/users/-/collections/{0}';

  /// 获取用户全部收藏（不限类型）。用户名，分页参数1(limit)，分页参数2(offset)
  static const String bangumiGetAllCollections =
      '/v0/users/{0}/collections?subject_type=2&limit={1}&offset={2}';

  /// Bangumi Next API Domain
  static const String bangumiAPINextDomain = 'https://next.bgm.tv';

  static const bangumiPublicApiHosts = {'api.bgm.tv', 'next.bgm.tv'};

  /// 每日放送
  static const String bangumiCalendar = '/p1/calendar';

  /// 番剧趋势
  static const String bangumiTrendsNext = '/p1/trending/subjects';

  /// Kazumi Bangumi 镜像缓存榜单
  static const String bangumiMirrorPopularSubjects =
      '/kazumi/v1/popular/subjects';

  /// Kazumi Bangumi 镜像季节时间表
  static const String bangumiMirrorSeasonCalendar =
      '/kazumi/v1/calendar/season';

  /// 番剧信息
  static const String bangumiInfoByIDNext = '/p1/subjects/{0}';

  /// 番剧评论
  static const String bangumiCommentsByIDNext =
      '/p1/subjects/{0}/comments?limit={1}&offset={2}';

  /// 番剧剧集评论
  static const String bangumiEpisodeCommentsByIDNext =
      '/p1/episodes/{0}/comments';

  /// 番剧角色信息
  static const String bangumiCharacterInfoByCharacterIDNext =
      '/p1/characters/{0}';

  /// 番剧角色评论
  static const String bangumiCharacterCommentsByIDNext =
      '/p1/characters/{0}/comments';

  /// DanDanPlay API Domain
  static const String dandanAPIDomain = 'https://api.dandanplay.net';

  /// 获取弹幕
  static const String dandanAPIComment = "/api/v2/comment/";

  /// 检索弹弹番剧元数据
  static const String dandanAPISearchEpisodes = "/api/v2/search/episodes";

  /// 获取弹弹番剧元数据
  static const String dandanAPIInfo = "/api/v2/bangumi/";

  /// 获取弹弹番剧元数据（通过BGM番剧ID）
  static const String dandanAPIInfoByBgmBangumiId = "/api/v2/bangumi/bgmtv/{0}";

  /// 图片识别番剧
  static const String traceApi = 'https://api.trace.moe/search';

  static String formatUrl(String url, List<dynamic> params) {
    for (int i = 0; i < params.length; i++) {
      url = url.replaceAll('{$i}', params[i].toString());
    }
    return url;
  }
}
