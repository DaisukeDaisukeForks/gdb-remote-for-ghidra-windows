@echo off
setlocal enabledelayedexpansion

:: --- docker コマンド存在確認 ---
where docker >nul 2>nul
if errorlevel 1 (
    echo [ERROR] docker コマンドが見つかりません。
    exit /b 1
)

:: --- 1. docker build ---
echo === Building image ===
docker build -t gdb10 .
if errorlevel 1 (
    echo [ERROR] docker build に失敗しました。
    exit /b 1
)

:: --- 2. docker create ---
echo === Creating container ===
for /f "delims=" %%i in ('docker create gdb10') do set CID=%%i
if "!CID!"=="" (
    echo [ERROR] docker create に失敗しました。
    exit /b 1
)

:: --- 3. docker cp ---
echo === Copying artifact ===
docker cp "!CID!":/tmp/gdb-ghidra.zip ./
if errorlevel 1 (
    echo [ERROR] docker cp に失敗しました。
    docker rm -f "!CID!" >nul 2>nul
    exit /b 1
)

:: --- 後片付け ---
:: docker rm -f "!CID!" >nul 2>nul

echo === 完了しました ===
endlocal
exit /b 0
