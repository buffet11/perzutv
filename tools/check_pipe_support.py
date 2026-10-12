"""
检查本机能否运行 Dart/Flutter 构建。

背景
----
Dart 在 Windows 上创建子进程时，固定会用命名管道接管子进程的 stdio：

    1. CreateNamedPipeW(name, PIPE_ACCESS_OUTBOUND | FILE_FLAG_OVERLAPPED, ...)
    2. CreateFileW(name, GENERIC_READ, 0, ...)          <- 客户端连读端

其中第一步给 stdin 用的是 **OUTBOUND + GENERIC_READ** 这个组合。

在某些做过安全加固的系统（例如定制版 Windows 上的策略/驱动）上，
以 GENERIC_READ 连接命名管道会一律返回 ERROR_PIPE_BUSY (231)，
于是第 2 步失败，Dart 报：

    ProcessException: 所有的管道范例都在使用中。
      (at ../../runtime/bin/process_win.cc:744)

后果是 Dart 无法创建**任何**子进程，`flutter pub get` / `flutter build`
全线失败。这不是项目代码的问题。

用法
----
    python tools\\check_pipe_support.py

退出码 0 = 正常；1 = 单向命名管道被拦，Dart 构建不可用。
"""
import ctypes
import ctypes.wintypes as w
import sys
import uuid

k32 = ctypes.WinDLL("kernel32", use_last_error=True)

PIPE_ACCESS_INBOUND = 0x00000001
PIPE_ACCESS_OUTBOUND = 0x00000002
PIPE_ACCESS_DUPLEX = 0x00000003
FILE_FLAG_OVERLAPPED = 0x40000000
GENERIC_READ = 0x80000000
GENERIC_WRITE = 0x40000000
OPEN_EXISTING = 3
INVALID = ctypes.c_void_p(-1).value

k32.CreateNamedPipeW.restype = ctypes.c_void_p
k32.CreateNamedPipeW.argtypes = [
    w.LPCWSTR, w.DWORD, w.DWORD, w.DWORD, w.DWORD, w.DWORD, w.DWORD, ctypes.c_void_p
]
k32.CreateFileW.restype = ctypes.c_void_p
k32.CreateFileW.argtypes = [
    w.LPCWSTR, w.DWORD, w.DWORD, ctypes.c_void_p, w.DWORD, w.DWORD, ctypes.c_void_p
]
k32.CloseHandle.argtypes = [ctypes.c_void_p]


def probe(server_flags, client_access):
    """按 Dart 的方式建管道并连接，返回 (是否成功, 错误码)。"""
    name = "\\\\.\\Pipe\\perzutv_check_%s" % uuid.uuid4()
    server = k32.CreateNamedPipeW(
        name, server_flags, 0, 1, 1024, 1024, 0, None
    )
    if server == INVALID or not server:
        return False, ctypes.get_last_error()
    try:
        client = k32.CreateFileW(
            name, client_access, 0, None, OPEN_EXISTING, 0, None
        )
        if client != INVALID and client:
            k32.CloseHandle(client)
            return True, 0
        return False, ctypes.get_last_error()
    finally:
        k32.CloseHandle(server)


def main():
    print("=" * 62)
    print(" Dart 子进程能力自检（命名管道）")
    print("=" * 62)

    # 关键一项：Dart 给 stdin 用的就是这个组合
    ok, err = probe(PIPE_ACCESS_OUTBOUND | FILE_FLAG_OVERLAPPED, GENERIC_READ)
    print()
    print("关键项：Dart stdin 管道 (OUTBOUND + GENERIC_READ)")
    if ok:
        print("  结果：可以")
    else:
        print(f"  结果：失败  错误码 {err}")
        if err == 231:
            print("        ERROR_PIPE_BUSY —— 命名管道实例被占满/被拦截")

    # 参考项
    print()
    print("参考项：")
    for flags, fname in [
        (PIPE_ACCESS_INBOUND | FILE_FLAG_OVERLAPPED, "INBOUND"),
        (PIPE_ACCESS_DUPLEX, "DUPLEX"),
    ]:
        for acc, aname in [
            (GENERIC_READ, "GENERIC_READ"),
            (GENERIC_WRITE, "GENERIC_WRITE"),
            (GENERIC_READ | GENERIC_WRITE, "READ|WRITE"),
        ]:
            ok2, err2 = probe(flags, acc)
            status = "可以" if ok2 else f"失败 err={err2}"
            print(f"  {fname:8s} + {aname:12s} -> {status}")

    print()
    print("=" * 62)
    if ok:
        print(" 结论：单向命名管道正常，Dart/Flutter 构建应可用。")
        return 0
    print(" 结论：单向命名管道被拦截，Dart 无法创建子进程。")
    print("       flutter pub get / flutter build 会全线失败。")
    print()
    print(" 这不是项目代码的问题，需要从系统侧排查：")
    print("   1. 系统定制方案（如 AtlasOS 等）的加固策略")
    print("   2. 安全软件（杀软/EDR）的命名管道防护")
    print("   3. 组策略 / WDAC 中的管道限制")
    print("   4. 或改在另一台机器 / 虚拟机里构建")
    print("=" * 62)
    return 1


if __name__ == "__main__":
    sys.exit(main())
