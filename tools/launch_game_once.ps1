param([string]$Project = "D:\休闲小岛幻境\游戏工程", [string]$Resolution = "1440x900")
$ErrorActionPreference = "Stop"
$envFile = Join-Path $Project "tools\base_env.json"
if (Test-Path $envFile) {
  $e = Get-Content -Raw $envFile | ConvertFrom-Json
  foreach ($prop in $e.PSObject.Properties) { Set-Item -Path ("env:" + $prop.Name) -Value ([string]$prop.Value) }
}
$exe = "D:\休闲小岛幻境\引擎\Godot_v4.7.2-stable_win64.exe"
$logDir = Join-Path $Project "..\开发产物\logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$stdout = Join-Path $logDir "game_stdout.log"
$stderr = Join-Path $logDir "game_stderr.log"
$p = Start-Process -FilePath $exe -ArgumentList @("--path", $Project, "--resolution", $Resolution, "--position", "80,40") -WorkingDirectory $Project -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru
$p.Id | Out-File -Encoding ascii (Join-Path $logDir ".game_pid")
Write-Output ("GAME_PID " + $p.Id)
Start-Sleep -Seconds 3
Write-Output ("ALIVE " + (-not $p.HasExited))
