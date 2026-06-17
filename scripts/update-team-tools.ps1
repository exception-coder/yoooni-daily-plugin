<#
.SYNOPSIS
  自动刷新公司团队套件「可脚本化部分」——两个 MCP 仓(普通命令，无需 slash)：
    git pull project-domain-knowledge / cross-project-topology
    若 project-domain-knowledge 有更新 -> npm install + npm run build
    幂等重注册 domain-knowledge / cross-topology 两个 MCP 实例
  插件(team-standards / project-coding-profiles)走 /plugin slash，脚本代不了——
  仅当本地有插件源码且落后远程时，写提示到 notice 文件，由 hook/skill 浮现。
.NOTES 被 SessionStart hook(每日后台)、Windows 计划任务、update-team-tools skill 共用。
#>
param(
  [string]$WorkspaceDir,
  [ValidateSet('user','local','project')][string]$McpScope = 'user'
)
$ErrorActionPreference = 'Continue'
$utf8 = New-Object System.Text.UTF8Encoding($false)   # 无 BOM
$state  = Join-Path $env:USERPROFILE '.kai-toolbox'
New-Item -ItemType Directory -Force -Path $state | Out-Null
$log    = Join-Path $state 'team-tools-update.log'
$notice = Join-Path $state 'team-tools-update.notice'
$cfg    = Join-Path $state 'workspace.path'
function Log($m){ Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) }
function Has($c){ [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function HasPdk($w){ return ($w -and (Test-Path (Join-Path $w 'project-domain-knowledge\.git'))) }

# --- 自动定位 WorkspaceDir：参数 -> 环境变量 -> 配置 -> claude mcp 解析 -> 跨盘探测 -> 默认 ---
$cands = @()
if ($WorkspaceDir) { $cands += $WorkspaceDir }
if ($env:YOOONI_WORKSPACE_DIR) { $cands += $env:YOOONI_WORKSPACE_DIR }
if (Test-Path $cfg) { $cands += (((Get-Content $cfg -Raw) -replace "^\xEF\xBB\xBF","") -replace "﻿","").Trim() }
if (Has claude) {
  $info = @((claude mcp get domain-knowledge 2>$null); (claude mcp list 2>$null)) -join "`n"
  $m = [regex]::Match($info, '([A-Za-z]:[\/].*?)[\/]project-domain-knowledge[\/]dist[\/]server\.js')
  if ($m.Success) { $cands += $m.Groups[1].Value }
}
$cands += (Join-Path $env:USERPROFILE 'myWork')
foreach ($drv in @('C:','D:','E:','F:')) { $cands += ("{0}\Users\{1}\myWork" -f $drv, $env:USERNAME) }
$WorkspaceDir = $null
foreach ($c in $cands) { if (HasPdk $c) { $WorkspaceDir = $c; break } }
if (-not $WorkspaceDir) { $WorkspaceDir = (Join-Path $env:USERPROFILE 'myWork') }
[IO.File]::WriteAllText($cfg, $WorkspaceDir, $utf8)   # 记住(无 BOM)，下次直接用

Log "=== update start (ws=$WorkspaceDir, scope=$McpScope) ==="
$mcpDir  = Join-Path $WorkspaceDir 'project-domain-knowledge'
$topoDir = Join-Path $WorkspaceDir 'cross-project-topology'
$pdkChanged = $false

foreach ($d in @($mcpDir, $topoDir)) {
  if (Test-Path (Join-Path $d '.git')) {
    $before = (git -C $d rev-parse HEAD 2>$null)
    git -C $d pull --ff-only 2>&1 | ForEach-Object { Log ("  git " + $_) }
    $after  = (git -C $d rev-parse HEAD 2>$null)
    if (($d -eq $mcpDir) -and ($before -ne $after)) { $pdkChanged = $true }
  } else { Log ("  skip (not cloned): " + $d) }
}

if ($pdkChanged -and (Has npm)) {
  Push-Location $mcpDir
  try { Log "  npm install/build (engine updated)"; npm install 2>&1 | ForEach-Object { Log ("  npm " + $_) }; npm run build 2>&1 | ForEach-Object { Log ("  build " + $_) } }
  finally { Pop-Location }
}

$entry = Join-Path $mcpDir 'dist\server.js'
if ((Has claude) -and (Test-Path $entry)) {
  $domainKb = Join-Path $mcpDir 'knowledge'
  $topoKb   = Join-Path $topoDir 'knowledge'
  claude mcp remove domain-knowledge -s $McpScope 2>$null | Out-Null
  claude mcp add domain-knowledge -s $McpScope -e "DOMAIN_KB_DIR=$domainKb" -- node "$entry" 2>&1 | ForEach-Object { Log ("  mcp " + $_) }
  if (Test-Path $topoKb) {
    claude mcp remove cross-topology -s $McpScope 2>$null | Out-Null
    claude mcp add cross-topology -s $McpScope -e "DOMAIN_KB_DIR=$topoKb" -- node "$entry" 2>&1 | ForEach-Object { Log ("  mcp " + $_) }
  }
}

$pluginMsgs = @()
foreach ($p in @('team-standards','project-coding-profiles')) {
  $pd = Join-Path $WorkspaceDir $p
  if (Test-Path (Join-Path $pd '.git')) {
    git -C $pd fetch --quiet 2>$null
    $localRev  = (git -C $pd rev-parse '@' 2>$null)
    $remoteRev = (git -C $pd rev-parse '@{u}' 2>$null)
    if ($localRev -and $remoteRev -and ($localRev -ne $remoteRev)) { $pluginMsgs += $p }
  }
}
if ($pluginMsgs.Count -gt 0) {
  [IO.File]::WriteAllText($notice, ("团队插件有新版({0})：在 Claude Code 里说『更新公司套件』或跑 /plugin marketplace update 后重装。" -f ($pluginMsgs -join ' / ')), $utf8)
} else {
  [IO.File]::WriteAllText($notice, "", $utf8)
}
Log "=== update done (pdkChanged=$pdkChanged) ==="
