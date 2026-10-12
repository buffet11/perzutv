"""探测苹果CMS（maccms）采集源的可用性，筛出能进内置清单的源。

对每个候选 base 依次做四件事：

  1. 搜索接口 `?ac=videolist&wd=<关键词>&pg=1`
     —— 判定 JSON 是否合法、`code==1`、命中条数；（多个关键词各测一遍取最大命中）
  2. 分类树 `?ac=list`（拿不到就退到 `?ac=detail`）
     —— 判定能否拿到 `class` 数组、分了多少类；
  3. 动漫分区 —— 分类树里 `type_name` 命中「动漫/国漫/日漫/动画/番剧/剧场版」的分区
     （后续「动漫」模块要用，这是优先收录项）；
  4. 分区列表 `?ac=detail&t=<typeId>&pg=1`（退到 `?ac=videolist&t=<typeId>`）
     —— 对有动漫分区的源，验证该分区能否真的拉到片单。

输出一张可读表格（成功/失败、命中数、动漫分区、分区列表可用性、延迟），
并把同一份内容写入 txt 报告（默认落在本脚本同目录）。

用法（在能访问外网的机器上跑；沙箱/代理下超时失败属正常）：

    python tools/probe_sources.py
    python tools/probe_sources.py --keywords 斗罗大陆,流浪地球 --timeout 20
    python tools/probe_sources.py --out /tmp/r.txt --workers 16

候选源清单见下方 CANDIDATES —— 想加源直接往字典里加一行即可。
"""

import argparse
import json
import os
import re
import ssl
import sys
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

# 不少采集站证书链不全或用了自签证书，探测时统一跳过校验（与 tools/ 下其它
# 探测脚本一致）。这里只是为了「看接口活不活」，不涉及敏感数据传输。
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)

# 判定「动漫分区」的关键字。采集站对动漫的叫法不统一，尽量覆盖。
ANIME_RE = re.compile(r"动漫|国漫|日漫|动画|番剧|剧场版")

# 候选源：显示名 -> 接口根地址。
# 可以只给域名（脚本会补 /api.php/provide/vod），也可以给到完整接口根。
# 顺序无意义，最终按探测结果排序输出。
CANDIDATES = {
    # —— 当前已内置（含怀疑已挂的），纳入复测 ——
    "电影天堂": "http://caiji.dyttzyapi.com",
    "360资源": "https://360zy.com",
    "金鹰资源": "https://jyzyapi.com",
    "量子资源": "https://cj.lziapi.com",
    "虎牙资源": "https://www.huyaapi.com",
    "光速资源": "https://api.guangsuapi.com",
    "最大资源": "https://api.zuidapi.com",
    "非凡资源": "http://cj.ffzyapi.com",

    # —— 上一轮实测有命中的，复测并重点看动漫分区 ——
    "魔都资源": "https://www.mdzyapi.com",
    "飘零资源": "https://p2100.net",
    "飘零资源2": "https://api.p00000.com",

    # —— 上一轮本环境不通，但未必真死，加长超时复测 ——
    "快看资源": "https://kuaikan-api.com",
    "卧龙资源": "https://collect.wolongzyw.com",
    "豪华资源": "https://hhzyapi.com",
    "百度资源": "https://api.apibdzy.com",
    "暴风资源": "https://bfzyapi.com",
    "极速资源": "https://jszyapi.com",
    "红牛资源": "https://www.hongniuzy2.com",
    "天涯资源": "https://tyyszy.com",
    "无尽资源": "https://api.wujinapi.me",
    "天空资源": "https://api.tiankongapi.com",
    "豆瓣资源": "https://dbzy.tv",
    "索尼资源": "https://suoniapi.com",
    "新浪资源": "https://api.xinlangapi.com/xinlangapi.php/provide/vod",
    "闪电资源": "https://sdzyapi.com",
    "ikun资源": "https://ikunzyapi.com",
    "天堂资源": "http://caiji.ttzyapi.com",
    "优优资源": "https://api.uuzyapi.com",
    "樱花资源": "https://api.yinghuazy.com",

    # —— 常见苹果CMS采集站（历史/常见源清单里活跃过的），补进来广撒网 ——
    "黑木耳": "https://json.heimuer.xyz",
    "蘑菇资源": "https://caiji.moguzyw.com",
    "速播资源": "https://subocaiji.com",
    "如意资源": "https://cj.rycjapi.com",
    "大师兄": "https://api.1080zyku.com",
    "优质资源": "https://api.yzzy-api.com",
    "新视觉": "https://api.xinmp4.com",
    "哇哇资源": "https://api.wwzy.tv",
    "蚂蚁资源": "https://api.mayizy.com",
    "牛牛资源": "https://api.nnzyapi.com",
    "凸凹资源": "https://api.tuapi.com",
    "四方资源": "https://www.sfzyapi.com",
    "艾旦影视": "https://lovedan.net",
    "天空影视": "https://api.tkys1.com",
    "火星资源": "https://api.huo12.com",
    "金牌资源": "https://api.jinpai123.com",
    "酷点资源": "https://kudian10.com",
    "动漫资源": "https://api.dmzyapi.com",
}


def norm_api(base):
    """把候选地址补成完整接口根（与 MovieSource.normalizedApi 同规则）。"""
    b = base.strip().rstrip("/")
    if "://" in b and "/" not in b.split("://", 1)[1]:
        return b + "/api.php/provide/vod"
    return b


def http_get(url, timeout, headers=None):
    h = {"User-Agent": UA, "Accept": "application/json, */*"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        return r.read()


def q(url, params):
    return f"{url}?{urllib.parse.urlencode(params)}"


def fetch_classes(api, timeout):
    """拿分类树：先 ac=list，拿不到再 ac=detail。"""
    for ac in ("list", "detail"):
        try:
            d = json.loads(http_get(q(api, {"ac": ac, "pg": 1}), timeout).decode("utf-8", "replace"))
            classes = d.get("class") or []
            if classes:
                return [(c.get("type_id"), str(c.get("type_name", ""))) for c in classes]
        except Exception:
            continue
    return []


def verify_category(api, type_id, timeout):
    """验证某个分区能否拉到片单：ac=detail&t= 拿不到就退 ac=videolist&t=。"""
    for kw in ({"ac": "detail", "t": type_id, "pg": 1},
               {"ac": "videolist", "t": type_id, "pg": 1}):
        try:
            d = json.loads(http_get(q(api, kw), timeout).decode("utf-8", "replace"))
            n = len(d.get("list") or [])
            if n:
                return n
        except Exception:
            continue
    return 0


def probe(item, keywords, timeout):
    """探测单个源，返回结果字典。"""
    name, base = item
    api = norm_api(base)
    r = {
        "name": name, "base": base, "api": api,
        "ok": False, "code": None,
        "counts": {}, "count": 0, "latency": -1,
        "classes": 0, "anime": [],
        "cat_works": False, "cat_count": 0,
        "err": "",
    }

    # —— 1. 搜索接口：多个关键词各测一遍，取命中最大的 ——
    best_ms = -1
    for kw in keywords:
        t0 = time.time()
        try:
            raw = http_get(q(api, {"ac": "videolist", "wd": kw, "pg": 1}), timeout)
            ms = int((time.time() - t0) * 1000)
            d = json.loads(raw.decode("utf-8", "replace"))
            code = d.get("code")
            r["code"] = code
            if code == 1:
                n = len(d.get("list") or [])
                r["counts"][kw] = n
                if n > r["count"]:
                    r["count"] = n
                r["ok"] = True
                if best_ms < 0 or ms < best_ms:
                    best_ms = ms
            elif not r["err"]:
                r["err"] = f"code={code}"
        except Exception as e:
            if not r["err"]:
                r["err"] = f"{type(e).__name__}: {str(e)[:60]}"
    r["latency"] = best_ms

    if not r["ok"]:
        return r

    # —— 2. 分类树 ——
    classes = fetch_classes(api, timeout)
    r["classes"] = len(classes)

    # —— 3. 动漫分区 ——
    r["anime"] = [(tid, tn) for tid, tn in classes if ANIME_RE.search(tn)]

    # —— 4. 验证动漫分区能拉片单 ——
    if r["anime"]:
        n = verify_category(api, r["anime"][0][0], timeout)
        if n:
            r["cat_works"] = True
            r["cat_count"] = n
    return r


def fmt_row(r, idx):
    if r["ok"]:
        hits = " ".join(f"{k}:{v}" for k, v in r["counts"].items()) or "0"
        lat = f"{r['latency']}ms" if r["latency"] >= 0 else "-"
        return (f"  {idx:>2}  {r['name']:<8} {r['count']:>4}  {lat:>7}  "
                f"分类{r['classes']:>3}  动漫{len(r['anime']):>2}  "
                f"{'可用(' + str(r['cat_count']) + ')' if r['cat_works'] else '不可用':<8} {hits}")
    code = r["code"] if r["code"] is not None else "-"
    return f"  {idx:>2}  {r['name']:<8} {'--':>4}  {'--':>7}  code={code}  {r['err']}"


def build_report(results, args, started, elapsed):
    lines = []
    add = lines.append
    add("=" * 92)
    add("苹果CMS 采集源探测报告")
    add(f"时间   : {started}")
    add(f"关键词 : {', '.join(args.keywords)}")
    add(f"超时   : {args.timeout}s    并发: {args.workers}    候选: {len(results)}")
    add(f"耗时   : {elapsed:.1f}s")
    add("=" * 92)
    add("")

    ok = [r for r in results if r["ok"] and r["count"] > 0]
    # 排序：先动漫分区可用的，再按命中数，再按延迟
    ok.sort(key=lambda r: (not r["cat_works"], -len(r["anime"]), -r["count"],
                           r["latency"] if r["latency"] >= 0 else 10 ** 9))
    noreply = [r for r in results if not (r["ok"] and r["count"] > 0)]

    add(f"【确认可用】{len(ok)} 个（code==1 且有命中）—— 按「动漫分区可用 > 动漫分区数 > 命中数 > 延迟」排序")
    add("   #  源名        命中    延迟    分类树  动漫分区  分区列表   命中明细(关键词:条数)")
    add("  " + "-" * 88)
    for i, r in enumerate(ok, 1):
        add(fmt_row(r, i))
        if r["anime"]:
            add("      动漫分区: " + ", ".join(f"{t}:{n}" for t, n in r["anime"][:12]))
        if not r["cat_works"] and r["anime"]:
            add("      (分区列表接口未取到片单，动漫浏览可能不可用，搜索仍可用)")
    add("")

    add(f"【本环境不通 / 无命中】{len(noreply)} 个 —— 未必真死，可能只是本机网络/代理问题")
    add("  " + "-" * 88)
    for i, r in enumerate(sorted(noreply, key=lambda x: x["name"]), 1):
        add(fmt_row(r, i))
    add("")

    anime_ok = [r for r in ok if r["anime"]]
    add("=" * 92)
    add(f"汇总: 确认可用 {len(ok)}/{len(results)}；其中带动漫分区 {len(anime_ok)} 个；"
        f"动漫分区列表可用 {sum(1 for r in ok if r['cat_works'])} 个")
    if anime_ok:
        add("带动漫分区的源（优先收录）: " + ", ".join(r["name"] for r in anime_ok))
    add("=" * 92)
    return "\n".join(lines)


def main():
    ap = argparse.ArgumentParser(description="探测苹果CMS采集源可用性")
    ap.add_argument("--keywords", default="斗罗大陆",
                    help="搜索关键词，逗号分隔；每个源对每个关键词各测一遍取最大命中")
    ap.add_argument("--timeout", type=int, default=15, help="单请求超时秒数（默认 15）")
    ap.add_argument("--workers", type=int, default=16, help="并发线程数（默认 16）")
    ap.add_argument("--out", default="", help="报告输出路径；默认写本脚本同目录")
    args = ap.parse_args()
    args.keywords = [k.strip() for k in args.keywords.split(",") if k.strip()]

    started = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"探测 {len(CANDIDATES)} 个候选源  关键词={args.keywords}  超时={args.timeout}s\n", flush=True)

    t0 = time.time()
    items = list(CANDIDATES.items())
    with ThreadPoolExecutor(max_workers=args.workers) as ex:
        results = list(ex.map(lambda it: probe(it, args.keywords, args.timeout), items))
    elapsed = time.time() - t0

    report = build_report(results, args, started, elapsed)
    print(report)

    out = args.out or os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                   "source_probe_report.txt")
    with open(out, "w", encoding="utf-8") as f:
        f.write(report + "\n")
    print(f"\n报告已写入: {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
