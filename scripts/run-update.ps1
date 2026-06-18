<#
.SYNOPSIS
  稳定启动器（路径永不变）——计划任务固定指向本文件，运行时定位"当前最新版"插件里的
  update-team-tools.ps1 再调用它。
  解决：claude plugin 缓存目录带版本号（...\cache\yoooni-daily-plugin\yoooni-daily-plugin\<版本>\），
  插件自更新后旧版本目录会被回收，若计划任务写死旧路径就会断掉。本启动器在固定路径
  %USERPROFILE%\.kai-toolbox\run-update.ps1，由 register-autoupdate-task.ps1 部署。
.NOTES 定位顺序：缓存里最高版本 > 回退路径(注册时记下的源脚本，dev 仓/自定义安装位置)。
#>
$ErrorActionPreference = 'Continue'
$state = Join-Path $env:USERPROFILE '.kai-toolbox'
function Log($m) {
  New-Item -ItemType Directory -Force -Path $state | Out-Null
  Add-Content -Path (Join-Path $state 'team-tools-update.log') -Value ("[{0}] launcher: {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m)
}

$target = $null
$cacheRoot = Join-Path $env:USERPROFILE '.claude\plugins\cache\yoooni-daily-plugin\yoooni-daily-plugin'
if (Test-Path $cacheRoot) {
  $target = Get-ChildItem $cacheRoot -Directory -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName 'scripts\update-team-tools.ps1') } |
    Sort-Object { try { [version](($_.Name -split '[^0-9.]')[0]) } catch { [version]'0.0.0' } } |
    Select-Object -Last 1 |
    ForEach-Object { Join-Path $_.FullName 'scripts\update-team-tools.ps1' }
}
if (-not $target) {
  # 回退：注册时记下的源脚本路径（dev 仓 / 自定义安装位置）
  $fb = Join-Path $state 'update-script.path'
  if (Test-Path $fb) {
    $p = (((Get-Content $fb -Raw) -replace "^\xEF\xBB\xBF", "")).Trim()
    if ($p -and (Test-Path $p)) { $target = $p }
  }
}

if ($target) {
  Log "-> $target"
  & $target
}
else {
  Log "未找到 update-team-tools.ps1（缓存与回退路径均无）"
}
