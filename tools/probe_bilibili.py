"""探测 B 站官方外链播放器与公开接口的可用性。

背景：perzutv 想接入「正版番剧」——不在本地解码，而是用应用内 WebView 加载
B 站官方外链播放器（player.bilibili.com）。这条路能不能走通，取决于三件事：

  1. 播放页是否允许「无 Referer 直接访问」（应用内 WebView 是顶层导航，
     不是 iframe，理论上不受 X-Frame-Options 限制）；
  2. 播放页在不同 UA 下是否被拒（WebView2 的 UA 带 Edg/ 标识）；
  3. pgc season 接口能否免签名拿到集列表（决定能不能「粘一个季号就选集」）。

本脚本只做 HTTP 层探测，不解析播放逻辑。全程只读，不写任何文件。

用法：
    python tools\\probe_bilibili.py
    python tools\\probe_bilibili.py "https://www.bilibili.com/bangumi/play/ss12345"
    python tools\\probe_bilibili.py ep282316          # 也接受裸编号

不带参数时只用官方文档里的示例视频做基础连通性测试。
"""

import json
import re
import ssl
import sys
import urllib.error
import urllib.request

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

# WebView2 的默认 UA 带 Edg/ 标识；用它测一遍，避免「浏览器能开、应用内被拒」
UA_BROWSER = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)
UA_WEBVIEW2 = (
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36 Edg/131.0.0.0"
)

# 官方外链播放器文档里的示例视频，必定存在
SAMPLE_BVID = "BV1B7411m7LV"

PLAYER = "https://player.bilibili.com/player.html"

INTERESTING_HEADERS = (
    "content-type",
    "x-frame-options",
    "content-security-policy",
    "location",
    "server",
)


def rule(char="=", width=64):
    print(char * width)


def banner(text=""):
    print(text)


def fetch(url, ua=UA_BROWSER, referer=None, timeout=15, limit=4000):
    """返回 (状态码, 响应头字典, 正文前缀, 错误信息)。"""
    headers = {
        "User-Agent": ua,
        "Accept": "text/html,application/json,*/*",
        "Accept-Language": "zh-CN,zh;q=0.9",
    }
    if referer:
        headers["Referer"] = referer

    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            raw = resp.read(limit)
            head = {k.lower(): v for k, v in resp.headers.items()}
            return resp.status, head, raw.decode("utf-8", "replace"), None
    except urllib.error.HTTPError as e:
        body = ""
        try:
            body = e.read(limit).decode("utf-8", "replace")
        except Exception:
            pass
        return e.code, {}, body, "HTTPError"
    except Exception as e:  # 网络层失败（DNS / 超时 / 连接被重置）
        return None, {}, "", f"{type(e).__name__}: {e}"


def summarize_headers(head):
    parts = []
    for key in INTERESTING_HEADERS:
        if key in head:
            value = head[key]
            if len(value) > 70:
                value = value[:70] + "..."
            parts.append(f"{key}={value}")
    return "；".join(parts) if parts else "（无关键头）"


def probe_player(label, url):
    """探测播放页在三种 UA / Referer 组合下的表现。"""
    banner(f"--- {label} ---")
    banner(f"    {url}")
    variants = [
        ("无 Referer + 浏览器 UA", UA_BROWSER, None),
        ("无 Referer + WebView2 UA", UA_WEBVIEW2, None),
        ("带 B站 Referer", UA_BROWSER, "https://www.bilibili.com/"),
    ]
    verdicts = []
    for name, ua, ref in variants:
        status, head, body, err = fetch(url, ua=ua, referer=ref)
        if status is None:
            banner(f"    [x] {name}: 请求失败 —— {err}")
            verdicts.append(False)
            continue
        ok = status == 200
        verdicts.append(ok)
        mark = "OK " if ok else "拒 "
        banner(f"    [{mark}] {name}: HTTP {status}")
        banner(f"          {summarize_headers(head)}")
        if not ok:
            snippet = body[:160].replace("\n", " ")
            banner(f"          正文: {snippet}")
        elif "player" not in body.lower():
            banner("          [注意] 200 但正文里没有 player 关键字，页面结构可能变了")
    banner()
    return verdicts


def probe_json_api(label, url, expect_keys):
    """探测 JSON 接口，返回 (是否可用, 解析后的字典)。"""
    banner(f"--- {label} ---")
    banner(f"    {url}")
    status, head, body, err = fetch(url, referer="https://www.bilibili.com/")
    if status is None:
        banner(f"    [x] 请求失败 —— {err}")
        banner()
        return False, None
    banner(f"    HTTP {status}  {summarize_headers(head)}")
    if status != 200:
        banner("    [x] 非 200，接口可能已加密或下线")
        banner()
        return False, None
    try:
        data = json.loads(body if len(body) < 4000 else body)
    except Exception:
        # 正文被 limit 截断时补一次完整请求
        status2, _, body2, err2 = fetch(
            url, referer="https://www.bilibili.com/", limit=8 * 1024 * 1024
        )
        try:
            data = json.loads(body2)
        except Exception as e:
            banner(f"    [x] 返回的不是合法 JSON（{e}）")
            banner(f"        正文: {body2[:160]!r}")
            banner()
            return False, None

    code = data.get("code", data.get("Code"))
    banner(f"    code = {code!r}  message = {data.get('message', '')!r}")
    if code == 0:
        result = data.get("result", data.get("data"))
        for key in expect_keys:
            value = None
            if isinstance(result, dict):
                value = result.get(key)
            if isinstance(value, list):
                banner(f"    result.{key} = 列表，共 {len(value)} 项")
            elif value is not None:
                banner(f"    result.{key} = {str(value)[:60]}")
        banner("    [OK] 免签名可读")
        banner()
        return True, data
    banner("    [x] code != 0，接口需要签名 / 登录态")
    banner()
    return False, data


def parse_target(raw):
    """从用户给的链接或裸编号里提取 (类型, 编号)。"""
    raw = raw.strip()
    if not raw:
        return None
    m = re.search(r"/(ep|ss)(\d+)", raw)
    if m:
        return (m.group(1), m.group(2))
    m = re.search(r"(BV[0-9A-Za-z]{10})", raw)
    if m:
        return ("bv", m.group(1))
    m = re.search(r"\bav(\d+)\b", raw, re.I)
    if m:
        return ("av", m.group(1))
    m = re.match(r"^(ep|ss)(\d+)$", raw, re.I)
    if m:
        return (m.group(1).lower(), m.group(2))
    m = re.match(r"^(BV[0-9A-Za-z]{10})$", raw)
    if m:
        return ("bv", m.group(1))
    return None


def main():
    rule()
    banner("  B 站外链播放器 / 公开接口 探测")
    rule()
    banner()

    if len(sys.argv) > 1 and sys.argv[1] in ("-h", "--help"):
        banner(__doc__)
        return 0

    user_arg = sys.argv[1] if len(sys.argv) > 1 else None
    target = parse_target(user_arg) if user_arg else None

    # ---------- 1. 播放页：UGC 视频 ----------
    ugc_url = (
        f"{PLAYER}?bvid={SAMPLE_BVID}"
        "&autoplay=0&danmaku=0&high_quality=1"
    )
    ugc_verdicts = probe_player("1. 播放页（UGC 示例视频）", ugc_url)

    # ---------- 2. 播放页：番剧（若给了 ep/ss） ----------
    ogv_urls = []
    if target and target[0] == "ep":
        ogv_urls.append(
            (
                f"2. 播放页（番剧，episodeId={target[1]}）",
                f"{PLAYER}?episodeId={target[1]}"
                "&autoplay=0&danmaku=0&high_quality=1",
            )
        )
    if target and target[0] == "ss":
        ogv_urls.append(
            (
                f"2. 播放页（番剧，仅 seasonId={target[1]}）",
                f"{PLAYER}?seasonId={target[1]}"
                "&autoplay=0&danmaku=0&high_quality=1",
            )
        )
    ogv_verdicts = []
    for label, url in ogv_urls:
        ogv_verdicts += probe_player(label, url)
    if not ogv_urls:
        banner("--- 2. 播放页（番剧）---")
        banner("    跳过：没有传入番剧链接。")
        banner("    想测番剧请带上链接，例如：")
        banner('      python tools\\probe_bilibili.py '
               '"https://www.bilibili.com/bangumi/play/ep282316"')
        banner()

    # ---------- 3. 视频详情接口 ----------
    view_ok, view_data = probe_json_api(
        "3. 视频详情接口（x/web-interface/view）",
        f"https://api.bilibili.com/x/web-interface/view?bvid={SAMPLE_BVID}",
        ["bvid", "aid", "title", "cid", "duration"],
    )

    # ---------- 4. pgc 季信息接口 ----------
    # 这个接口同时接受 season_id 和 ep_id —— 所以只要给一个剧集链接就能测，
    # 不需要用户自己去翻季号。
    season_query = None
    if target and target[0] == "ss":
        season_query = f"season_id={target[1]}"
    elif target and target[0] == "ep":
        season_query = f"ep_id={target[1]}"

    pgc_ok = False
    pgc_data = None
    first_ep = None
    if season_query:
        pgc_ok, pgc_data = probe_json_api(
            f"4. 番剧季信息接口（{season_query}）",
            f"https://api.bilibili.com/pgc/view/web/season?{season_query}",
            ["season_id", "title", "episodes", "total"],
        )
        if pgc_ok and pgc_data:
            try:
                episodes = (pgc_data.get("result") or {}).get("episodes") or []
                if episodes:
                    first_ep = episodes[0].get("id")
                    banner(f"    首集 episodeId = {first_ep}（可直接拼播放页验证）")
                    banner()
            except Exception:
                pass
    else:
        banner("--- 4. 番剧季信息接口（pgc/view/web/season）---")
        banner("    跳过：没传番剧链接。")
        banner("    想测请传剧集或整季链接，例如：")
        banner('      python tools\\probe_bilibili.py '
               '"https://www.bilibili.com/bangumi/play/ep282316"')
        banner()

    # ---------- 结论 ----------
    rule()
    banner("  结论")
    rule()
    ugc_ok = all(ugc_verdicts) if ugc_verdicts else False
    banner(
        f"  播放页（UGC）    : {'可达 ✓' if ugc_ok else '存在问题 ✗'}"
        + ("" if ugc_ok else "  —— 见上面逐条结果")
    )
    if ogv_verdicts:
        banner(
            f"  播放页（番剧）   : "
            f"{'可达 ✓' if all(ogv_verdicts) else '存在问题 ✗'}"
        )
        if target and target[0] == "ss" and all(ogv_verdicts):
            banner("                     （仅 seasonId 也能出页面，但不代表能播 —— "
                   "官方文档里 episodeId 才是必填）")
    banner(f"  视频详情接口     : {'免签名可用 ✓' if view_ok else '不可用 ✗'}")
    if season_query:
        banner(f"  番剧季接口       : {'免签名可用 ✓' if pgc_ok else '不可用 ✗'}")
    else:
        banner("  番剧季接口       : 未测")
    banner()
    if ugc_ok:
        banner("  → 「粘贴链接 / BV 号 → 应用内 WebView 播放」的方案可以开工。")
    else:
        banner("  → 播放页在无 Referer 时被拒，需要在 WebView 请求头里补 Referer，")
        banner("    或改用其它加载方式；把上面的逐条结果发我。")
    if season_query and not pgc_ok:
        banner("  → 季接口不可用：选集功能降级为「请粘贴具体某一集的链接」。")
    rule()
    return 0


if __name__ == "__main__":
    sys.exit(main())
