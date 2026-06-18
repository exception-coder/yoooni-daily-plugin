<#
.SYNOPSIS 注册 Windows 计划任务：每 4 小时自动刷新公司套件(会话外也刷新)。
          用 schtasks 创建用户级任务(无需管理员)，幂等(/F 覆盖)。
          关键：任务指向【稳定启动器】%USERPROFILE%\.kai-toolbox\run-update.ps1，
          而非版本化的 update-team-tools.ps1——后者随插件自更新换目录会让任务断掉。
          启动器运行时再定位最新版脚本。WorkspaceDir 由 update-team-tools.ps1 自动定位。
          "开 Claude Code 即刷新"由 SessionStart hook 负责，二者互补。
.PARAMETER OnlyIfExists 自愈模式：仅当任务已存在时才校准(刷新启动器 + 必要时把任务迁到启动器)；
          从未注册过则什么都不做(不擅自给用户创建任务)。由 update-team-tools.ps1 末尾调用。
.EXAMPLE  powershell -ExecutionPolicy Bypass -File .\register-autoupdate-task.ps1
#>
param([int]$EveryHours = 4, [switch]$OnlyIfExists)
$ErrorActionPreference = 'Continue'
$taskName = 'YoooniTeamToolsAutoUpdate'
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($OnlyIfExists -and -not $existing) { return }   # 自愈：从未注册过就不创建

$state = Join-Path $env:USERPROFILE '.kai-toolbox'
New-Item -ItemType Directory -Force -Path $state | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$launcher = Join-Path $state 'run-update.ps1'

# 部署/刷新稳定启动器到固定路径 + 记下源脚本作回退（都很廉价，每次都做以保持最新）
$srcLauncher = Join-Path $PSScriptRoot 'run-update.ps1'
if (Test-Path $srcLauncher) { Copy-Item $srcLauncher $launcher -Force }
[IO.File]::WriteAllText((Join-Path $state 'update-script.path'), (Join-Path $PSScriptRoot 'update-team-tools.ps1'), $utf8)

# 任务已正确指向启动器则不重建(避免每次刷新打乱触发时间)；否则(新建/旧任务写死版本路径)创建/迁移
$pointsAtLauncher = $false
if ($existing) {
  $actArgs = (($existing.Actions | ForEach-Object { $_.Arguments }) -join ' ')
  if ($actArgs -match [regex]::Escape($launcher)) { $pointsAtLauncher = $true }
}
if ($pointsAtLauncher) {
  Write-Host "Task '$taskName' already points at stable launcher; launcher refreshed." -ForegroundColor DarkGray
} else {
  $tr = "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$launcher`""
  schtasks /Create /TN $taskName /TR $tr /SC HOURLY /MO $EveryHours /F | Out-Null
  if ($LASTEXITCODE -eq 0) {
    Write-Host "Registered '$taskName' (every $EveryHours h) -> stable launcher: $launcher" -ForegroundColor Green
  } else {
    Write-Warning "schtasks create failed (exit $LASTEXITCODE). Run this script in your own terminal."
  }
}
