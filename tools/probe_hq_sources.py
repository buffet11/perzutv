"""探测候选影视源的可用性与画质。

两个阶段：
  1. 大批量并发探活（搜索「流浪地球」），筛出能返回结果的；
  2. 对存活的源拉详情 -> 取 m3u8 -> 抓 master playlist 看 RESOLUTION，
     判断它到底给不给 1080p 及以上。

输出一张表，供人工挑选内置源。
"""

import json
import re
import ssl
import sys
import time
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

# 候选源：key 是显示名，值是接口根地址
CANDIDATES = {
    "黑木耳": "https://json.heimuer.xyz",
    "非凡资源": "http://cj.ffzyapi.com",
    "天空资源": "https://api.tiankongapi.com",
    "快看资源": "https://kuaikan-api.com",
    "卧龙资源": "https://collect.wolongzyw.com",
    "无尽资源": "https://api.wujinapi.me",
    "索尼资源": "https://suoniapi.com",
    "飘零资源": "https://api.p00000.com",
    "天涯资源": "https://tyyszy.com",
    "闪电资源": "https://sdzyapi.com",
    "极速资源": "https://jszyapi.com",
    "最大资源": "https://api.zuidapi.com",
    "豪华资源": "https://hhzyapi.com",
    "四方资源": "https://www.sfzyapi.com",
    "豆瓣资源": "https://dbzy.com",
    "蘑菇资源": "https://caiji.moguzyw.com",
    "红牛资源": "https://www.hongniuzy2.com",
    "速播资源": "https://subocaiji.com",
    "如意资源": "https://cj.rycjapi.com",
    "大师兄": "https://api.1080zyku.com",
    "优质资源": "https://api.yzzy-api.com",
    "新视觉": "https://api.xinmp4.com",
    "哇哇资源": "https://api.wwzy.tv",
    "蚂蚁资源": "https://api.mayizy.com",
    "光速资源": "https://api.guangsuapi.com",
    "牛牛资源": "https://api.nnzyapi.com",
    "樱花资源": "https://api.yhzyapi.com",
    "凸凹资源": "https://api.tuapi.com",
    "电影天堂": "http://caiji.dyttzyapi.com",
    "360资源": "https://360zy.com",
    "金鹰资源": "https://jyzyapi.com",
    "量子资源": "https://cj.lziapi.com",
    "虎牙资源": "https://www.huyaapi.com",
    "飘花资源": "https://www.piaohua.com",
    "艾旦影视": "https://lovedan.net",
    "魔都资源": "https://www.mdzyapi.com",
    "百度资源": "https://api.apibdzy.com",
    "天空影视": "https://api.tkys1.com",
    "火星资源": "https://api.huo12.com",
    "金牌资源": "https://api.jinpai123.com",
}

MOVIE = "流浪地球"


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


def search_one(name, base):
    """返回 dict：avail / latency / count / 样例 vod_id / 线路名 / 错误"""
    api = norm_api(base)
    q = urllib.parse.urlencode({"ac": "videolist", "wd": MOVIE, "pg": 1})
    url = f"{api}/?{q}"
    t0 = time.time()
    out = {"name": name, "base": base, "api": api, "avail": False,
           "latency": -1, "count": 0, "vod_id": "", "froms": [], "err": ""}
    try:
        _, raw = http_get(url, timeout=10)
        ms = int((time.time() - t0) * 1000)
        text = raw.decode("utf-8", "ignore")
        data = json.loads(text)
        lst = data.get("list") or []
        out.update(avail=True, latency=ms, count=len(lst))
        if lst:
            it = lst[0]
            out["vod_id"] = str(it.get("vod_id", ""))
            out["froms"] = [s for s in str(it.get("vod_play_from", "")).split("$$$") if s]
    except Exception as e:
        out["err"] = f"{type(e).__name__}: {str(e)[:60]}"
    return out


RES_RE = re.compile(r"RESOLUTION=(\d+)x(\d+)")


def probe_quality(entry):
    """拉详情 -> 找可播 m3u8 -> 看 master playlist 的 RESOLUTION。"""
    vod_id = entry.get("vod_id")
    if not vod_id:
        return None
    q = urllib.parse.urlencode({"ac": "videolist", "ids": vod_id})
    try:
        _, raw = http_get(f"{entry['api']}/?{q}", timeout=12)
        data = json.loads(raw.decode("utf-8", "ignore"))
        lst = data.get("list") or []
        if not lst:
            return None
        det = lst[0]
        groups = str(det.get("vod_play_url") or "").split("$$$")
        froms = str(det.get("vod_play_from") or "").split("$$$")
    except Exception as e:
        entry["err"] = f"detail {type(e).__name__}"
        return None

    best = 0
    best_from = ""
    checked = 0
    for i, g in enumerate(groups):
        line = froms[i] if i < len(froms) else f"line{i}"
        for seg in g.split("#"):
            parts = seg.split("$")
            u = (parts[1] if len(parts) > 1 else parts[0]).strip()
            if ".m3u8" not in u:
                continue
            checked += 1
            if checked > 3:          # 每源最多抓 3 个，够判断了
                break
            try:
                _, body = http_get(u, timeout=8, max_bytes=20000,
                                   headers={"Accept": "*/*", "Referer": u})
                text = body.decode("utf-8", "ignore")
                heights = [int(m.group(2)) for m in RES_RE.finditer(text)]
                if heights:
                    h = max(heights)
                    if h > best:
                        best, best_from = h, line
                elif "#EXTINF" in text:
                    # 直接是媒体列表（无 master），高度未知，按 0 记
                    pass
            except Exception:
                pass
        if checked > 3:
            break

    entry["max_height"] = best
    entry["height_from"] = best_from
    return entry


def main():
    names = list(CANDIDATES.items())
    print(f"阶段 1：并发探活 {len(names)} 个候选源（关键词「{MOVIE}」）\n", flush=True)
    results = []
    with ThreadPoolExecutor(max_workers=16) as ex:
        for r in ex.map(lambda kv: search_one(*kv), names):
            results.append(r)

    ok = [r for r in results if r["avail"] and r["count"] > 0]
    ok.sort(key=lambda r: r["latency"])
    print(f"存活且能搜到：{len(ok)} / {len(results)}\n")
    print(f"{'源名':<12}{'延迟':>8}{'条数':>6}  线路")
    print("-" * 78)
    for r in ok:
        print(f"{r['name']:<12}{r['latency']:>6}ms{r['count']:>6}  "
              f"{','.join(r['froms'][:6])}")
    dead = [r for r in results if not (r["avail"] and r["count"] > 0)]
    if dead:
        print(f"\n不可用 {len(dead)} 个：")
        for r in dead:
            print(f"  {r['name']:<12} {r['err'][:60]}")

    print(f"\n阶段 2：抓 m3u8 看画质（各源最多 3 条线路）\n", flush=True)
    print(f"{'源名':<12}{'最高分辨率':>12}  线路")
    print("-" * 78)
    with ThreadPoolExecutor(max_workers=8) as ex:
        for r in ex.map(probe_quality, ok):
            if r is None:
                continue
            h = r.get("max_height", 0)
            label = f"{h}p" if h else "未知/非master"
            print(f"{r['name']:<12}{label:>12}  {r.get('height_from','')}")

    # 落一份 JSON 备查
    with open("F:/WB-project/perzutv/_hq_probe.json", "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    print("\n明细已写入 _hq_probe.json")


if __name__ == "__main__":
    sys.exit(main())
