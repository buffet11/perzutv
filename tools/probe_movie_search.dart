// P1 验证脚本：走真实网络 + 复用真实解析代码，确认「能搜到片、能解析出可播 m3u8」。
//
// 用法（在 app 目录下）：
//     dart run tools/probe_movie_search.dart 流浪地球
//
// 为什么不用 MovieSearchService：
//   它依赖 DioFactory -> NetworkConfig.fromSettings() -> GStorage -> path_provider，
//   那些要 Flutter 运行时。本脚本跑在纯 Dart VM 里，所以自己用 dart:io 发请求，
//   但**解析全部走 AppleCmsApi 的公开纯函数** —— 这样验证的仍是真实代码。
//
// 它验证的是协议与解析，不是 UI 链路；网络层等价（同一个 URL、同一套请求参数）。

import 'dart:convert';
import 'dart:io';

import 'package:perzutv/modules/movie/builtin_movie_sources.dart';
import 'package:perzutv/modules/movie/movie_source.dart';
import 'package:perzutv/request/apis/apple_cms_api.dart';

const _ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36';

Future<Map<String, dynamic>?> _getJson(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set('User-Agent', _ua);
    req.headers.set('Accept', 'application/json');
    final resp = await req.close().timeout(const Duration(seconds: 12));
    final body = await resp.transform(utf8.decoder).join();
    final start = body.indexOf('{');
    final end = body.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    final decoded = jsonDecode(body.substring(start, end + 1));
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

Future<void> main(List<String> args) async {
  final keyword = args.isEmpty ? '流浪地球' : args.first;
  final sources = builtinMovieSources();

  stdout.writeln('关键词：$keyword');
  stdout.writeln('源数量：${sources.length}\n');

  var totalItems = 0;
  final firstHits = <MovieSource, String>{};

  for (final source in sources) {
    final url = '${source.normalizedApi}'
        '?ac=videolist&wd=${Uri.encodeQueryComponent(keyword)}&pg=1';
    final sw = Stopwatch()..start();
    final json = await _getJson(url);
    sw.stop();

    if (json == null) {
      stdout.writeln('✗ ${source.name.padRight(10)} 请求失败（${sw.elapsedMilliseconds}ms）');
      continue;
    }

    // —— 走真实解析 ——
    final page = AppleCmsApi.parseSearchPage(json, source, 1);
    totalItems += page.items.length;
    stdout.writeln('✓ ${source.name.padRight(10)} '
        '${page.items.length} 条 / 共 ${page.total} '
        '(${sw.elapsedMilliseconds}ms)');

    if (page.items.isNotEmpty && !firstHits.containsKey(source)) {
      firstHits[source] = page.items.first.vodId;
      final it = page.items.first;
      stdout.writeln('    ${it.name}  ${it.year}  ${it.remarks}  '
          '评分=${it.score}  id=${it.vodId}');
    }
  }

  stdout.writeln('\n合计 $totalItems 条\n');

  // 取第一个成功的源拉详情，验证线路解析
  if (firstHits.isEmpty) {
    stdout.writeln('没有可用源，无法继续验证详情。');
    exitCode = 1;
    return;
  }

  final source = firstHits.keys.first;
  final vodId = firstHits[source]!;
  final detailUrl = '${source.normalizedApi}'
      '?ac=videolist&ids=${Uri.encodeQueryComponent(vodId)}';

  stdout.writeln('=' * 62);
  stdout.writeln('详情验证：${source.name} / vodId=$vodId');
  stdout.writeln('=' * 62);

  final json = await _getJson(detailUrl);
  if (json == null) {
    stdout.writeln('详情请求失败');
    exitCode = 1;
    return;
  }

  final detail = AppleCmsApi.parseDetailResponse(json, source);
  if (detail == null) {
    stdout.writeln('详情解析为空');
    exitCode = 1;
    return;
  }

  stdout.writeln('片名   : ${detail.name}');
  stdout.writeln('年份   : ${detail.year}  地区: ${detail.area}  评分: ${detail.score}');
  stdout.writeln('类型   : ${detail.typeName}');
  stdout.writeln('简介   : ${detail.content.substring(0, detail.content.length.clamp(0, 80))}...');
  stdout.writeln('演员   : ${detail.actors.take(5).join(" / ")}');
  stdout.writeln('豆瓣id : ${detail.doubanId}');
  stdout.writeln('');
  stdout.writeln('原始线路（源站顺序）:');
  for (final r in detail.routes) {
    stdout.writeln('  ${r.name.padRight(14)} ${r.episodes.length} 集, '
        '${r.playableCount} 可播  ${r.playable ? "✓" : "✗ 播不了"}');
  }

  stdout.writeln('');
  stdout.writeln('按可播性排序后（播放器应当用第一条）:');
  final playable = detail.playableRoutes;
  if (playable.isEmpty) {
    stdout.writeln('  ⚠ 没有一条线路可播');
  }
  for (final r in playable) {
    final first = r.firstPlayable!;
    stdout.writeln('  ${r.name.padRight(14)} ${r.playableCount}/${r.episodes.length} 可播');
    stdout.writeln('      首集: ${first.title} -> ${first.url}');
  }

  stdout.writeln('');
  stdout.writeln(playable.isEmpty ? '结果：✗ 无可播线路' : '结果：✓ 有可播线路，P1 通');
}
