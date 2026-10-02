"""跑 probe_movie_resolve.dart（影视地址解析的回归验证）。

为什么要这个包装脚本，而不是直接 `dart run tools/probe_movie_resolve.dart`：

    在 Flutter 包目录里跑 `dart run`，会先为**整个包**构建 native assets
    （ech_http、media_kit 都有构建钩子，要编 C 代码）。而
    `native_toolchain_c` 在中文 Windows（ANSI 代码页 936/GBK）上有个缺陷：
    它用 jsonDecode 解析 `vswhere.exe -format json -utf8` 的输出，解出来的
    文本里混进控制字符，直接抛 FormatException —— 于是脚本一行没跑就挂了。

    这不是本项目的代码问题（`flutter build` 走 CMake，不受影响），
    也没法在本地绕过。

绕过办法：把探针用到的几个**纯文件**复制到一个没有 pubspec.yaml 的临时
目录，把 `package:kazutv/` 改写成相对路径，在那儿跑。没有 pubspec 就没有
native assets 这一步。

被复制的文件都不依赖 Flutter（只 import dart:convert 或不 import 任何东西），
所以脱离包也能编译。

    python tools/run_movie_resolve_probe.py            # 离线部分
    python tools/run_movie_resolve_probe.py --live     # 再加联网自检
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

APP_DIR = Path(__file__).resolve().parent.parent
PROBE = APP_DIR / "tools" / "probe_movie_resolve.dart"

# 探针依赖的纯文件（不碰 Flutter / dio）
PURE_FILES = [
    "lib/services/movie/movie_stream_parsing.dart",
    "lib/modules/movie/parse_source.dart",
    "lib/modules/movie/movie_detail.dart",
]


def find_dart():
    """按优先级找 dart 可执行文件。找到返回路径，否则返回 None。"""
    for env in ("DART_BIN", "DART_SDK"):
        value = os.environ.get(env)
        if not value:
            continue
        p = Path(value)
        if p.is_dir():
            p = p / "dart.exe" if os.name == "nt" else p / "dart"
        if p.is_file():
            return str(p)

    found = shutil.which("dart")
    if found:
        return found

    # Flutter SDK 自带的 dart
    candidates = [
        Path(r"D:\path\flutter\bin\cache\dart-sdk\bin\dart.exe"),
        Path(r"C:\flutter\bin\cache\dart-sdk\bin\dart.exe"),
    ]
    for p in candidates:
        if p.is_file():
            return str(p)
    return None


def main() -> int:
    dart = find_dart()
    if dart is None:
        print("[错误] 找不到 dart。设环境变量 DART_BIN 指向它，或把 dart 加进 PATH。")
        return 1

    if not PROBE.is_file():
        print(f"[错误] 找不到探针：{PROBE}")
        return 1

    with tempfile.TemporaryDirectory(prefix="kazutv_probe_") as raw:
        tmp = Path(raw)
        for rel in PURE_FILES:
            src = APP_DIR / rel
            if not src.is_file():
                print(f"[错误] 缺少 {rel}")
                return 1
            dst = tmp / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)

        # 把 package 导入改写成相对路径 —— 脱离 pubspec 后唯一的办法
        text = PROBE.read_text(encoding="utf-8")
        rewritten = text.replace("package:kazutv/", "../lib/")
        if rewritten == text:
            print("[警告] 探针里没有 package:kazutv/ 导入，可能已改过写法")
        # 保持 LF：Dart 对行尾不敏感，但别让工具链的 lint 抱怨
        (tmp / "tools").mkdir(parents=True, exist_ok=True)
        (tmp / "tools" / "probe.dart").write_text(rewritten, encoding="utf-8", newline="")

        cmd = [dart, "run", os.path.join("tools", "probe.dart"), *sys.argv[1:]]
        # flush：子进程直接往终端写，不 flush 的话这几行会跑到它后面去
        print(f"[运行] {' '.join(cmd)}", flush=True)
        print(f"[临时目录] {tmp}  （无 pubspec，所以不会触发 native assets）", flush=True)
        print(flush=True)
        return subprocess.call(cmd, cwd=str(tmp))


if __name__ == "__main__":
    sys.exit(main())
