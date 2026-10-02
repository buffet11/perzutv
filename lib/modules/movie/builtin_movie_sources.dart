import 'package:kazutv/modules/movie/movie_source.dart';

/// 内置影视源。
///
/// 全部为**实测可用**，按延迟排序。源站存活会变，所以：
///   - 每个源都能在设置里单独停用；
///   - 探活失败只影响该源，不会拖垮整体搜索（见 MovieSearchService）；
///   - 用户可自行增删，内置源只是「保证开箱可用」的兜底，不是硬编码依赖。
///
/// 实测备注（2026-10-01 探测，搜索「流浪地球」）：
///   - 电影天堂有 `dytt`（网页播放页）和 `dyttm3u8`（直链）两条线路；
///   - 其余源基本也都有 `xxxm3u8`（直链）+ `xxx云`（网页播放页）两条线路。
///     网页线路现在由 `WebStreamScraper` 解析（见 services/movie/），
///     所以它们不再是废线路。
const List<({String key, String name, String api})> _builtin = [
  (key: 'builtin_dytt', name: '电影天堂', api: 'http://caiji.dyttzyapi.com'),
  (key: 'builtin_360', name: '360资源', api: 'https://360zy.com'),
  (key: 'builtin_jinying', name: '金鹰资源', api: 'https://jyzyapi.com'),
  (key: 'builtin_lzi', name: '量子资源', api: 'https://cj.lziapi.com'),
  (key: 'builtin_huya', name: '虎牙资源', api: 'https://www.huyaapi.com'),
];

/// 内置的**高画质**源 —— 默认不参与搜索，由设置里的总开关控制。
///
/// 2026-10-02 实测（探测 40 个候选源，13 个存活，再对每源 × 6 部片
/// 抓 m3u8 master 里的 `RESOLUTION` 与 `BANDWIDTH`；详见
/// `tools/probe_hq_sources.py` / `tools/probe_hq_quality.py`）：
///
/// | 源 | 实测最高 | 6 部片中达到 1080p 的部数 | 搜索延迟 |
/// |---|---|---|---|
/// | 光速资源 | 1080p | **6 / 6** | 2.4 s |
/// | 最大资源 | 1280p | 3 / 6 | 2.4 s |
/// | 非凡资源 | 1280p | 2 / 6 | 0.8 s |
///
/// 结论：**只有光速资源是稳定 1080p**，另外两个是「部分内容能到 1080p」。
/// 所以这一组叫「高画质候选」更准确 —— 开关的说明文案也是这么写的，不夸大。
///
/// 落选的：量子资源实测**稳定只有 608p**（它在普通组里，胜在延迟最低）；
/// 魔都资源能到 1280p 但搜索要 8 s，太慢，不进内置。
///
/// 为什么默认关闭：它们是「更慢、更费流量」的源，普通用户不该为此买单；
/// 想看高画质的用户主动打开。播放器侧不用做任何事 —— mpv 的 `hls-bitrate`
/// 默认是 `INT_MAX`（见 mpv 源码 `options.c` 的 `.hls_bitrate = INT_MAX`），
/// 本来就会挑码率最高的那一路。
const List<({String key, String name, String api})> _builtinHighQuality = [
  (key: 'builtin_hq_gs', name: '光速资源', api: 'https://api.guangsuapi.com'),
  (key: 'builtin_hq_zuid', name: '最大资源', api: 'https://api.zuidapi.com'),
  (key: 'builtin_hq_ffzy', name: '非凡资源', api: 'http://cj.ffzyapi.com'),
];

/// 构造内置源列表（每次返回新实例，便于调用方直接改 enabled / order）。
///
/// 高画质源一并返回，但带 `highQuality: true` —— 是否真正参与搜索由
/// `MovieSourceManager.enabled()` 结合设置里的开关决定。
List<MovieSource> builtinMovieSources() {
  final out = <MovieSource>[];
  for (var i = 0; i < _builtin.length; i++) {
    out.add(MovieSource(
      key: _builtin[i].key,
      name: _builtin[i].name,
      api: _builtin[i].api,
      order: i,
    ));
  }
  for (var i = 0; i < _builtinHighQuality.length; i++) {
    out.add(MovieSource(
      key: _builtinHighQuality[i].key,
      name: _builtinHighQuality[i].name,
      api: _builtinHighQuality[i].api,
      highQuality: true,
      order: out.length,
    ));
  }
  return out;
}

/// 内置源的 key 集合，用于判断某个源是不是内置的（影响能否删除）。
const Set<String> builtinMovieSourceKeys = {
  'builtin_dytt',
  'builtin_360',
  'builtin_jinying',
  'builtin_lzi',
  'builtin_huya',
  'builtin_hq_gs',
  'builtin_hq_zuid',
  'builtin_hq_ffzy',
};

/// 内置高画质源的 key 集合。
const Set<String> builtinHighQualitySourceKeys = {
  'builtin_hq_gs',
  'builtin_hq_zuid',
  'builtin_hq_ffzy',
};
