# Perzutv 融合设计方案

> ⚠️ 项目后来已改名 **perzutv**（本文中的「Kazutv」是当时的工作名）。为保留设计过程，正文未做改写。
> 把 LibreTV 的影视能力并入 Kazumi 番剧应用
> 版本：v0.1（设计稿，待评审）
> 日期：2026-10-01

---

## 0. 摘要

以 **Kazumi（Flutter）为主干**，在其上新增一个独立的「影视」一级模块：用 Dart 实现苹果CMS（Apple CMS）聚合协议，接入电影 / 剧集 / 综艺内容；播放复用 Kazumi 现有的 `media_kit` 播放器与弹幕渲染层；弹幕新增「按标题自动检索 + 打分匹配 + 纠正记忆」能力，并提供独立开关；视频源沿用 LibreTV 的 `{name, url, detail, isAdult}` 自定义源范式，支持增删改与订阅导入。

**不做**：不把 LibreTV 的 Next.js/Tauri 代码搬进来，不用 WebView 内嵌 LibreTV，不移植其代理层（Flutter 无 CORS 限制，不需要）。

---

## 1. 目标与范围

### 1.1 需求

| # | 需求 | 来源 |
|---|---|---|
| R1 | 在 Kazumi 里能看电影、剧集、综艺 | 用户 |
| R2 | 影视内容也能用弹幕 | 用户 |
| R3 | 弹幕支持自动检索 + 自动加载，带独立开关（默认由用户决定开不开） | 用户 |
| R4 | 保留 LibreTV 的「自选视频源」——用户可自行添加源 | 用户 |
| R5 | 界面保持 Kazumi 原有的美观与操作习惯 | 用户 |

### 1.2 明确不做（本期）

- 不移植 LibreTV 的直播 / IPTV 能力（`/api/live/*`、M3U + EPG）。苹果CMS 协议里没有这块，属于另一个体系，先不碰。
- 不移植 LibreTV 的登录 / 密码 / 会话体系。Kazumi 是单机应用，没有服务端。
- 不移植 LibreTV 的 m3u8 重写代理与 SSRF 防护。详见 §3.2 D5。
- 不改动 Kazumi 现有的番剧链路（规则引擎、Bangumi 元数据、时间表、追番）。只做增量。

### 1.3 目标平台

**Windows 桌面 + Android 双目标。** 先 Windows（本机可编译调试，迭代最快），跑通后补 Android。

> 另注：用户主力机是 HarmonyOS 7（纯血鸿蒙）。Flutter 官方不支持 OHOS，需要走 `ErBWs/Kazumi` 的鸿蒙分支。那是另一条腿，本方案不覆盖，但架构上不做阻碍（不引入平台专属依赖）。

---

## 2. 现状分析

### 2.1 三个源码包能力矩阵

| 维度 | Kazumi-main | LibreTV-main | LibreTV-App-main |
|---|---|---|---|
| 技术栈 | Flutter 3.47.5 + MobX + flutter_modular | Next.js 15 + React 19 + TS | Tauri v2 + 原生 JS |
| 播放器 | media_kit（mpv 内核，自 fork） | ArtPlayer + hls.js | DPlayer + hls.js |
| 弹幕 | ✅ 完整（DanDanPlay，自动 + 手动匹配） | ❌ | ❌（DPlayer 带能力但未启用） |
| 视频源模型 | 规则引擎（XPath / API+JSONPath）+ WebView 嗅探 | 苹果CMS 聚合 | 苹果CMS 聚合 |
| 自选源 | ✅ 4 种入口（商店/模板/剪贴板/文件） | ✅ 表单 + 订阅 + 环境变量 | ✅ 表单 + 本地存储 |
| 源导入导出 | ✅ `kazumi://` 分享链接 + JSON | ✅ LibreTV-SourceList / TVBOX | ✅ `LibreTV-Settings` + sha256 |
| 本地存储 | Hive（8 个 Box） | localStorage + IndexedDB | localStorage |
| 许可证 | GPL-3.0 | AGPL-3.0 | — |
| **本方案中的角色** | **宿主（主干）** | 协议参考 | 自选源范式参考 |

### 2.2 Kazumi 可复用资产盘点

| 资产 | 位置 | 复用度 |
|---|---|---|
| 播放页全套 UI（进度条/手势/面板/截图/倍速/画中画/超分） | `lib/pages/player/`（约 1.4 万行） | **100% 直接复用** |
| 弹幕渲染 + 弹幕设置 + 屏蔽词 | `lib/pages/player/controller/player_danmaku_controller.dart`、`lib/pages/settings/danmaku/` | **约 90% 复用** |
| 弹幕手动检索面板（搜索→番剧→分集 三步） | `lib/pages/player/danmaku_source_sheet.dart`（824 行） | **直接复用** |
| 弹幕数据模型 | `lib/modules/danmaku/danmaku_module.dart` | 直接用 |
| 网络层（dio 工厂、错误映射、代理） | `lib/request/core/` | 直接用 |
| 设置框架（`SettingKey<T>` + 分组） | `lib/services/storage/settings_keys.dart`（700+ 行） | 直接扩展 |
| 播放上下文入参（sealed class） | `lib/pages/video/video_playback_args.dart` | **扩展点** |
| 番剧规则引擎 | `lib/services/plugin/rule_engine.dart` | 不复用（见 D2） |
| WebView 视频流嗅探 | `lib/webview/video/` | 影视不需要（直链） |

### 2.3 实测结论（本方案的技术依据）

> 以下均为本机实测，非推测。

**① 苹果CMS 协议可用，且字段比预期丰富**

```
GET http://caiji.dyttzyapi.com/api.php/provide/vod/?ac=videolist&wd=流浪地球&pg=1
→ 200, {"code":1,"msg":"数据列表","page":"1","pagecount":1,"limit":"20","total":4,"list":[...]}
```

除常规字段外，还在详情接口中拿到了：`vod_score`(8.3)、`vod_douban_id`(35267208)、`vod_douban_score`、`vod_year`、`vod_area`、`vod_class`、`vod_actor`、`vod_director`、`vod_blurb`、`vod_content`、`type_name`(科幻片)。**元数据足够撑起一个像样的详情页，不需要再查豆瓣。**

**② 线路必须做「可播性」筛选（关键）**

`流浪地球2` 的真实响应：

```
vod_play_from = dytt$$$dyttm3u8
vod_play_url  = HD国语$https://vip.dytt-live.com/share/926c11cc055de9b8d697b6a587d40c4d
                $$$HD国语$https://vip.dytt-live.com/20250505/5821_926c11cc/index.m3u8
```

- 线路 `dytt` → `/share/...` 是**网页中转页，交给播放器直接播不了**
- 线路 `dyttm3u8` → `/.../index.m3u8` 是**直链，可播**

这和 LibreTV 源码里「优先取含 `.m3u8` 直链的线路」的处理完全一致。**这条规则必须实现**，否则首条线路默认不可播，用户体验会直接崩。

**③ 源可用性参差，必须多源并发 + 降级**

| 源 | 实测结果 |
|---|---|
| `caiji.dyttzyapi.com` | ✅ 200，正常 JSON |
| `json.heimuer.xyz` | ⚠️ 302 → Cloudflare 挑战页 |
| `cj.rycjapi.com` | ❌ 连接失败 |

**④ 弹弹play API 是硬门槛**

```
GET https://api.dandanplay.net/api/v2/search/episodes?anime=三体
→ 403   （/search/anime、/comment/* 同样 403）
```

无 AppId/AppSecret 签名一律 403，未找到可用镜像。
Kazumi 的凭据来自 `lib/utils/dandan_credentials.dart` 的 `String.fromEnvironment`，由 CI 从 GitHub Secrets 注入 —— **源码里没有**。
→ **自己编译意味着番剧弹幕也会一起失效**，不只是新功能的问题。申请步骤见附录 A。

**⑤ 工具链现状**

| 组件 | 状态 |
|---|---|
| Flutter SDK | ❌ **缺失**，需装 3.47.5（正好当前 stable）。国内镜像 `storage.flutter-io.cn`，zip 1.93 GB，实测 9.7 MB/s（约 3.5 分钟） |
| Visual Studio | ✅ Community 2026，含 `VC.Tools.x86.x64` |
| Windows SDK | ✅ 10.0.26100.0（`E:\Windows Kits`） |
| Android SDK | ✅ `F:\Android\sdk`（`ANDROID_HOME` 已配） |
| JDK | ✅ 21（`D:\path\java\jdk21`） |

---

## 3. 总体架构

### 3.1 分层

```
┌─ 界面层 ────────────────────────────────────────────────────┐
│  推荐 │ 时间表 │ 追番 │ 影视(新) │ 我的                        │
└─────────────────────────────────────────────────────────────┘
        │                                    │
        ▼                                    ▼
┌─ 番剧链路（不动）─┐          ┌─ 影视链路（新增）──────────────┐
│ 规则引擎          │          │ 影视源管理 (MovieSourceManager)│
│ WebView 嗅探      │          │ 聚合搜索 (MovieSearchService)  │
│ Bangumi 元数据    │          │ 苹果CMS 客户端 (AppleCmsApi)   │
└───────────────────┘          └────────────────────────────────┘
        │                                    │
        └──────────────┬─────────────────────┘
                       ▼
        ┌─ 播放上下文抽象（改造点）──────────────────────┐
        │  VideoPlaybackArgs (sealed)                   │
        │   ├ OnlineVideoPlaybackArgs   (番剧，已有)     │
        │   ├ OfflineVideoPlaybackArgs  (离线，已有)     │
        │   └ MovieVideoPlaybackArgs    (影视，新增) ★   │
        └───────────────────────────────────────────────┘
                       ▼
        ┌─ 复用：播放页 + media_kit + 弹幕渲染 ─────────┐
        │  VideoPageController / PlayerController       │
        │  PlayerDanmakuController（加匹配策略分支）★    │
        └───────────────────────────────────────────────┘
                       ▼
        ┌─ 弹幕数据源 ──────────────────────────────────┐
        │  DanmakuApi（已有）                            │
        │   ├ 番剧：bgmId → dandanId → episodeId (已有)  │
        │   └ 影视：标题 → 打分 → episodeId（新增）★     │
        └───────────────────────────────────────────────┘
```

### 3.2 关键设计决策

**D1｜以 Kazumi 为宿主，用 Dart 重写影视链路（而非内嵌 LibreTV）**

- 理由：内嵌 WebView 会丢掉 Kazumi 的界面一致性与全部播放器能力（手势、截图、超分、画中画、DLNA、WebDAV 同步），等于把两套 UI 缝合在一起，与 R5 直接冲突。
- 代价：要重写。但苹果CMS 协议本质只有**两个接口**（搜索、详情），解析逻辑不到 200 行 Dart，成本可控。
- 收益：影视内容自动获得 Kazumi 已有的**下载、历史、WebDAV 同步、代理设置、硬件解码、超分辨率**等全部能力。

**D2｜影视作为独立一级模块，不并入番剧规则引擎**

- 理由：Kazumi 的规则引擎面向「网页解析」（XPath / WebView 嗅探），而苹果CMS 是**标准 JSON API**，两者心智模型不同。更关键的是内容形态差异大——番剧有 Bangumi 元数据、时间表、季度、角色；影视没有。硬塞进规则引擎会让 `Plugin` 模型变形，且污染番剧搜索结果。
- 代价：要做一套影视专属 UI。
- 缓解：数据模型独立，但**播放器与弹幕完全共用**，重复工作量有限。

**D3｜播放复用策略：新增第三种 `VideoPlaybackArgs` 变体**

`lib/pages/video/video_playback_args.dart` 已经是 `sealed class`，天然是扩展点：

```dart
sealed class VideoPlaybackArgs {
  const VideoPlaybackArgs({required this.bangumiItem});
  final BangumiItem bangumiItem;
}

// 新增
class MovieVideoPlaybackArgs extends VideoPlaybackArgs {
  const MovieVideoPlaybackArgs({
    required super.bangumiItem,   // 合成身份载体，见下
    required this.movieTitle,
    required this.movieCover,
    required this.routeName,
    required this.episodes,       // List<MovieEpisode>，已解析出直链
    required this.episodeIndex,
    required this.danmakuQuery,   // 弹幕匹配用的标题 + 年份
  });
  ...
}
```

> **关于 `bangumiItem`**：播放控制器把它当作「身份载体」用（`id` 做历史与弹幕键、`images['large']` 做封面、`nameCn` 做标题）。影视没有 Bangumi ID，方案是**合成一个占位 `BangumiItem`**，`id` 取保留段（建议 `3_000_000_000 + hash(sourceKey + vodId)`）避免与真实 bgm id 冲突。这样历史、封面、标题三条路径零改动。风险点是 Hive 里 int 无上限，安全。

**D4｜弹幕匹配：标题检索 + 打分 + 纠正记忆**

- 番剧路径（已有）：`bgmId` → `/bangumi/bgmtv/{id}` → `dandanBangumiId` → `episodeId = bangumiId*10000 + 集号`
- 影视路径（新增）：清洗标题 → `/search/episodes?anime=` → **打分选优** → 取 `episodeId` → `/comment/{episodeId}`
- 记忆优先：用户手动纠正过一次后，写入 `{sourceKey}:{vodId}:{集号} → episodeId`，下次跳过匹配。
- 详见 §5.6。

**D5｜不移植 LibreTV 的代理层**

LibreTV 需要 `/api/proxy` + m3u8 分片重写，是因为浏览器有 CORS 与防盗链限制。**Flutter 用 dio 直连 HTTP，不存在 CORS**——这正是 Kazumi 现有番剧链路也不需要代理的原因。因此：
- 只需要在请求里带自定义 `User-Agent` / `Referer`（Kazumi 已在播放器层支持 `httpHeaders`）。
- `m3u8` 直链可直接交给 mpv 播放。
- **省掉整个代理模块，是本次融合最大的成本节省点。**

**D6｜线路选择规则**

按「可播优先级」排序，而不是按源站顺序：

1. 线路内**含 `.m3u8` 直链** → 最优先（实测确认这是唯一能直接播的形态）
2. 线路内是 `http(s)` 且非 `/share/` 中转页 → 次优先
3. 其余（网页中转页）→ 排最后，且标注「需解析」

同一优先级内保持源站原顺序。

---

## 4. 数据模型

### 4.1 影视源

```dart
// lib/modules/movie/movie_source.dart
class MovieSource {
  String key;        // 唯一标识：'builtin_dytt' | 'custom_0' | 'sub_<hash>'
  String name;       // 显示名
  String api;        // https://x.com/api.php/provide/vod   （去尾斜杠）
  String detail;     // 可选：详情页根，用于 HTML 兜底抓取
  bool isAdult;      // 成人内容标记（参与过滤）
  bool enabled;      // 是否参与聚合搜索
  int order;         // 展示顺序
  int lastOkAt;      // 最近一次探活成功时间戳（0=从未）
  int lastLatencyMs; // 最近一次探活延迟（-1=失败）
}
```

> **格式与 LibreTV 完全对齐**：`{name, url, detail, isAdult}`。`api` 对应 LibreTV 的 `url`，导入导出时做字段映射即可直接吃它的 `LibreTV-SourceList` JSON 与 TVBOX 配置。

### 4.2 影视内容

```dart
// lib/modules/movie/movie_item.dart —— 搜索结果的统一形态（跨源聚合后）
class MovieSearchItem {
  String sourceKey;
  String sourceName;
  String vodId;
  String name;
  String pic;
  String typeName;   // 科幻片 / 连续剧 / 综艺
  String year;
  String area;
  String remarks;    // "HD国语" / "更新至12集"
  String score;
  bool isAdult;
}

// lib/modules/movie/movie_detail.dart
class MovieDetail {
  String sourceKey;
  String vodId;
  String name;
  String pic;
  String content;         // 已去 HTML 标签的简介
  String typeName;
  String year;
  String area;
  String remarks;
  double score;
  List<String> actors;
  List<String> directors;
  String doubanId;        // 实测可得，留给未来扩展
  List<MovieRoute> routes;
}

class MovieRoute {
  String name;              // dytt / dyttm3u8 / 线路一
  List<MovieEpisode> episodes;
  bool get playable => episodes.any((e) => e.url.contains('.m3u8'));
}

class MovieEpisode {
  String title;   // "HD国语" / "第01集"
  String url;
}
```

### 4.3 Hive Box 新增

在 `lib/services/storage/storage.dart` 的 `GStorage` 中注册：

| Box | 类型 | 用途 |
|---|---|---|
| `movieSources` | `Box<MovieSource>` | 影视源配置 |
| `movieHistory` | `Box<MovieHistory>` | 观看历史与进度 |
| `movieCollectibles` | `Box<MovieCollectible>` | 影视收藏 |
| `movieDanmakuMatch` | `Box<MovieDanmakuMatch>` | 弹幕匹配记忆（含手动纠正） |

设置项复用现有 `_setting` Box，在 `settings_keys.dart` 新增 `SettingGroup.movie`。

### 4.4 弹幕匹配记忆

```dart
class MovieDanmakuMatch {
  String movieKey;      // "{sourceKey}:{vodId}"
  int episodeIndex;     // 第几集（电影固定 0）
  int danmakuEpisodeId; // 弹弹play episodeId
  String matchedTitle;  // 命中的番剧名（用于 UI 展示「当前弹幕来自《XXX》」）
  double score;         // 匹配得分
  bool manual;          // true = 用户手动指定，优先级最高，不会被自动匹配覆盖
  int updatedAt;
}
```

---

## 5. 模块详细设计

### 5.1 苹果CMS 客户端

`lib/request/apis/apple_cms_api.dart`

```dart
class AppleCmsApi {
  // 搜索：{api}?ac=videolist&wd={kw}&pg={page}
  static Future<CmsSearchPage> search(
    MovieSource source, String keyword, int page);

  // 详情（优先）：{api}?ac=videolist&ids={vodId}
  static Future<MovieDetail?> detail(MovieSource source, String vodId);

  // 详情（兜底）：抓 detail 页 HTML 解析
  static Future<MovieDetail?> detailFromHtml(MovieSource source, String vodId);
}
```

**要点**

- 走 Kazumi 现有 `DioFactory`，复用其代理设置与错误映射（`NetworkErrorMapper`）。
- 默认请求头：`User-Agent`（随机 UA，复用 `getRandomUA()`）、`Accept: application/json`；`source.detail` 非空时按域名补 `Referer`。
- 超时：搜索单源 8s（对齐 LibreTV 的 `SEARCH_SOURCE_TIMEOUT_MS`），详情 10s。
- `vod_play_from` 与 `vod_play_url` 按 `$$$` 切分后**按下标一一对应**，生成 `MovieRoute`；线路内按 `#` 切集，每集按 `$` 切「标题 / 地址」（`parts.length > 1 ? parts[1] : ''`，地址必须以 `http` 开头才收）。
- 详情接口失败时降级到 HTML 抓取（`detail` 非空才试）。
- **不引第三方 HTML 解析依赖**：Kazumi 已带 `html` 包，用它解析兜底页面。

### 5.2 聚合搜索服务

`lib/services/movie/movie_search_service.dart`

```
searchAll(keyword, {page, sources}) →
  1. 取 enabled == true 的源
  2. 并发请求（Future.wait + 单源 try/catch 隔离，参考 Kazumi SourceSheet 的并发范式）
  3. 每个源最多翻 min(pagecount, 5) 页（对齐 LibreTV SEARCH_MAX_PAGES）
  4. 汇聚 + 去重（key = sourceKey + vodId）
  5. 排序：精确命中优先 → 有评分优先 → 年份倒序
  6. 返回 SearchOutcome{ items, failures[] }
```

**UI 必须展示 `failures`**（哪个源超时/失败），不能让用户以为「搜不到就是没有」。这是 LibreTV 已经做的事，体验上很关键。

### 5.3 影视源管理

`lib/services/movie/movie_source_manager.dart` + `lib/pages/settings/movie/movie_source_settings.dart`

能力清单（对齐并略超 LibreTV）：

| 能力 | 说明 |
|---|---|
| 增 / 删 / 改 | 字段：名称、API 地址、详情地址（可选）、成人标记、启用开关 |
| 启用 / 停用 | 影响是否参与聚合搜索 |
| 拖拽排序 | 影响结果展示优先级 |
| 单源探活 | `?ac=videolist&wd=test&pg=1`，记录延迟，UI 显示「正常 120ms / 超时 / 失败」 |
| 批量导入 | ① LibreTV-SourceList JSON ② TVBOX 配置（仅取 `type:1` 的 CMS 直连） ③ Kazumi 现有 `kazumi://` 分享链接格式（复用 `plugin_import_parser.dart` 的解析范式） |
| 导出 | 生成 LibreTV-SourceList 格式，可直接分享给别人的 LibreTV |
| URL 订阅 | 填一个 JSON URL，拉取后合并（**在客户端解析，不走服务端**，因此不受 CORS 限制） |
| 内置源 | 预置 3~5 个实测可用的源，保证开箱可用（见 §8 R1） |

> 默认**内置源全部启用**，用户可关；自定义源默认启用。

### 5.4 播放上下文抽象

`lib/pages/video/video_playback_args.dart` 增加 `MovieVideoPlaybackArgs`（见 D3）。

`lib/pages/video/video_controller.dart` 改造：

```
init():
  switch (args) {
    OnlineVideoPlaybackArgs  → 现有逻辑（规则引擎 + WebView 嗅探）
    OfflineVideoPlaybackArgs → 现有逻辑（本地文件）
    MovieVideoPlaybackArgs   → 新增：
        - 跳过 WebView 嗅探，episode url 直接就是 m3u8
        - bangumiId 用合成的占位 id
        - httpHeaders 用该源的 UA / Referer
        - 剧集列表来自 args.episodes
  }
```

**关键改造点**：现有 `videoUrl()` / `queryRoads()` 这类方法里对 `currentPlugin`、`bangumiItem` 的依赖，需要按 args 类型短路。

### 5.5 弹幕控制器改造

`lib/pages/player/controller/player_danmaku_controller.dart`

现有入口：

```dart
Future<DanmakuLoadResult> fetchDanmaku(int bangumiId, String pluginName, int episode)
```

新增影视入口（**不破坏现有签名**）：

```dart
/// 影视：按标题自动匹配（受开关控制）
Future<DanmakuLoadResult> fetchMovieDanmaku({
  required String movieKey,     // "{sourceKey}:{vodId}"
  required String title,
  required String year,
  required String typeName,
  required int episodeIndex,
});
```

内部优先级：
1. **手动纠正记忆**（`movieDanmakuMatch` 中 `manual == true`）→ 直接用
2. **自动匹配记忆**（缓存命中且未过期）→ 直接用
3. **开关关闭** → 直接返回空，不发起网络请求
4. **自动匹配** → 走 §5.6 的匹配器，命中则写入记忆

### 5.6 弹幕自动匹配器（核心）

`lib/services/danmaku/movie_danmaku_matcher.dart` + `lib/utils/title_normalizer.dart`

#### 步骤 1｜标题清洗

苹果CMS 的标题噪声很多（实测 `vod_sub` 里就是 `流浪地球2(3D版) / The Wandering Earth Ⅱ`，`vod_remarks` 是 `HD国语`）。清洗规则：

```
输入 → 输出
"流浪地球2"                          → "流浪地球2"
"流浪地球2(3D版)"                    → "流浪地球2"
"【高清】甄嬛传 第1季"                → "甄嬛传 第1季"
"庆余年 第二季 国语"                  → "庆余年 第二季"
"让子弹飞[国语]"                      → "让子弹飞"
```

规则（按序执行）：

1. 去掉括号及其内容：`（）() 【】[] 《》〈〉`
2. 去掉版本/画质词：`国语|粤语|英语|HD|BD|4K|1080P|720P|2160P|高清|超清|完整版|未删减|加长版|导演剪辑版|特效字幕|中字|双语|国配|原声`
3. 保留季/集信息（**不能删**，否则第二季会匹配到第一季）
4. 全角转半角，去首尾空白与连续空格
5. 小写化（用于比较）

#### 步骤 2｜检索

```dart
final res = await DanmakuApi.searchAnimes(cleanedTitle);   // 已有，直接用
```

#### 步骤 3｜打分

对每个候选计算：

```
score = 0.60 * titleSim
      + 0.25 * yearMatch
      + 0.15 * typeMatch
```

| 因子 | 计算 |
|---|---|
| `titleSim` | 归一化编辑距离：`1 - levenshtein(a, b) / max(len(a), len(b))`；一方是另一方子串时直接给 0.95 |
| `yearMatch` | 候选标题含年份 == `vod_year` → 1.0；含不同年份 → 0.0；不含年份 → 0.5（中性） |
| `typeMatch` | `typeName` 含「片」且候选 `typeDescription` 含「电影」→ 1.0；其余组合按类别对齐给 0.5~0.8 |

阈值：`score < 0.55` 视为未命中 → **不自动加载弹幕**，静默降级（避免给用户匹配错弹幕，比没弹幕更糟）。

#### 步骤 4｜分集对齐

```
if (候选 episodes.length == 1 && vod_total == 0)  → 电影，用 episodes[0]
else if (episodeIndex < episodes.length)          → episodes[episodeIndex]      // 0-based
else                                              → episodes.last                 // 兜底
```

> 剧集名称匹配（如「第01集」vs「第1话」）作为**二期增强**：先用下标对齐，跑通后再加名称归一化比对。

#### 步骤 5｜记忆写回

命中后写入 `movieDanmakuMatch`。用户手动纠正时覆盖并置 `manual = true`。

#### 匹配质量的可观测性

匹配结果要在 UI 上**可见**：播放器弹幕按钮旁的小字提示「弹幕来自《流浪地球2》(匹配度 92%)」，点进去可手动改（复用已有的 `danmaku_source_sheet.dart`）。这是「自动」能被信任的前提。

### 5.7 弹幕开关

新增设置项：

| Key | 类型 | 默认 | 说明 |
|---|---|---|---|
| `movieDanmakuAutoMatch` | bool | **false** | 影视弹幕自动检索并加载。默认关，由用户决定 |
| `movieDanmakuAutoMatchThreshold` | double | 0.55 | 自动匹配的最低得分 |
| `movieDanmakuShowSourceToast` | bool | true | 是否提示「弹幕来自《XXX》」 |

位置：设置 → 弹幕设置 → 新增「影视弹幕」分组；同时在播放器弹幕菜单里放一个快捷开关。

> **默认关闭**是刻意的：用户明确说「这个可以另做一个开关，由用户选择打不打开」。首次进影视播放页给一次一次性引导提示。

### 5.8 影视 UI

```
lib/pages/movie/
├── movie_module.dart          # 路由：/tab/movie、/tab/movie/search、/tab/movie/detail
├── movie_page.dart            # Tab 首页：搜索框 + 搜索历史 + 源筛选
├── movie_controller.dart      # MobX 控制器
├── movie_result_grid.dart     # 结果网格（封面 + 标题 + 源标签 + 备注）
├── movie_detail_page.dart     # 详情：元数据 + 简介 + 线路选择 + 剧集网格
├── movie_route_selector.dart  # 线路选择器
├── movie_episode_grid.dart    # 剧集网格
└── movie_source_chips.dart    # 单源结果筛选
```

**详情页布局**

```
┌──────────────────────────────────────────┐
│  [封面]  流浪地球2                        │
│          2023 · 大陆 · 科幻片 · 8.3       │
│          HD国语                           │
│          导演：郭帆                       │
│          主演：吴京 / 刘德华 / 李雪健 …    │
│          [收藏]        [播放]             │
├──────────────────────────────────────────┤
│  线路：[dyttm3u8 ✓] [dytt]                │  ← 默认选可播线路，不可播的打标记
├──────────────────────────────────────────┤
│  选集：[HD国语]                            │
├──────────────────────────────────────────┤
│  简介：……（可展开）                        │
└──────────────────────────────────────────┘
```

**注意**：默认选中「可播线路」（D6 排序后的第一条），避免用户点了播不了再回头找。

### 5.9 影视收藏与历史

- 历史：复用 Hive，记录 `movieKey / 集号 / 播放位置 / 时间`，进播放页自动续播。
- 收藏：影视 Tab 内一个二级入口（不放到底部导航，避免导航膨胀）。
- **不做**与 WebDAV 的影视同步（一期），避免影响现有番剧同步逻辑。

---

## 6. 对 Kazumi 现有文件的改造清单

### 6.1 新增文件

| 路径 | 说明 |
|---|---|
| `lib/modules/movie/movie_source.dart` | 源模型 |
| `lib/modules/movie/movie_item.dart` | 搜索结果模型 |
| `lib/modules/movie/movie_detail.dart` | 详情 / 线路 / 剧集模型 |
| `lib/modules/movie/movie_history.dart` | 历史模型 |
| `lib/modules/movie/movie_collectible.dart` | 收藏模型 |
| `lib/modules/movie/movie_danmaku_match.dart` | 弹幕匹配记忆模型 |
| `lib/request/apis/apple_cms_api.dart` | 苹果CMS 协议客户端 |
| `lib/services/movie/movie_search_service.dart` | 聚合搜索 |
| `lib/services/movie/movie_source_manager.dart` | 源管理 + 导入导出 + 订阅 |
| `lib/services/movie/movie_history_service.dart` | 历史与进度 |
| `lib/services/danmaku/movie_danmaku_matcher.dart` | 弹幕匹配器 |
| `lib/utils/title_normalizer.dart` | 标题清洗 + 相似度 |
| `lib/pages/movie/**` | §5.8 全部页面 |
| `lib/pages/settings/movie/movie_source_settings.dart` | 源管理设置页 |
| `lib/pages/settings/movie/movie_danmaku_settings.dart` | 影视弹幕设置页 |

### 6.2 修改文件

| 路径 | 改动 | 风险 |
|---|---|---|
| `lib/pages/video/video_playback_args.dart` | 加 `MovieVideoPlaybackArgs` | 低（sealed class 扩展） |
| `lib/pages/video/video_controller.dart` | 按 args 类型分派；影视跳过 WebView 解析 | **中**（核心链路，需回归） |
| `lib/pages/player/controller/player_danmaku_controller.dart` | 加 `fetchMovieDanmaku()` | 低（纯新增方法） |
| `lib/pages/menu/menu.dart` | `_bottomMenu` + `_sideMenu` 各加一个 destination；path 表加一项 | **中**（Tab index 位移） |
| `lib/pages/index_module.dart` | `tabModule` 注册 `movieModule` | 低 |
| `lib/pages/router.dart` | 路由挂载 | 低 |
| `lib/core_module.dart` | 注入 `MovieController` / `MovieSourceManager` 等单例 | 低 |
| `lib/services/storage/storage.dart` | 注册 4 个新 Box | 低 |
| `lib/services/storage/settings_keys.dart` | 加 `SettingGroup.movie` + 4 个 key | 低 |
| `lib/hive_registrar.g.dart` | 重新生成（`dart run build_runner build`） | 低（自动） |
| `lib/pages/settings/settings_page.dart` | 加「影视源管理」「影视弹幕」入口 | 低 |
| `lib/pages/settings/interface_settings.dart` | 默认启动页选项加「影视」 | 低 |

> **Tab index 位移提醒**：新 Tab 插在「追番」与「我的」之间，「我的」的 index 由 3 变 4。已确认 `_handleSystemBack` 只判断 `!= 0`，默认启动页设置按**路径**（`/tab/timeline/`）而非 index，所以不受影响。但仍需回归 Tab 切换与横竖屏两套菜单。

---

## 7. 实施计划

| 阶段 | 内容 | 产出 |
|---|---|---|
| **P0 环境** | 装 Flutter 3.47.5 + 配国内镜像；`flutter doctor`；编译跑通**未改动的原版** | 可编译的基线，确认改造前一切正常 |
| **P1 基础层** | 数据模型 + Hive Box + 苹果CMS 客户端 + 聚合搜索（**纯 Dart，可先用单元测试验证，不依赖 UI**） | 命令行能搜到片、能解析出可播 m3u8 |
| **P2 源管理** | 源 CRUD UI + 探活 + 导入导出 + 订阅 | 设置页可管理源 |
| **P3 影视 UI** | Tab + 搜索页 + 详情页 | 能浏览，还不能播 |
| **P4 播放打通** | `MovieVideoPlaybackArgs` + `VideoPageController` 分派 + 页面跳转 | **能完整看片** |
| **P5 弹幕** | 匹配器 + 设置开关 + UI 提示 + 纠正入口 | 影视有弹幕，可开关 |
| **P6 打磨** | 收藏、历史续播、源排序、错误提示、性能（封面懒加载 / 结果分页） | 完整体验 |
| **P7 打包** | Windows（`flutter build windows`）+ Android（`build apk --split-per-abi`）；补弹幕凭据注入 | 两个平台的产物 |

**P1 的关键提醒**：苹果CMS 客户端与匹配器都是**纯逻辑，不依赖 Flutter UI**。建议先写成可单测的类，用 `dart test` 或直接跑 `dart run` 脚本验证真实源，确认解析正确后再接 UI。这能避免「UI 写完了发现数据不对」的返工。

---

## 8. 风险与应对

| # | 风险 | 影响 | 应对 |
|---|---|---|---|
| R1 | **影视源随时可能失效**（实测三源已挂两个） | 高 | ① 内置 3~5 个源并定期实测筛选 ② 聚合搜索展示 `failures` ③ 用户可自行添加 ④ 源管理页有探活按钮 |
| R2 | **弹弹play 凭据缺失 → 弹幕全失效**（含番剧） | **高（阻塞）** | 见附录 A。在拿到之前，代码把凭据做成可配置项（`--dart-define` 或设置页填写），不硬编码 |
| R3 | 影视弹幕匹配错（匹配到同名不同片） | 中 | ① 打分阈值 0.55 ② 年份加权 ③ UI 明示弹幕来源 ④ 一键手动纠正 + 记忆 |
| R4 | 苹果CMS 源响应格式不完全一致（各家魔改） | 中 | 所有字段解析都做**空值容错**；`vod_play_url` 解析失败时降级 HTML 抓取 |
| R5 | 部分源走 Cloudflare 挑战 | 中 | dio 带完整浏览器请求头；仍失败则标记该源不可用，不阻塞其他源 |
| R6 | 修改 `VideoPageController` 影响现有番剧播放 | **高** | P0 先建立可运行的基线；改完对番剧链路（在线 + 离线 + 弹幕）做完整回归 |
| R7 | 授权风险 | 低 | 聚合第三方采集站用于**个人**使用；若公开分发，需保留 Kazumi 的 GPL-3.0 与 LibreTV 的 AGPL-3.0 声明，组合作品整体按 AGPL 处理 |
| R8 | 苹果CMS 源含成人内容 | 中 | 沿用 LibreTV 的 `isAdult` 标记 + 全局过滤开关；默认开启过滤 |

---

## 附录 A｜弹弹play AppId 申请步骤

> 这是 R2 的解法，也是整个方案里**唯一的外部依赖**。

**申请入口**

- 开发者中心：**https://dev.dandanplay.com**
- 官方文档：https://doc.dandanplay.com/open/
- 备用联系：邮件 `kaedei@dandanplay.net`（标题 `弹弹play开放弹幕网络咨询`，或按另一份指南用的 `弹弹play开放平台申请`）

**步骤**

1. 访问 **https://dev.dandanplay.com** ，注册账号
   - ⚠️ 官方明确提示「网站部分组件可能需要科学上网才能正常显示」，准备好网络环境
2. 完善**开发者资料**，通过**邮件验证**
3. 在【应用管理】页 **创建应用** 并**提交审核**
   - 应用类型选**客户端应用**（桌面 / 移动端），对应**签名验证模式**
4. 等待审核。官方说「收到申请后尽快处理」，会通过**邮件 + 站内留言**通知进展
5. 审核通过后获得 **1 个 AppId + 2 个 AppSecret**
   - 务必妥善保管，官方明确：泄露或滥用会被**立即停用**

**接入方式**

- 客户端应用建议用**签名验证模式**，请求头带三个字段：
  - `X-AppId`
  - `X-Timestamp`（当前 Unix 时间戳，秒）
  - `X-Signature`
- 签名算法：
  ```
  X-Signature = base64( sha256( AppId + Timestamp + Path + AppSecret ) )
  ```
  其中 `Path` 是 API 路径（以 `/` 开头、**不含域名和查询参数**，建议全小写），例如
  `https://api.dandanplay.net/api/v2/comment/123450001?withRelated=true` → `Path = /api/v2/comment/123450001`

  > Kazumi 已经实现好了这套签名，在 `lib/utils/crypto.dart` 的 `generateDandanSignature()`。**只需把凭据喂进去，不用重写。**

**拿到之后怎么用**

按现有 CI 的做法传编译参数即可，源码无需改动：

```bash
flutter build windows \
  --dart-define=DANDANAPI_APPID=<你的AppId> \
  --dart-define=DANDANAPI_KEY=<你的AppSecret>
```

> 也可以顺手做成设置页可填、存 Hive 的形态，方便换 key 不用重新编译。设计上倾向后者，但**要注意 AppSecret 落到本地文件的安全性问题**——个人自用问题不大。

**如果申请不下来**

备选方案（按推荐度）：

1. 自建弹幕聚合服务，对外统一协议 —— 成本高，且弹幕数据源本身还是得解决
2. 只做弹幕**展示与手动检索**，不做自动匹配；凭据留空，功能对用户可见但提示「需配置弹幕服务」
3. 放弃影视弹幕，只保留番剧弹幕（但番剧弹幕同样受凭据影响）

---

## 附录 B｜苹果CMS 接口协议速查

**搜索**

```
GET {api}?ac=videolist&wd={关键词}&pg={页码}

{
  "code": 1, "msg": "数据列表",
  "page": "1", "pagecount": 1, "limit": "20", "total": 4,
  "list": [
    {
      "vod_id": 40510,
      "vod_name": "流浪地球2",
      "vod_pic": "https://.../xxx.jpg",
      "type_name": "科幻片",
      "vod_year": "2023",
      "vod_area": "大陆",
      "vod_remarks": "HD国语",
      "vod_score": "8.3",
      "vod_douban_id": "35267208",
      "vod_actor": "吴京,刘德华,李雪健,...",
      "vod_director": "郭帆",
      "vod_content": "<p>…简介 HTML…</p>",
      "vod_play_from": "dytt$$$dyttm3u8",
      "vod_play_url": "HD国语$https://.../share/xxx$$$HD国语$https://.../index.m3u8"
    }
  ]
}
```

**详情**

```
GET {api}?ac=videolist&ids={vodId}      → 结构同上，list 只含一条
```

**播放地址编码**

```
vod_play_from = 线路名1 $$$ 线路名2 $$$ ...
vod_play_url  = 线路1内容 $$$ 线路2内容 $$$ ...
                线路N内容 = 集标题1 $ 地址1 # 集标题2 $ 地址2 # ...
```

- 线路与 `vod_play_from` **按下标对应**
- 集标题与地址按 `$` 切分（`parts.length > 1 ? parts[1] : ''`）
- **地址必须 `http` 开头**才收集（过滤空值）
- ⚠️ **`/share/` 形态是网页中转页，播放器播不了**；优先选含 `.m3u8` 的线路

**分页**

响应含 `pagecount`；`page` 从 1 开始。

---

## 附录 C｜待确认事项

1. **产品名**：目录叫 `kazutv`，但对外叫什么？（本方案暂用「Kazutv」占位）
2. **内置源清单**：需要实测筛选后确定 3~5 个稳定源，内置进去。
3. **弹幕凭据落地形态**：编译期注入（`--dart-define`）vs 运行时设置页填写？前者安全、后者灵活。
4. **是否要影视的 WebDAV 同步**：一期不做，二期看需要。
