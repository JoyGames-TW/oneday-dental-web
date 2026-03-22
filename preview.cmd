@echo off
cd /d %~dp0
echo Starting local preview server at http://127.0.0.1:5500
cmd /c npx.cmd --yes http-server .\site -p 5500
