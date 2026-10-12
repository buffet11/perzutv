@echo off
rem ============================================================
rem  Perzutv build launcher (Windows desktop)
rem
rem  Usage:  build.bat          -> build
rem          build.bat clean    -> clean then build
rem
rem  NOTE: This file is intentionally PURE ASCII.
rem    cmd.exe reads batch files in fixed-size blocks and decodes them with the
rem    active code page. Multi-byte CJK characters landing on a block boundary
rem    get split, which truncates a line into two bogus commands -- this breaks
rem    even short scripts. A UTF-8 BOM is worse: it turns the first line into
rem    "<BOM>@echo off", disabling @echo off entirely.
rem    So all Chinese output is printed by the Python driver instead.
rem
rem  NOTE: %~dp0 ends with a backslash. Every concatenation below therefore
rem    adds its own separator explicitly. APP_DIR strips that trailing
rem    backslash because it is used as a complete path, not as a prefix.
rem ============================================================

setlocal

set "ROOT=%~dp0"
set "APP_DIR=%ROOT:~0,-1%"
set "DRIVER=%ROOT%tools\build_windows.py"

set "PY="
rem NOTE: "where python" can hit the Microsoft Store stub alias (0-byte
rem reparse point in %LOCALAPPDATA%\WindowsApps) which prints
rem "Python was not found" and exits 9009. Probe every candidate with a
rem real "--version" run before trusting it.
if exist "D:\path\python\python.exe" set "PY=D:\path\python\python.exe"
if not defined PY if exist "%LOCALAPPDATA%\Programs\Python\Python313\python.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Python313\python.exe"
if not defined PY if exist "%LOCALAPPDATA%\Programs\Python\Python312\python.exe" set "PY=%LOCALAPPDATA%\Programs\Python\Python312\python.exe"
if not defined PY (
    where python >nul 2>nul && set "PY=python"
)
if defined PY (
    "%PY%" --version >nul 2>nul
    if errorlevel 1 set "PY="
)
if not defined PY (
    echo [ERROR] No working Python interpreter found.
    echo         Searched: D:\path\python, %%LOCALAPPDATA%%\Programs\Python, PATH.
    echo         If "python" opens the Microsoft Store, disable the alias at:
    echo         Settings ^> Apps ^> Advanced app settings ^> App execution aliases
    echo         or set PY near the top of this file.
    echo.
    pause
    exit /b 1
)

if not exist "%DRIVER%" (
    echo [ERROR] Driver not found: %DRIVER%
    echo         This launcher must sit in the Flutter project root, next to the "tools" folder.
    echo.
    pause
    exit /b 1
)

if not exist "%APP_DIR%\pubspec.yaml" (
    echo [ERROR] Project not found: %APP_DIR%\pubspec.yaml
    echo.
    pause
    exit /b 1
)

"%PY%" "%DRIVER%" %*
set "CODE=%ERRORLEVEL%"

if not "%CODE%"=="0" (
    echo.
    echo Build did not complete. Exit code: %CODE%
)

pause
exit /b %CODE%
