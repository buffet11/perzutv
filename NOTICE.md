# NOTICE — 第三方组件、上游项目与致谢

本文件记录 Perzutv 所依赖、参考与派生的第三方项目，以及相应的许可证义务。
本文件的全部内容均需保留，不得删改。

---

## 1. 本作品的性质

**Perzutv** 是基于 [Kazumi](https://github.com/Predidit/Kazumi) 的二次开发分支（fork）。

- 上游项目：Kazumi
- 上游作者：Predidit 及[全体贡献者](https://github.com/Predidit/Kazumi/graphs/contributors)
- 上游许可证：GNU General Public License v3.0
- 本分支修改起始日期：**2026-10-01**

依据 GNU GPL-3.0 第 5(a) 条，本作品已在 [README.md](README.md) 与本文件中
显著声明其为经过修改的版本，并注明了修改日期。

Perzutv 与上游作者之间**不存在隶属、赞助或背书关系**。上游项目名与作者署名
不得被用于暗示对本分支的认可。

---

## 2. 参考与派生项目

### LibreTV

- 项目：<https://github.com/LibreSpark/LibreTV>
- 许可证：GNU Affero General Public License v3.0 (AGPL-3.0)

Perzutv 的影视内容聚合能力，基于对 LibreTV 所实现的**苹果CMS（Apple CMS）采集接口协议**
的理解，使用 Dart 重新实现。协议本身为公开事实，实现代码为独立编写，
但设计思路与边界条件处理参考了 LibreTV 的实现，故在此致谢并声明。

> 依据 AGPL-3.0 与 GPL-3.0 的兼容性，**组合作品整体按 AGPL-3.0 发布**。
> 若你分发本软件，需同时提供完整的对应源码。

---

## 3. 上游 Kazumi 的致谢名单

以下为上游项目的致谢内容，予以完整保留：

特别感谢 [XpathSelector](https://github.com/simonkimi/xpath_selector) 这个优秀的项目是本项目的基石。

特别感谢 [弹弹play](https://www.dandanplay.com/) 本项目使用了 弹弹play开放平台 以提供弹幕交互。

特别感谢 [Bangumi](https://bangumi.tv/) 本项目使用了 Bangumi 开放 API 以提供番剧元数据。

特别感谢 [Anime4K](https://github.com/bloc97/Anime4K) 本项目使用 Anime4K 进行实时超分。

特别感谢 [SyncPlay](https://github.com/Syncplay/syncplay) 本项目使用 SyncPlay 协议并通过 SyncPlay 公共服务器实现一起看功能。

特别感谢 [所有贡献者](https://github.com/Predidit/Kazumi/graphs/contributors) 本项目因为你们变得更好。

特别感谢 [trace.moe](https://trace.moe) 本项目使用了 trace.moe 提供的图片识别番剧功能。

感谢 [media-kit](https://github.com/media-kit/media-kit) 本项目跨平台媒体播放能力来自 media-kit。

感谢 [avbuild](https://github.com/wang-bin/avbuild) 本项目使用了来自 avbuild 的树外补丁实现非标准视频流播放。

感谢 [hive](https://github.com/isar/hive) 本项目持久化储存能力来自 hive。

---

## 4. 外部服务

本软件在运行时会访问以下第三方服务。这些服务由第三方独立运营，
本软件不对其可用性、内容合法性或数据准确性作任何担保。

| 服务 | 用途 | 说明 |
|---|---|---|
| [弹弹play 开放弹幕网络](https://doc.dandanplay.net/open/) | 弹幕收发、番剧搜索、番剧信息 | **需自行申请 AppId / AppSecret**，使用需遵守其[使用规定](https://doc.dandanplay.net/open/) |
| [Bangumi](https://bangumi.tv/) | 番剧元数据 | 遵循其开放 API 使用条款 |
| [trace.moe](https://trace.moe) | 以图搜番 | |
| [哔哩哔哩](https://www.bilibili.com/) | 「正版番剧」功能的官方外链播放器与公开元数据接口 | 仅嵌入 B 站官方播放器页面，不解析、不转存视频流；需登录或会员的内容由 B 站侧判定 |
| 各类第三方影视采集接口 | 影视内容索引 | 由用户自行配置；本软件不内置、不托管任何此类内容 |

---

## 5. 许可证全文

- 本作品：GNU Affero General Public License v3.0（见 [LICENSE](LICENSE)）
- 上游 Kazumi：GNU General Public License v3.0
- LibreTV：GNU Affero General Public License v3.0

各依赖包的许可证全文可在构建产物与各包源仓库中查阅。
