"""深挖画质：对存活的源，用多部片子测，取最高分辨率/码率。

比 probe_hq_sources.py 更严：
  - 每源测多部片（不同类型的），看画质是否稳定；
  - m3u8 同时读 RESOLUTION 与 BANDWIDTH（有的 master 只给码率）；
  - 每条线路多抽几集，降低偶然性。
"""

import json
import re
import ssl
import sys
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

UA = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)

ALIVE = {
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

TITLES = ["流浪地球", "沙丘", "狂飙", "三体", "奥本海默", "热辣滚烫"]

RES_RE = re.compile(r"RESOLUTION=(\d+)x(\d+)")
BW_RE = re.compile(r"BANDWIDTH=(\d+)")


def http_get(url, timeout=10, headers=None, max_bytes=None):
    h = {"User-Agent": UA, "Accept": "application/json, */*"}
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, headers=h)
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
        data = r.read() if max_bytes is None else r.read(max_bytes)
        return r.status, data


def norm_api(base):
    b = base.rstrip("/")
    if "://" in b and "/" not in b.split("://", 1)[1]:
        return b + "/api.php/provide/vod"
    return b


def m3u8_quality(url, depth=0):
    """返回 (max_height, max_bandwidth)。master 会挑最高的一路再跟一层。"""
    if depth > 2:
        return 0, 0
    try:
        _, body = http_get(url, timeout=8, max_bytes=40000,
                           headers={"Accept": "*/*", "Referer": url})
    except Exception:
        return 0, 0
    text = body.decode("utf-8", "ignore")
    heights = [int(m.group(2)) for m in RES_RE.finditer(text)]
    bws = [int(m.group(1)) for m in BW_RE.finditer(text)]

    if heights:
        return max(heights), (max(bws) if bws else 0)

    # master 只给了 BANDWIDTH -> 按码率粗估：约 1080p 需 4~6 Mbps
    if bws:
        return 0, max(bws)

    # 是媒体列表（含 #EXTINF 但没有码率/分辨率），说明单码率，跟不了
    return 0, 0


def probe_one_source(name, base):
    api = norm_api(base)
    per_title = {}
    for title in TITLES:
        q = urllib.parse.urlencode({"ac": "videolist", "wd": title, "pg": 1})
        try:
            _, raw = http_get(f"{api}/?{q}", timeout=10)
            data = json.loads(raw.decode("utf-8", "ignore"))
            lst = data.get("list") or []
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
        best_h, best_b = 0, 0
        for i, g in enumerate(groups):
            urls = []
            for seg in g.split("#"):
                parts = seg.split("$")
                u = (parts[1] if len(parts) > 1 else parts[0]).strip()
                if ".m3u8" in u:
                    urls.append(u)
            for u in urls[:2]:                 # 每条线路最多抽 2 集
                h, b = m3u8_quality(u)
                best_h = max(best_h, h)
                best_b = max(best_b, b)
        per_title[title] = (best_h, best_b)

    return {"name": name, "base": base, "per_title": per_title}


def label(h, b):
    if h:
        return f"{h}p"
    if b:
        return f"~{b // 1000}kbps"
    return "-"


def main():
    print(f"对 {len(ALIVE)} 个源 × {len(TITLES)} 部片做画质纵横对比\n", flush=True)
    out = []
    with ThreadPoolExecutor(max_workers=6) as ex:
        for r in ex.map(lambda kv: probe_one_source(*kv), ALIVE.items()):
            out.append(r)

    head = f"{'源名':<10}" + "".join(f"{t:>12}" for t in TITLES) + f"{'结论':>10}"
    print(head)
    print("-" * (10 + 12 * len(TITLES) + 10))
    for r in out:
        row = f"{r['name']:<10}"
        maxh = 0
        for t in TITLES:
            h, b = r["per_title"].get(t, (0, 0))
            row += f"{label(h, b):>12}"
            maxh = max(maxh, h)
        r["max_height"] = maxh
        row += f"{(str(maxh) + 'p') if maxh else '需人工':>10}"
        print(row)

    print()
    hq = [r for r in out if r["max_height"] >= 1080]
    hq.sort(key=lambda r: -r["max_height"])
    print("=== 达到 1080p 及以上的源 ===")
    for r in hq:
        hits = sum(1 for t in TITLES if r["per_title"].get(t, (0, 0))[0] >= 1080)
        print(f"  {r['name']:<10} 最高 {r['max_height']}p   在 {hits}/{len(TITLES)} 部片中达到 1080p")

    with open("F:/WB-project/kazutv/_hq_probe2.json", "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=2)
    print("\n明细已写入 _hq_probe2.json")


if __name__ == "__main__":
    sys.exit(main())
