"""统计各源给出的播放地址形态 —— 判断「解析源」有没有真实用武之地。

对每个源的多部片，收集全部线路的全部集地址，按形态归类：
  direct   —— 直链（.m3u8/.mp4/.flv），播放器能直接播
  page     —— 绝对地址但不是直链（平台页/网页中转），**解析源的用武之地**
  relative —— 相对路径（没有 host，解析源也没办法）
"""

import json
import ssl
import sys
import urllib.parse
import urllib.request
from collections import Counter
from concurrent.futures import ThreadPoolExecutor

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36")

SOURCES = {
    "量子资源": "https://cj.lziapi.com",
    "金鹰资源": "https://jyzyapi.com",
    "电影天堂": "http://caiji.dyttzyapi.com",
    "极速资源": "https://jszyapi.com",
    "红牛资源": "https://www.hongniuzy2.com",
    "360资源": "https://360zy.com",
    "非凡资源": "http://cj.ffzyapi.com",
    "光速资源": "https://api.guangsuapi.com",
    "最大资源": "https://api.zuidapi.com",
    "艾旦影视": "https://lovedan.net",
    "虎牙资源": "https://www.huyaapi.com",
    "豪华资源": "https://hhzyapi.com",
    "魔都资源": "https://www.mdzyapi.com",
}

TITLES = ["流浪地球", "狂飙", "三体", "奥本海默"]

DIRECT_SUFFIX = (".m3u8", ".mp4", ".flv", ".mkv", ".ts")
# 常见的平台/中转页特征
PLATFORM_HINTS = ("v.qq.com", "iqiyi.com", "youku.com", "mgtv.com",
                  "bilibili.com", "sohu.com", "pptv.com", "le.com",
                  "/share/", "/play/", ".html", ".htm")


def http_get(url, timeout=10, headers=None):
    h = {"User-Agent": UA, "Accept": "application/json, */*"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        return r.status, r.read()


def norm_api(base):
    b = base.rstrip("/")
    if "://" in b and "/" not in b.split("://", 1)[1]:
        return b + "/api.php/provide/vod"
    return b


def classify(u):
    ul = u.lower()
    if not ul.startswith("http"):
        return "relative"
    if ul.endswith(DIRECT_SUFFIX):
        return "direct"
    return "page"


def probe(name, base):
    api = norm_api(base)
    stats = Counter()
    samples = {"page": [], "relative": []}
    lines = Counter()
    for title in TITLES:
        q = urllib.parse.urlencode({"ac": "videolist", "wd": title, "pg": 1})
        try:
            _, raw = http_get(f"{api}/?{q}", timeout=10)
            lst = json.loads(raw.decode("utf-8", "ignore")).get("list") or []
        except Exception:
            continue
        if not lst:
            continue
        vod_id = str(lst[0].get("vod_id", ""))
        if not vod_id:
            continue
        try:
            q2 = urllib.parse.urlencode({"ac": "videolist", "ids": vod_id})
            _, raw2 = http_get(f"{api}/?{q2}", timeout=12)
            det = (json.loads(raw2.decode("utf-8", "ignore")).get("list") or [None])[0]
            if not det:
                continue
        except Exception:
            continue

        groups = str(det.get("vod_play_url") or "").split("$$$")
        froms = str(det.get("vod_play_from") or "").split("$$$")
        for i, g in enumerate(groups):
            lname = froms[i] if i < len(froms) else f"line{i}"
            for seg in g.split("#"):
                parts = seg.split("$")
                u = (parts[1] if len(parts) > 1 else parts[0]).strip()
                if not u:
                    continue
                kind = classify(u)
                stats[kind] += 1
                if kind != "direct":
                    lines[lname] += 1
                    if len(samples[kind]) < 3:
                        samples[kind].append((title, lname, u[:90]))
    return {"name": name, "stats": dict(stats), "lines": dict(lines), "samples": samples}


def main():
    print(f"统计 {len(SOURCES)} 个源 × {len(TITLES)} 部片的播放地址形态\n", flush=True)
    out = []
    with ThreadPoolExecutor(max_workers=8) as ex:
        for r in ex.map(lambda kv: probe(*kv), SOURCES.items()):
            out.append(r)

    print(f"{'源名':<10}{'直链':>7}{'绝对非直链':>12}{'相对路径':>10}   非直链出自哪些线路")
    print("-" * 90)
    for r in out:
        s = r["stats"]
        d, p, rel = s.get("direct", 0), s.get("page", 0), s.get("relative", 0)
        lines = ",".join(f"{k}×{v}" for k, v in sorted(r["lines"].items(), key=lambda x: -x[1])[:4])
        print(f"{r['name']:<10}{d:>7}{p:>12}{rel:>10}   {lines}")

    print("\n=== 非直链样例 ===")
    for r in out:
        for kind in ("page", "relative"):
            for t, ln, u in r["samples"].get(kind, []):
                print(f"  [{r['name']}][{kind}][{ln}] {t}: {u}")

    with open("F:/WB-project/perzutv/_url_shapes.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print("\n明细已写入 _url_shapes.json")


if __name__ == "__main__":
    sys.exit(main())
