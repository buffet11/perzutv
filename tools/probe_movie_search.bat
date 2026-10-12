@echo off
rem ============================================================
rem  Perzutv movie search probe (P1)
rem
rem  Usage: double-click this file, or
rem         probe_movie_search.bat <keyword>
rem
rem  ---------------------------------------------------------------
rem  KNOWN LIMITATION -- read this before debugging a failure.
rem
rem  "dart run" builds this package's native-asset hooks first, and
rem  media_kit's hook uses package:native_toolchain_c to locate MSVC. That
rem  resolver runs `vswhere.exe -format json -utf8` and json-decodes its
rem  stdout. On Windows with a non-UTF-8 ANSI code page (e.g. 936 / GBK) the
rem  decoded text ends up containing control characters, and decoding throws:
rem
rem      FormatException: Control character in string (at line 16, ...)
rem      at VisualStudioResolver.parseVswhere (native_toolchain_c/.../msvc.dart)
rem
rem  That is a defect in the third-party package, not in this script or in
rem  the project, and it cannot be worked around from here. "flutter build"
rem  is unaffected because it locates Visual Studio through CMake instead.
rem
rem  => On such a machine, verify through the app instead:
rem       Settings -> Resources -> Movie Sources -> probe a source
rem     Probing issues a real search request and parses the response, so it
rem     exercises exactly the same code path, minus the command line.
rem
rem  ---------------------------------------------------------------
rem  NOTE: This file is intentionally PURE ASCII.
rem    cmd.exe decodes batch files with the active code page and reads
rem    them in fixed-size blocks. Multi-byte CJK characters landing on a
rem    block boundary get split and corrupt the line. All Chinese output
rem    is produced by Dart instead.
rem
rem  NOTE: "cd /d" is required -- plain "cd" does NOT switch drives in
rem    cmd.exe. Running "cd F:\..." while on C: silently stays on C:,
rem    which is why every relative path afterwards appears missing.
rem
rem  NOTE: "call" before the batch file is required -- "dart" resolves to
rem    dart.bat. Invoking a batch file without call transfers control away
rem    permanently, so the pause below would never run and the window would
rem    close instantly. (An .exe needs no call; a .bat always does.)
rem ============================================================

setlocal

rem Switch to the app directory (this file lives in app\tools\)
cd /d "%~dp0.."
if errorlevel 1 (
    echo [ERROR] Cannot enter "%~dp0.."
    echo.
    pause
    exit /b 1
)

where dart >nul 2>nul
if errorlevel 1 (
    echo [ERROR] dart not found in PATH.
    echo         Add Flutter's bin directory to PATH, then retry.
    echo.
    pause
    exit /b 1
)

echo ============================================================
echo   Perzutv movie search probe
echo ============================================================
echo.

rem NOTE: "call" is required here, and this one is easy to miss.
rem   "dart" resolves to dart.bat, which is itself a batch file. Invoking a
rem   batch file from another batch file WITHOUT call transfers control away
rem   permanently -- the caller never resumes. So everything below this line
rem   (including the pause) would be skipped and the window would close the
rem   instant the probe finished, hiding its output.
rem ---------------------------------------------------------------
rem Set up the MSVC environment before running Dart.
rem
rem Why: "dart run" builds this package's native-asset hooks (media_kit and
rem friends need to compile native code). That compilation requires the full
rem MSVC environment -- INCLUDE / LIB / PATH -- which VsDevCmd.bat provides.
rem "flutter build" sets this up itself via CMake; a bare "dart run" does not,
rem so the hook dies with "Running build hooks failed".
rem ---------------------------------------------------------------
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if exist "%VSWHERE%" (
    for /f "usebackq delims=" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%i"
)
if defined VSDIR (
    if exist "%VSDIR%\Common7\Tools\VsDevCmd.bat" (
        echo Setting up MSVC environment ...
        call "%VSDIR%\Common7\Tools\VsDevCmd.bat" -arch=x64 -host_arch=x64 -no_logo >nul 2>&1
    )
)
if not defined VSDIR echo [WARN] Visual Studio not found; native build hooks may fail.

set "LOG=%TEMP%\perzutv_probe.log"
echo.
echo Running... output appears when finished, and is also saved to:
echo   %LOG%
echo.

call dart run tools\probe_movie_search.dart %* > "%LOG%" 2>&1
set "CODE=%ERRORLEVEL%"

type "%LOG%"

echo.
if not "%CODE%"=="0" echo Exit code: %CODE%
pause
exit /b %CODE%
