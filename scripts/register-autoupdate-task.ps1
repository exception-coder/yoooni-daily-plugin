<#
.SYNOPSIS 注册 Windows 计划任务：每 4 小时自动跑 update-team-tools.ps1(会话外也刷新)。
          用 schtasks 创建用户级任务(无需管理员)，幂等(/F 覆盖)。
          WorkspaceDir 由 update-team-tools.ps1 自动定位，无需传参。
          "开 Claude Code 即刷新"由 SessionStart hook 负责，二者互补。
.EXAMPLE  powershell -ExecutionPolicy Bypass -File .\register-autoupdate-task.ps1
#>
param([int]$EveryHours = 4)
$ErrorActionPreference = 'Stop'
$ps1 = Join-Path $PSScriptRoot 'update-team-tools.ps1'
$taskName = 'YoooniTeamToolsAutoUpdate'
$tr = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ps1`""
schtasks /Create /TN $taskName /TR $tr /SC HOURLY /MO $EveryHours /F | Out-Null
if ($LASTEXITCODE -eq 0) {
  Write-Host "Registered scheduled task '$taskName' (every $EveryHours h). update-team-tools.ps1 auto-detects repo dir." -ForegroundColor Green
} else {
  Write-Warning "schtasks create failed (exit $LASTEXITCODE). Run this script in your own terminal."
}
