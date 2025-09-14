@echo off
chcp 65001 >nul

set LC_ALL=C

REM UTF-8環境変数を設定
set PYTHONUTF8=1
rem set PYTHONIOENCODING=utf-8:surrogateescape

REM 現在のディレクトリを取得（バッチファイルのディレクトリ）
set BASE=%~dp0

REM デバッグ情報を表示
echo Base directory: %BASE%

REM Set Python home and path
set PYTHONHOME=%BASE%
set PYTHONPATH=%BASE%

REM DLL があるディレクトリを PATH に追加
set PATH=%BASE%;%PATH%

REM Optionally set GDB data directory
set GDB_DATA_DIR=%BASE%

if exist "%BASE%gdb-multiarch.exe" (
    echo   gdb-multiarch.exe: EXISTS
) else (
    echo   gdb-multiarch.exe: NOT FOUND
    pause
    exit 1
)

echo.
echo PYTHONPATH: %PYTHONPATH%
echo.

"%BASE%gdb-multiarch.exe" --data-directory=%GDB_DATA_DIR% %*