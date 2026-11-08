@echo off
rem 启动 WsDoctor C# GUI（自动增量编译 + STA 窗口）
setlocal
cd /d "%~dp0"
pwsh -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
if errorlevel 1 pause
endlocal
