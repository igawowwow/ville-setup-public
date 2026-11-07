@echo off
chcp 65001 >nul
rem ヴィレグループ 業務セットアップ（Windows）。ダブルクリック→「はい」で始まる
net session >nul 2>&1 || (powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs" & exit /b)
powershell -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/igawowwow/ville-setup-public/main/windows/install.ps1 | iex"
echo.
echo 終わりました。このウィンドウは閉じてかまいません。
pause
