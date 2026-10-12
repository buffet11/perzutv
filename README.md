# Perzutv

> 动漫 + 影视，一个播放器

Perzutv 是 [**Kazumi**](https://github.com/Predidit/Kazumi) 的二次开发分支。保留上游的番剧采集、
播放与弹幕能力，在其之上新增影视（电影 / 剧集 / 综艺）聚合播放、动漫分区浏览，以及把
**B 站官方外链播放器**接进应用内的正版观看入口。已增强弹幕的自动匹配。

> **本仓库是 Kazumi 的修改版本，非官方版本，与上游作者无隶属关系。**
> 修改起始日期 **2026-10-01**（依 GPL-3.0 §5(a) 声明本作品已被修改）。
> 许可证与致谢见 [LICENSE](LICENSE)、[NOTICE.md](NOTICE.md)。

## 状态

早期开发中 —— 基于上游源码起步，二开功能实现中。下表未勾选的即尚未实现。

## 功能

**继承自上游**：XPath 规则番剧采集与播放、弹幕（[弹弹play](https://doc.dandanplay.net/open/)）、
规则编辑器与规则商店、离线下载、观看历史、追番收藏、WebDAV 同步、DLNA 投屏、
一起看（SyncPlay）、Anime4K 实时超分。

**二开新增（规划中）**：

- [ ] 影视模块：苹果CMS 协议的电影 / 剧集 / 综艺聚合搜索与播放
- [ ] 自定义影视源管理：增删改、启用停用、探活测速、订阅导入导出
- [ ] 影视弹幕**自动检索 + 自动加载**（独立开关，默认关闭）
- [ ] 弹幕匹配纠错：手动指定后记住选择，下次直接命中
- [ ] 影视收藏与观看历史续播
- [x] **正版番剧**：应用内加载 B 站官方外链播放器。粘贴链接 / BV 号 / 剧集号即可播放，
  整季链接会列出选集；**只嵌入官方播放器、不解析视频流**，解码与鉴权都在 B 站侧完成，
  因此不占用本机解码资源（B 站侧需要登录或会员的内容，请用系统浏览器打开观看）。
  另有画质档位（关闭 / 流畅 / 标准 / 高清）与**卡顿自动降档** —— 渲染帧率持续跟不上
  视频帧率时会自动降一档并提示，避免核显设备卡到没法看。

设计细节见 [`docs/Perzutv-融合设计方案.md`](docs/Perzutv-融合设计方案.md)。

## 平台

Android 10+ · Windows 10+ · macOS 10.15+ · Linux（实验性）· iOS 13+（需侧载）

## 构建

需要 Flutter **3.47.5** 及以上，以及 Visual Studio（含 C++ 桌面开发工作负载）。

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # 生成 MobX / Hive 代码
flutter build windows                                      # 或 flutter build apk --split-per-abi
```

Windows 下可直接双击 **`build.bat`**，它会依次完成上面三步并打印产物路径。
`tools/` 里另有两个小工具：`hooks_prebuilt.py` 用于预置 native assets 钩子需要下载的
预编译包（国内直连会超时或龟速），`check_pipe_support.py` 用于自检运行环境。

国内网络建议把 `PUB_HOSTED_URL`、`FLUTTER_STORAGE_BASE_URL` 指向 `*.flutter-io.cn` 镜像，
可显著加快依赖拉取。

### 弹幕凭据

弹弹play 的接口需要 AppId / AppSecret 签名，**未配置时弹幕不可用**。
到[开发者中心](https://dev.dandanplay.com)免费申请（需审核），构建时注入：

```bash
flutter build windows \
  --dart-define=DANDANAPI_APPID=<AppId> \
  --dart-define=DANDANAPI_KEY=<AppSecret>
```

也可以把这两项写进项目根目录的 `.perzutv_build_defines.env`（模板见
`.perzutv_build_defines.env.example`），`build.bat` 会自动读取。该文件已被 gitignore。

> 凭据会被编译进客户端二进制，请勿提交到公开仓库。

### 由 CI 密钥驱动的功能（自行构建时注意）

上游 Kazumi 的一部分能力，密钥是通过 `--dart-define` 由 GitHub Actions 从
**上游自己的** Secrets 注入的，源码里是空串。所谓「自己编译之后某功能坏了」，
绝大多数都是这个原因，而不是代码问题：

| 功能 | 缺什么 | 自行构建时怎么办 |
|---|---|---|
| 弹幕 | 弹弹play 的 AppId / AppSecret | 申请自己的（见上一节），或用 `--dart-define` 传入。**没有就完全没有弹幕** |
| 番剧条目加速的「镜像接口」 | 镜像签名密钥 `KAZUMI_APPID` / `KAZUMI_KEY`（**上游私有，无法申请**） | 不用管：程序检测到没有凭据会**自动改用「加密握手」(ECH)** |

第二条展开说一句，因为它的失败现象极具误导性：镜像对搜索与评论要求
`X-Signature`，没有密钥时服务端返回 `401 invalid request signature`，而这个异常
在调用处被吞掉、只写日志，界面上表现为「**没有找到番剧**」——看起来像这部番不存在。
所以本仓库在设置 → 网络设置里，把「镜像接口」标注为「本构建无签名凭据，会自动
改用加密握手」，并在搜索失败时明确给出错误提示与「加速设置」入口（而不是伪装成
「没有找到」）。

## 免责与隐私

仅供学习与技术研究。视频内容均来自第三方接口，本项目不存储、不制作、不托管任何内容，
也不对第三方内容的合法性负责；使用时请遵守所在地法律法规，产生的缓存数据请在 24 小时内清除。
不收集任何用户数据，不含遥测组件。

## 许可证

[GNU General Public License v3.0](LICENSE)。

本作品包含基于 [LibreTV](https://github.com/LibreSpark/LibreTV)（AGPL-3.0）的协议实现重写代码，
组合作品整体按 AGPL-3.0 发布。
