// 影视地址解析的回归验证。
//
// 覆盖三块纯逻辑：
//   1. 从网页 HTML 抽播放地址（WebStreamScraper 的核心）
//   2. 从解析接口的响应里抽播放地址（ParseSourceClient 的核心）
//   3. 线路的可用性排序（MovieDetail.availableRoutes）
//
// 用到的样例都是从真实响应里截下来的 —— 见 tools/probe_url_shapes.py 与
// tools/probe_hq_quality.py 的输出。
//
// 为什么单独一个脚本：`dart analyze` / `flutter test` 在本机跑不起来
// （见 git 历史里 native_toolchain_c 那条），而这几个函数不碰网络、
// 也不依赖 Flutter，用 `dart run` 就能直接验。
//
//   cd app
//   dart run tools/probe_movie_resolve.dart            # 离线部分
//   dart run tools/probe_movie_resolve.dart --live     # 再加联网自检
//
// `--live` 会拿几个真实的「云线路」播放页走一遍：抓页面 -> 用**同一份**
// 抽取逻辑找候选 -> 校验候选是否真的返回 `#EXTM3U`。页面地址是 2026-10-02
// 实测可用的，源站会变，失败不代表代码有问题（用例本身可能过期了）。

import 'dart:convert';
import 'dart:io';

import 'package:kazutv/modules/movie/movie_detail.dart';
import 'package:kazutv/modules/movie/parse_source.dart';
import 'package:kazutv/services/movie/movie_stream_parsing.dart';

int _passed = 0;
int _failed = 0;

void check(String label, bool ok, [String detail = '']) {
  if (ok) {
    _passed++;
    stdout.writeln('  ✓ $label');
  } else {
    _failed++;
    stdout.writeln('  ✗ $label${detail.isEmpty ? '' : '  ($detail)'}');
  }
}

void checkEq(String label, Object? actual, Object? expected) {
  check(label, actual == expected, '实际=$actual 期望=$expected');
}

void section(String title) {
  stdout.writeln();
  stdout.writeln('── $title ' + '─' * (60 - title.length));
}

// ---------------------------------------------------------------- 样例

/// 光速资源的播放页（绝对地址形态）。真实响应 1591 字节。
const _guangsuPage = '''
<!DOCTYPE html>
<html><head><title>播放</title></head>
<body>
<script>
  var player = {
    "vid": "e1wwYPGb",
    "url": "https://v.gsuus.com/play/e1wwYPGb/index.m3u8"
  };
</script>
</body></html>
''';

/// 电影天堂的分享页（根相对路径 + 查询串形态）。真实响应 1162 字节。
const _dyttPage = r'''
<!DOCTYPE html>
<html><head><meta charset="utf-8"></head>
<body>
<script>
        const url = "/20250505/5821_926c11cc/index.m3u8?sign=41d7f8d44d49f792ddd3bdd209791cf0";
        const pic = "/20250505/5821_926c11cc/1.jpg";
        const resumeKey = "926c11cc055de9b";
</script>
</body></html>
''';

/// 转义斜杠形态（不少站点的 JS 里是 `https:\/\/...`）。
const _escapedSlashPage = r'''
<script>var u="https:\/\/cdn.example.com\/v\/movie\/index.m3u8?auth=abc";</script>
''';

void main(List<String> args) async {
  stdout.writeln('影视地址解析 · 回归验证');

  offlineChecks();

  if (args.contains('--live')) {
    await liveChecks();
  }

  // ---------------------------------------------------------------- 汇总
  stdout.writeln();
  stdout.writeln('─' * 64);
  stdout.writeln('通过 $_passed，失败 $_failed');
  if (_failed > 0) {
    stdout.writeln('有失败项 —— 上面带 ✗ 的行就是。');
    exitCode = 1;
  } else {
    stdout.writeln('全部通过。');
  }
}

// ---------------------------------------------------------------- 联网自检

/// 2026-10-02 实测可用的「云线路」播放页。
///
/// 左边是源名+线路名，右边是播放页地址。`/play/` 和 `/share/` 两种形态都有，
/// 正好覆盖「绝对地址」和「根相对路径」两类抽取。
const _liveCases = <String, String>{
  '光速资源 /play（绝对地址形态）': 'https://v.gsuus.com/play/e1wwYPGb',
  '极速资源 /play': 'https://vv.jisuzyv.com/play/e5yylXAe',
  '红牛资源 /play': 'https://hn.bfvvs.com/play/eZ66wN8e',
  '金鹰资源 /play': 'https://hd.kuktxu.com/play/e311jP9b',
  '虎牙资源 /play': 'https://1080p.huyall.com/play/e311jP9b',
  '豪华资源 /play': 'https://play.hhuus.com/play/b4xxkPkb',
  '电影天堂 /share（根相对路径形态）':
      'https://vip.dytt-live.com/share/926c11cc055de9b8d697b6a587d40c4d',
  '量子资源 /share':
      'https://vip.lzcdn2.com/share/15b3342aa0abd5176b93d68ddf95e3ce',
  '非凡资源 /share（已知拿不到）':
      'https://vip.ffzy-play8.com/share/b9e4ce50f6c1ba80d31aa4826948a5a6',
};

Future<void> liveChecks() async {
  section('6. 联网自检：真实播放页 -> 可播地址');

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 12)
    ..badCertificateCallback = (cert, host, port) => true;

  for (final entry in _liveCases.entries) {
    final pageUrl = entry.value;
    try {
      final html = await _fetchText(client, pageUrl);
      if (html == null || html.isEmpty) {
        check('${entry.key} —— 页面拿不到', false, '空响应');
        continue;
      }

      final candidates = StreamParsing.extractCandidates(html, pageUrl);
      if (candidates.isEmpty) {
        check('${entry.key} —— 页面里没有 m3u8 候选', false, '${html.length} 字节');
        continue;
      }

      // 逐个校验，和 WebStreamScraper 的做法一致
      String? hit;
      for (final c in candidates) {
        if (await _isHls(client, c)) {
          hit = c;
          break;
        }
      }

      if (hit == null) {
        check('${entry.key} —— 候选都不可播', false,
            '候选 ${candidates.length} 个');
      } else {
        check('${entry.key}', true);
        stdout.writeln('      -> $hit');
      }
    } catch (e) {
      check('${entry.key}', false, '$e');
    }
  }

  client.close(force: true);
}

Future<String?> _fetchText(HttpClient client, String url) async {
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader,
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36');
    request.headers.set(HttpHeaders.acceptHeader, 'text/html,*/*');
    final response = await request.close();
    final bytes = await response.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    return utf8.decode(bytes, allowMalformed: true);
  } catch (_) {
    return null;
  }
}

/// 候选地址是否真的返回 HLS 播放列表。
Future<bool> _isHls(HttpClient client, String url) async {
  try {
    final request = await client.getUrl(Uri.parse(url));
    request.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    request.headers.set(HttpHeaders.rangeHeader, 'bytes=0-2047');
    final response = await request.close();
    if (response.statusCode >= 400) return false;
    final bytes = await response.fold<List<int>>(
      <int>[],
      (acc, chunk) => acc..addAll(chunk),
    );
    return utf8.decode(bytes.take(2048).toList(), allowMalformed: true)
        .contains('#EXTM3U');
  } catch (_) {
    return false;
  }
}

// ---------------------------------------------------------------- 离线部分

void offlineChecks() {

  // ------------------------------------------------------------ 1. 候选抽取
  section('1. 网页 HTML -> 候选地址');

  const pageUrl = 'https://v.gsuus.com/play/e1wwYPGb';
  final abs = StreamParsing.extractCandidates(_guangsuPage, pageUrl);
  checkEq('绝对地址能抽出来', abs.length, 1);
  checkEq('绝对地址原样保留', abs.first, 'https://v.gsuus.com/play/e1wwYPGb/index.m3u8');

  const shareUrl =
      'https://vip.dytt-live.com/share/926c11cc055de9b8d697b6a587d40c4d';
  final rel = StreamParsing.extractCandidates(_dyttPage, shareUrl);
  checkEq('根相对路径能抽出来', rel.length, 1);
  checkEq(
    '根相对路径按页面 origin 补全（并保留 sign）',
    rel.first,
    'https://vip.dytt-live.com/20250505/5821_926c11cc/index.m3u8'
        '?sign=41d7f8d44d49f792ddd3bdd209791cf0',
  );
  check('jpg 不会被当成播放地址', !rel.any((u) => u.endsWith('.jpg')));

  final esc = StreamParsing.extractCandidates(
    _escapedSlashPage,
    'https://www.example.com/play/x',
  );
  checkEq('JS 里的 \\/ 转义能还原', esc.length, 1);
  checkEq('还原后的地址', esc.first,
      'https://cdn.example.com/v/movie/index.m3u8?auth=abc');

  checkEq('空 HTML 返回空', StreamParsing.extractCandidates('', pageUrl).length, 0);
  checkEq(
    '没有播放地址时返回空',
    StreamParsing.extractCandidates('<p>no video here</p>', pageUrl).length,
    0,
  );

  // 去重 + 顺序
  const dup = '''
<a href="https://a.com/1.m3u8">x</a>
<a href="https://a.com/1.m3u8">x</a>
<a href="https://a.com/2.m3u8">y</a>
''';
  final dedup = StreamParsing.extractCandidates(dup, pageUrl);
  checkEq('重复地址会去重', dedup.length, 2);
  checkEq('保持出现顺序', dedup.first, 'https://a.com/1.m3u8');

  // ------------------------------------------------------------ 2. absolutize
  section('2. 地址补全（absolutize）');

  checkEq('已是绝对地址 -> 原样',
      StreamParsing.absolutize('https://x.com/a.m3u8', 'https://y.com/p'),
      'https://x.com/a.m3u8');
  checkEq('协议相对 -> 补 scheme',
      StreamParsing.absolutize('//x.com/a.m3u8', 'https://y.com/p'),
      'https://x.com/a.m3u8');
  checkEq('根相对 -> 换 origin 保留 path',
      StreamParsing.absolutize('/a/b.m3u8', 'https://y.com/deep/page'),
      'https://y.com/a/b.m3u8');
  checkEq('根相对 + 查询串',
      StreamParsing.absolutize('/a/b.m3u8?s=1', 'https://y.com/deep/page'),
      'https://y.com/a/b.m3u8?s=1');
  check('没有页面地址时补不出来',
      StreamParsing.absolutize('/a.m3u8', 'not a url') == null);

  // ------------------------------------------------------------ 3. 解析接口响应
  section('3. 解析接口响应 -> 播放地址');

  const req = 'https://api.example.com/jx?url=xxx';

  final j1 = StreamParsing.parseParseResponse(
    '{"code":200,"url":"https://cdn.a.com/v/index.m3u8"}',
    req,
  );
  checkEq('JSON 顶层 url', j1?.url, 'https://cdn.a.com/v/index.m3u8');

  final j2 = StreamParsing.parseParseResponse(
    '{"code":0,"data":{"url":"https://cdn.b.com/v/index.m3u8","header":{"Referer":"https://v.qq.com/"}}}',
    req,
  );
  checkEq('JSON data.url', j2?.url, 'https://cdn.b.com/v/index.m3u8');
  checkEq('同时取出 header 里的 Referer', j2?.headers['Referer'],
      'https://v.qq.com/');

  final j3 = StreamParsing.parseParseResponse(
    r'{"data":{"list":[{"name":"1080p","play_url":"https://cdn.c.com/v/index.m3u8"}]}}',
    req,
  );
  checkEq('深层 play_url 也能挖到', j3?.url, 'https://cdn.c.com/v/index.m3u8');

  final j4 = StreamParsing.parseParseResponse(
    'https://cdn.d.com/v/index.m3u8',
    req,
  );
  checkEq('纯文本就是一个地址', j4?.url, 'https://cdn.d.com/v/index.m3u8');

  final j5 = StreamParsing.parseParseResponse(
    '解析成功：https://cdn.e.com/v/index.m3u8 请享用',
    req,
  );
  checkEq('正文里夹着地址', j5?.url, 'https://cdn.e.com/v/index.m3u8');

  check('坏 JSON / 无地址 -> null',
      StreamParsing.parseParseResponse('{"msg":"解析失败"}', req) == null);
  check('空响应 -> null',
      StreamParsing.parseParseResponse('', req) == null);
  check('JSON 里没有播放地址 -> null',
      StreamParsing.parseParseResponse('{"url":"https://x.com/page.html"}', req) ==
          null);

  // ------------------------------------------------------------ 4. buildRequestUrl
  section('4. 解析接口地址拼接');

  ParseSource mk(String api, {bool post = false}) =>
      ParseSource(key: 'k', name: 'n', api: api, post: post);

  const target = 'https://v.qq.com/x/cover/abc.html';
  const enc = 'https%3A%2F%2Fv.qq.com%2Fx%2Fcover%2Fabc.html';

  checkEq('以 ?url= 结尾 -> 直接追加',
      mk('https://a.com/jx?url=').buildRequestUrl(target),
      'https://a.com/jx?url=$enc');
  checkEq('以 & 结尾 -> 直接追加',
      mk('https://a.com/jx?k=1&url=').buildRequestUrl(target),
      'https://a.com/jx?k=1&url=$enc');
  checkEq('{url} 占位符 -> 替换',
      mk('https://a.com/jx?target={url}&type=1').buildRequestUrl(target),
      'https://a.com/jx?target=$enc&type=1');
  checkEq('既没有查询串也没有占位符 -> 补 ?url=',
      mk('https://a.com/jx').buildRequestUrl(target),
      'https://a.com/jx?url=$enc');
  checkEq('已有查询串但没有 url -> 用 &',
      mk('https://a.com/jx?k=1').buildRequestUrl(target),
      'https://a.com/jx?k=1&url=$enc');

  // ------------------------------------------------------------ 5. 线路排序
  section('5. 线路可用性排序');

  MovieEpisode direct(String t) =>
      MovieEpisode(title: t, url: 'https://x.com/$t/index.m3u8');
  MovieEpisode page(String t) =>
      MovieEpisode(title: t, url: 'https://x.com/play/$t');
  MovieEpisode junk(String t) => MovieEpisode(title: t, url: '/share/$t');
  MovieEpisode blank(String t) => MovieEpisode(title: t, url: '');

  check('直链集 playable', direct('1').playable);
  check('网页集 resolvable', page('1').resolvable);
  check('网页集不是 playable', !page('1').playable);
  check('网页集 actionable', page('1').actionable);
  check('相对路径既不 playable 也不 resolvable',
      !junk('1').playable && !junk('1').resolvable && !junk('1').actionable);
  check('空地址啥也不是', !blank('1').actionable);

  final detail = MovieDetail(
    sourceKey: 's',
    vodId: '1',
    name: '测试片',
    routes: [
      // 全是网页页 -> 以前会被整个丢掉
      MovieRoute(name: '云线路', episodes: [page('1'), page('2'), page('3')]),
      // 全是垃圾 -> 一直都不该出现
      MovieRoute(name: '坏线路', episodes: [junk('1'), blank('2')]),
      // 直链
      MovieRoute(name: 'm3u8线路', episodes: [direct('1'), direct('2')]),
      // 混合：一半直链
      MovieRoute(
          name: '混合线路', episodes: [direct('1'), page('2'), junk('3')]),
    ],
  );

  final available = detail.availableRoutes.map((r) => r.name).toList();
  checkEq('可用线路包含「云线路」', available.contains('云线路'), true);
  checkEq('可用线路排除「坏线路」', available.contains('坏线路'), false);
  checkEq('可用线路 3 条', available.length, 3);
  // 直链占比高的优先：m3u8线路 2/2 = 1.0 > 混合线路 1/3 ≈ 0.33
  // （占比优先而不是条数优先 —— 占比高意味着更少集需要等解析）
  checkEq('全直链线路排第一', available.first, 'm3u8线路');
  checkEq('混合线路排第二', available[1], '混合线路');
  checkEq('全网页线路排最后', available.last, '云线路');

  checkEq('不显示无法处理的集也要留着（详情页要展示）',
      detail.routes[0].episodes.length, 3);
  checkEq('云线路 0 直链 3 可解析',
      '${detail.routes[0].playableCount}/${detail.routes[0].resolvableCount}',
      '0/3');
  checkEq('混合线路可播数 1/3',
      '${detail.routes[3].playableCount}/${detail.routes[3].episodes.length}',
      '1/3');

  checkEq('全是坏线路时 hasNoPlayableRoute',
      MovieDetail(
        sourceKey: 's',
        vodId: '1',
        name: 'x',
        routes: [
          MovieRoute(name: 'a', episodes: [junk('1')]),
        ],
      ).hasNoPlayableRoute,
      true);
}
