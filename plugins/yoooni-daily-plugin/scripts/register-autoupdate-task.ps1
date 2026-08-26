<#
.SYNOPSIS 注册 Windows 计划任务：每 4 小时自动刷新公司套件(会话外也刷新)。
          用 schtasks 创建用户级任务(无需管理员)，幂等(/F 覆盖)。
          关键：任务指向【稳定启动器】%USERPROFILE%\.kai-toolbox\run-update.ps1，
          而非版本化的 update-team-tools.ps1——后者随插件自更新换目录会让任务断掉。
          启动器运行时再定位最新版脚本。WorkspaceDir 由 update-team-tools.ps1 自动定位。
          本脚本只在用户明确运行时注册计划任务；插件默认采用手动更新。
.PARAMETER OnlyIfExists 自愈模式：仅当任务已存在时才校准(刷新启动器 + 必要时把任务迁到启动器)；
          从未注册过则什么都不做(不擅自给用户创建任务)。由 update-team-tools.ps1 末尾调用。
.EXAMPLE  powershell -ExecutionPolicy Bypass -File .\register-autoupdate-task.ps1
#>
param([int]$EveryHours = 4, [switch]$OnlyIfExists)
$ErrorActionPreference = 'Continue'
$taskName = 'YoooniTeamToolsAutoUpdate'
$existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($OnlyIfExists -and -not $existing) { return }   # 自愈：从未注册过就不创建
$wasDisabled = $existing -and $existing.State -eq 'Disabled'

$state = Join-Path $env:USERPROFILE '.kai-toolbox'
New-Item -ItemType Directory -Force -Path $state | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)
$launcher = Join-Path $state 'run-update.ps1'
$vbs      = Join-Path $state 'run-hidden.vbs'

# 部署/刷新稳定启动器 + VBS 隐藏启动器到固定路径 + 记下源脚本作回退（都很廉价，每次都做以保持最新）
$srcLauncher = Join-Path $PSScriptRoot 'run-update.ps1'
$srcVbs      = Join-Path $PSScriptRoot 'run-hidden.vbs'
if (Test-Path $srcLauncher) { Copy-Item $srcLauncher $launcher -Force }
if (Test-Path $srcVbs)      { Copy-Item $srcVbs $vbs -Force }
[IO.File]::WriteAllText((Join-Path $state 'update-script.path'), (Join-Path $PSScriptRoot 'update-team-tools.ps1'), $utf8)

# 任务动作：经 VBS 以隐藏窗口(SW_HIDE)跑 powershell——子进程(git/npm/claude/node)继承隐藏控制台、不再闪黑框。
# （-WindowStyle Hidden 是"先开窗再藏"，挡不住那一瞬；故改用 wscript + WshShell.Run(...,0)。）
# VBS 无参时自动定位同目录 run-update.ps1，故 TR 只是单个带引号路径，避开 schtasks 嵌套引号。
$tr = "wscript.exe `"$vbs`""
$expectInterval = "PT{0}H" -f $EveryHours

# 仅当任务已正确(走 VBS 且间隔==EveryHours)才跳过重建，避免打乱触发时间；
# 否则创建/迁移——旧任务多为 powershell 直跑 + 误成每小时，会在此被纠正为 wscript 隐藏 + 4 小时。
$correct = $false
if ($existing) {
  $actArgs = (($existing.Actions | ForEach-Object { ($_.Execute + ' ' + $_.Arguments) }) -join ' ')
  $usesVbs = ($actArgs -match 'wscript') -and ($actArgs -match [regex]::Escape($vbs))
  $intv = (($existing.Triggers | ForEach-Object { $_.Repetition.Interval }) -join ',')
  if ($usesVbs -and ($intv -match [regex]::Escape($expectInterval))) { $correct = $true }
}
if ($correct) {
  Write-Host "Task '$taskName' already correct (VBS hidden launcher, every $EveryHours h); launcher refreshed." -ForegroundColor DarkGray
} else {
  schtasks /Create /TN $taskName /TR $tr /SC HOURLY /MO $EveryHours /F | Out-Null
  if ($LASTEXITCODE -eq 0) {
    if ($wasDisabled) { Disable-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null }
    Write-Host "Registered '$taskName' (every $EveryHours h, hidden via VBS) -> $launcher" -ForegroundColor Green
  } else {
    Write-Warning "schtasks create failed (exit $LASTEXITCODE). Run this script in your own terminal."
  }
}
