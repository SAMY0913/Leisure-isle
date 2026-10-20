# 重建 Windows 图标缓存（会短暂重启 Explorer；如仍不生效请重启系统）
$ErrorActionPreference = "SilentlyContinue"
$log = "D:/休闲小岛幻境/开发产物/logs/icon_cache_refresh.log"
function Log($m){ Add-Content -Path $log -Value ((Get-Date -Format o) + "  " + $m) }
Set-Content -Path $log -Value ("start")
Log "stopping explorer"
Stop-Process -Name explorer -Force
Start-Sleep -Milliseconds 1200
$dirs = @("$env:LOCALAPPDATA\Microsoft\Windows\Explorer", "$env:LOCALAPPDATA\IconCache")
foreach ($d in $dirs) {
  if (Test-Path $d) {
    Get-ChildItem $d -Filter "iconcache_*.db" | Remove-Item -Force
    Get-ChildItem $d -Filter "thumbcache_*.db" | Remove-Item -Force
  }
}
Remove-Item "$env:LOCALAPPDATA\IconCache.db" -Force
Log "caches removed"
$ok = $false
for ($i = 0; $i -lt 6; $i++) {
  Start-Process explorer.exe
  Start-Sleep -Milliseconds 1500
  if (Get-Process -Name explorer -ErrorAction SilentlyContinue) { Log ("explorer restarted on try " + $i); $ok = $true; break }
}
if (-not $ok) { Log "FAILED to restart explorer" }
Start-Sleep -Milliseconds 800
Start-Process explorer.exe -ArgumentList "D:\休闲小岛幻境\发布"
Log ("done ok=" + $ok)
