@echo off
set LOG=D:\休闲小岛幻境\开发产物\logs\icon_refresh_cmd.log
echo start %DATE% %TIME% > "%LOG%"
taskkill /f /im explorer.exe >> "%LOG%" 2>&1
ping -n 2 127.0.0.1 >nul
del /a /f /q "%LOCALAPPDATA%\Microsoft\Windows\Explorer\iconcache_*.db" >> "%LOG%" 2>&1
del /a /f /q "%LOCALAPPDATA%\Microsoft\Windows\Explorer\thumbcache_*.db" >> "%LOG%" 2>&1
del /a /f /q "%LOCALAPPDATA%\IconCache.db" >> "%LOG%" 2>&1
echo deleted >> "%LOG%"
timeout /t 3 /nobreak >nul
tasklist /fi "imagename eq explorer.exe" >> "%LOG%" 2>&1
if errorlevel 1 (
  echo restarting manually >> "%LOG%"
  start "" explorer.exe
  timeout /t 3 /nobreak >nul
)
start "" explorer.exe "D:\休闲小岛幻境\发布"
echo done >> "%LOG%"
