@echo off
cd /d "%~dp0"
echo 正在以管理员身份启动安装程序...
powershell -ExecutionPolicy Bypass -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File \"%~dp0install.ps1\"'"
pause
