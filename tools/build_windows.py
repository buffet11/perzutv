"""
Perzutv Windows 构建驱动。

为什么不把逻辑写在 .bat 里
--------------------------
cmd.exe 按固定大小的缓冲块读取批处理文件、并按当前代码页解码，多字节汉字卡在
块边界上会被劈开，整行被截断成两条命令 —— 十几行的脚本上必现。
UTF-8 带 BOM 更糟，BOM 会让首行的 `@echo off` 失效。
（详见用户级 MEMORY.md「Windows .bat 编码」一节）

所以：.bat 只做纯 ASCII 的引导，中文横幅与提示一律由本脚本用 Python 打印
（Python 经 WriteConsoleW 输出 Unicode，可靠）。

用法
----
    python tools\\build_windows.py           # 构建
    python tools\\build_windows.py clean     # 先清理再构建
    python tools\\build_windows.py no-zip    # 构建，但跳过绿色版 zip 打包
"""
import os
import re
import shutil
import subprocess
import sys
import zipfile
from pathlib import Path

# 同目录的模块：直接运行本脚本时 sys.path[0] 就是 tools/
from hooks_prebuilt import ensure_all as ensure_hook_prebuilts

# ---------------------------------------------------------------- 路径与常量

TOOLS_DIR = Path(__file__).resolve().parent   # <app>/tools
APP_DIR = TOOLS_DIR.parent                    # <app>（含 pubspec.yaml 的 Flutter 项目根）
REPO_DIR = APP_DIR.parent                     # <perzutv 仓库根>（含 tools/danmu-api）
DANMU_API_SRC = REPO_DIR / "tools" / "danmu-api"
DELIVERABLES_DIR = REPO_DIR / "交付物"

FLUTTER_BIN = Path(r"D:\path\flutter\bin")
FLUTTER = FLUTTER_BIN / "flutter.bat"

# 国内镜像
MIRRORS = {
    "PUB_HOSTED_URL": "https://pub.flutter-io.cn",
    "FLUTTER_STORAGE_BASE_URL": "https://storage.flutter-io.cn",
}

# Dart 无法创建子进程时会出现这些特征
PIPE_ERROR_MARKERS = (
    "所有的管道范例都在使用中",
    "ERROR_PIPE_BUSY",
    "CreateFile failed 231",
    "process_win.cc",
)


def banner(text=""):
    print(text, flush=True)


def rule():
    print("=" * 62, flush=True)


# ---------------------------------------------------------------- 环境准备

def build_env():
    env = os.environ.copy()
    env.update(MIRRORS)
    env["PATH"] = str(FLUTTER_BIN) + os.pathsep + env.get("PATH", "")
    return env


def get_credentials_defines():
    """若存在本地凭据文件，返回 --dart-define-from-file 参数。"""
    # 兼容改名前的旧文件名（.kazutv_* -> .perzutv_*），两个都认。
    for name in (".perzutv_build_defines.env", ".kazutv_build_defines.env"):
        if (APP_DIR / name).is_file():
            return [f"--dart-define-from-file={name}"]
    return []


def _current_cmake_project_name():
    """从 windows/CMakeLists.txt 的 project() 取当前项目名。

    正则排掉空白与右括号：既有 `project(perzutv LANGUAGES CXX)` 这种写法，
    也要兼容最简的 `project(perzutv)`（否则会把右括号吃进项目名）。
    """
    cmakelists = APP_DIR / "windows" / "CMakeLists.txt"
    if not cmakelists.is_file():
        return None
    m = re.search(r"^\s*project\(\s*([^\s)]+)",
                  cmakelists.read_text(encoding="utf-8"), re.M)
    return m.group(1) if m else None


def _clean_build_dir(build_dir: Path):
    """删掉整个 CMake 构建目录，但保住 NuGet 工具与已下载的包。

    nuget.exe 与 packages/ 都是插件从网上下的，删了要重下；其余全部重建。
    """
    keep_names = ("nuget.exe", "packages")
    stash = build_dir.parent / "_keep_for_rebuild"
    shutil.rmtree(stash, ignore_errors=True)
    stash.mkdir(parents=True, exist_ok=True)

    moved = []
    for name in keep_names:
        src = build_dir / name
        if src.exists():
            shutil.move(str(src), str(stash / name))
            moved.append(name)

    shutil.rmtree(build_dir, ignore_errors=True)
    build_dir.mkdir(parents=True, exist_ok=True)

    for name in moved:
        shutil.move(str(stash / name), str(build_dir / name))
    shutil.rmtree(stash, ignore_errors=True)
    return moved


def ensure_cmake_cache_fresh():
    """CMake 缓存与当前项目对不上时自动清掉，避免"改了东西就构建失败"。

    两种必踩的情况：

    **一、改过 project() 名 / BINARY_NAME** —— 缓存里留着旧 target 名。
    上游模板里写的是：

        set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
        if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
          set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
        endif()

    缓存已经存在时那个 if 为假，于是缓存里存下来的**字面量**
    `$<TARGET_FILE_DIR:kazumi>` 会被直接求值 —— CMake 报：

        Error evaluating generator expression: $<TARGET_FILE_DIR:kazumi>
        No target "kazumi"

    **二、整个项目目录被改过名**（例如 `F:/WB-project/kazutv` → `perzutv`）——
    缓存里记着生成时的绝对路径，CMake 会校验并直接拒绝：

        CMakeCache.txt directory .../perzutv/app/build/windows/x64 is different
        than the directory .../kazutv/app/build/windows/x64 where it was created
        The source "..." does not match the source "..." used to generate cache

    两种都和代码本身没关系，纯粹是"缓存过期"。这里自动认出来并清掉
    （保留 nuget.exe / packages，免去重新下载），用户不用手动 clean。
    """
    build_dir = APP_DIR / "build" / "windows" / "x64"
    cache = build_dir / "CMakeCache.txt"
    if not cache.is_file():
        return

    current = _current_cmake_project_name()
    if not current:
        return

    text = cache.read_text(encoding="utf-8", errors="replace")

    # ① 目录被改过名（例如 kazutv → perzutv）：CMake 会拿缓存里记的
    #    「生成目录 / 源码目录」跟当前路径比对，不一致直接报
    #      CMakeCache.txt directory ... is different than the directory ...
    #    / The source "..." does not match the source "..." used to generate cache
    #    这跟项目名无关，是路径变了 —— 同样必须清掉缓存重来。
    path_stale = []
    m = re.search(r"^# For build in directory:\s*(.+?)\s*$", text, re.M)
    if m and os.path.normcase(m.group(1).strip()) != os.path.normcase(str(build_dir)):
        path_stale.append(f"缓存生成于 {m.group(1).strip()}")
    m = re.search(r"^CMAKE_HOME_DIRECTORY:INTERNAL=(.+?)\s*$", text, re.M)
    if m and os.path.normcase(m.group(1).strip()) != os.path.normcase(str(APP_DIR)):
        path_stale.append(f"源码目录 {m.group(1).strip()}")
    if path_stale:
        banner(f"       检测到 CMake 缓存是在别的路径下生成的：{'；'.join(path_stale)}")
        banner(f"       当前项目目录：{APP_DIR}")
        banner("       目录改名过 → 清理构建配置后重新生成（会自动重建）")
        kept = _clean_build_dir(build_dir)
        if kept:
            banner(f"       已保留：{'、'.join(kept)}（免去重新下载）")
        banner()
        return

    # ② 项目名对不上
    stale = set()
    for pat in (r"^CMAKE_INSTALL_PREFIX:PATH=\$<TARGET_FILE_DIR:([^>]+)>",
                r"^CMAKE_PROJECT_NAME:STATIC=(\S+)"):
        for m in re.finditer(pat, text, re.M):
            if m.group(1) != current:
                stale.add(m.group(1))
    if not stale:
        return

    banner(f"       检测到 CMake 缓存属于旧项目名：{'、'.join(sorted(stale))}")
    banner(f"       当前项目名是 {current} —— 清理构建配置后重新生成（会自动重建）")
    kept = _clean_build_dir(build_dir)
    if kept:
        banner(f"       已保留：{'、'.join(kept)}（免去重新下载）")
    banner()


def run(cmd, env, cwd=APP_DIR):
    """执行命令并把输出**实时**透传到控制台，返回 (退出码, 已收集的文本)。

    注意：不能先 subprocess.run(stdout=PIPE) 再一次性 print ——
    那样在 pub get 这种几十秒到几分钟的步骤上，用户会看到一片空白、
    以为卡死了（实际踩过，用户直接把窗口关了）。
    这里改成逐块读取、边读边打印。

    编码：子进程 stdout 是管道，Dart 会混用 UTF-8 与本地代码页输出，
    所以按 UTF-8 硬解 + errors='replace'，保证不抛异常、Flutter 的英文
    进度信息可读；少数本地化报错串可能出现替换字符，属正常。
    """
    print(f"$ {' '.join(str(c) for c in cmd)}", flush=True)
    proc = subprocess.Popen(
        [str(c) for c in cmd],
        cwd=str(cwd),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        bufsize=0,
    )

    chunks = []
    fd = proc.stdout.fileno()
    while True:
        try:
            # 用 os.read：有多少读多少，立刻返回。
            # 别用 BufferedReader.read(n) —— 它要攒够 n 字节才返回，就不实时了。
            chunk = os.read(fd, 4096)
        except OSError:
            break
        if not chunk:
            break
        chunks.append(chunk)
        print(chunk.decode("utf-8", "replace"), end="", flush=True)

    proc.wait()
    return proc.returncode, b"".join(chunks).decode("utf-8", "replace")


def explain_pipe_failure():
    rule()
    banner("  无法继续：Dart 无法创建子进程")
    rule()
    banner()
    banner("  现象：错误信息里出现「所有的管道范例都在使用中」或 ERROR_PIPE_BUSY。")
    banner("        （常见的首个失败点是 flutter --version —— 它内部要 spawn")
    banner("          git log 去算 framework age，同样会踩到这个问题。）")
    banner()
    banner("  原因：Dart 在 Windows 上建子进程时，会用命名管道接管新进程的 stdio，")
    banner("        其中给 stdin 用的是「OUTBOUND 管道 + GENERIC_READ 连接」这个组合。")
    banner("        该系统环境里以 GENERIC_READ 连接命名管道会一律返回 231，")
    banner("        于是 Dart 报 ProcessException，后续 pub / analyze / build 全都起不来。")
    banner()
    banner("  这不是项目代码的问题，需要从系统侧排查：")
    banner("    1. 系统定制方案（如 AtlasOS 等）的加固策略")
    banner("    2. 安全软件 / EDR 的命名管道防护")
    banner("    3. 组策略、WDAC 中的管道限制")
    banner("    4. 或改在另一台机器 / 虚拟机里构建")
    banner()
    banner("  自检脚本：python tools\\check_pipe_support.py")
    rule()


def fail_with(out, fallback_message):
    """统一失败处理：命中管道特征就打印专门解释，否则给一般提示。"""
    print(flush=True)
    if any(marker in out for marker in PIPE_ERROR_MARKERS):
        explain_pipe_failure()
    else:
        banner(fallback_message)
    return 1


# ---------------------------------------------------------------- 主流程

def get_pubspec_version():
    """从 pubspec.yaml 取 version 字段的应用版本（去掉 +build 号）。"""
    pubspec = APP_DIR / "pubspec.yaml"
    m = re.search(r"^version:\s*(\S+)", pubspec.read_text(encoding="utf-8"), re.M)
    if not m:
        return "0.0.0"
    return m.group(1).split("+")[0]


def deploy_danmu_service(release_dir: Path):
    """把内置弹幕服务复制进 Release（exe 旁的 danmu-api/）。

    DanmakuServiceHost 在运行时按「exe 旁 danmu-api/ → 逐级向上 tools/danmu-api」
    找服务目录，所以打包后放 exe 旁即可被识别；开发构建则天然命中仓库目录。
    """
    if not (DANMU_API_SRC / "danmu_api" / "server.js").is_file():
        banner("[5/5] 跳过内置弹幕服务：未找到源目录")
        banner(f"       预期位置：{DANMU_API_SRC}")
        return
    dst = release_dir / "danmu-api"
    if dst.exists():
        shutil.rmtree(dst, ignore_errors=True)
    banner("[5/5] 部署内置弹幕服务（含 Node 绿色运行时，约 190MB）")
    shutil.copytree(
        DANMU_API_SRC,
        dst,
        ignore=shutil.ignore_patterns("server.log", "__pycache__", "*.log"),
    )
    size_mb = sum(f.stat().st_size for f in dst.rglob("*") if f.is_file()) // (1024 * 1024)
    banner(f"       已部署：{dst}（{size_mb} MB）")
    if not (dst / "runtime" / "node.exe").is_file():
        banner("       [警告] runtime/node.exe 缺失 —— 朋友机器上没装 Node.js 时")
        banner("       内置弹幕服务起不来（应用会弹下载引导，弹幕走备用源）。")
    banner()


def make_green_zip(release_dir: Path):
    """把 Release 目录压成绿色版 zip（解压即用，含内置弹幕服务）。"""
    version = get_pubspec_version()
    DELIVERABLES_DIR.mkdir(parents=True, exist_ok=True)
    zip_path = DELIVERABLES_DIR / f"Perzutv-v{version}-win64-绿色版.zip"
    banner(f"[打包] 绿色版 zip：{zip_path}")
    banner("       内容较大（内置 Node + 弹幕依赖），压缩需要一会儿，请勿关窗口。")
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as zf:
        for root, _dirs, files in os.walk(release_dir):
            for name in files:
                full = Path(root) / name
                arcname = full.relative_to(release_dir)
                zf.write(full, str(arcname))
    size_mb = zip_path.stat().st_size // (1024 * 1024)
    banner(f"       完成：{zip_path}（{size_mb} MB）")
    banner()


def main():
    do_clean = "clean" in sys.argv[1:]
    do_zip = "no-zip" not in sys.argv[1:]

    banner()
    rule()
    banner("  Perzutv 构建（Windows 桌面版）")
    rule()
    banner()
    banner(f"  项目目录：{APP_DIR}")
    banner(f"  Flutter ：{FLUTTER}")
    banner()

    if not FLUTTER.is_file():
        banner(f"[错误] 找不到 Flutter：{FLUTTER}")
        banner("       请确认 Flutter SDK 路径，或修改本脚本里的 FLUTTER_BIN。")
        return 1

    if not (APP_DIR / "pubspec.yaml").is_file():
        banner(f"[错误] 找不到项目：{APP_DIR / 'pubspec.yaml'}")
        return 1

    env = build_env()
    APP_DIR.mkdir(parents=True, exist_ok=True)

    # 1/4 版本
    # 注意：flutter --version 自己就会 spawn `git log` 去算 framework age，
    # 所以在受限环境里这一步就会踩到管道问题 —— 失败时同样要给出解释。
    banner("[1/5] Flutter 版本")
    code, out = run([FLUTTER, "--version"], env)
    if code != 0:
        return fail_with(out, "[失败] flutter --version 执行失败")
    banner()

    # 2/4 清理
    if do_clean:
        banner("[2/5] 清理旧产物")
        for name in ("build", ".dart_tool"):
            target = APP_DIR / name
            if target.exists():
                shutil.rmtree(target, ignore_errors=True)
                banner(f"       已删除 {name}")
        banner()

    # 3/4 依赖
    banner("[3/5] 拉取依赖")
    banner("       首次运行会比较久：要下载全部依赖，还要 clone media_kit 的")
    banner("       git 依赖（上游自维护的 fork），国内可能几分钟。")
    banner("       输出是实时的，只要还在滚就是在干活，请勿关窗口。")
    banner()
    code, out = run([FLUTTER, "pub", "get"], env)
    if code != 0:
        return fail_with(out, "[失败] 依赖拉取失败，请查看上面的输出。")
    banner()

    # 凭据
    defines = get_credentials_defines()
    if defines:
        banner("       已载入 .perzutv_build_defines.env（弹幕凭据）")
    else:
        banner("       未找到 .perzutv_build_defines.env")
        banner("       构建产物将无法加载弹幕（弹弹play 需要 AppId/AppSecret）")
    banner()

    # 4/4 构建
    banner("[4/5] 构建 Windows 桌面版（release）")

    # 改过 project() 名之后，CMake 缓存里会留着旧的 target 名，
    # 直接构建会报 "No target kazumi"。这里自动认出来并清理。
    ensure_cmake_cache_fresh()

    # ech_http / media_kit 的 native assets 钩子都要从 GitHub Releases 拉预编译包，
    # 国内直连会超时或龟速。这里提前把包放进钩子的缓存目录
    # （两个钩子都是内容寻址 + SHA256 校验，哈希对得上就跳过下载）。
    # 缓存在 .dart_tool 下，会被 flutter clean 清掉，所以每次构建都兜一次底。
    banner("       检查 native assets 预编译依赖缓存 ...")
    if not ensure_hook_prebuilts("windows"):
        banner()
        banner("[失败] 预编译依赖下载失败（网络问题）。")
        banner("       可稍后重试，或手动执行：")
        banner("         python tools\\hooks_prebuilt.py windows")
        return 1

    banner("       首次构建会编译全部原生代码，可能十几分钟，同样请勿关窗口。")
    banner()
    code, out = run([FLUTTER, "build", "windows", "--release", *defines], env)
    if code != 0:
        return fail_with(out, "[失败] 构建失败，请查看上面的输出。")

    release_dir = APP_DIR / "build" / "windows" / "x64" / "runner" / "Release"
    banner()
    rule()
    banner("  构建成功")
    rule()
    banner(f"  产物目录：{release_dir}")
    banner()
    if release_dir.is_dir():
        for item in sorted(release_dir.iterdir()):
            marker = "/" if item.is_dir() else ""
            banner(f"    {item.name}{marker}")
        banner()

        # 5/5 内置弹幕服务 + 绿色版打包
        deploy_danmu_service(release_dir)
        if do_zip:
            make_green_zip(release_dir)
    return 0


if __name__ == "__main__":
    sys.exit(main())
