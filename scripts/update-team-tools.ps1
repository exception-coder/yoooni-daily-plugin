<#
.SYNOPSIS
  全自动刷新公司团队套件，两部分都无需任何 slash / 手动操作：
    [MCP 仓] git pull project-domain-knowledge / cross-project-topology
             若 project-domain-knowledge 有更新 -> npm install + npm run build
             幂等重注册 domain-knowledge / cross-topology 两个 MCP 实例
    [插件]   claude plugin marketplace update 刷新源 ->
             claude plugin update <plugin>@<marketplace> 逐个更新
             (team-standards / project-coding-profiles / yoooni-daily-plugin)，
             幂等(已最新则空跑)，有更新写 notice 提示「重启会话生效」。
  注：`claude plugin` 现已是完整 CLI，插件更新可全脚本化；早期"插件只能走 slash"的限制已不再适用。
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
$anyChanged = $false

foreach ($d in @($mcpDir, $topoDir)) {
  if (Test-Path (Join-Path $d '.git')) {
    $before = (git -C $d rev-parse HEAD 2>$null)
    git -C $d pull --ff-only 2>&1 | ForEach-Object { Log ("  git " + $_) }
    $after  = (git -C $d rev-parse HEAD 2>$null)
    if ($before -ne $after) { $anyChanged = $true }
    if (($d -eq $mcpDir) -and ($before -ne $after)) { $pdkChanged = $true }
  } else { Log ("  skip (not cloned): " + $d) }
}

if ($pdkChanged -and (Has npm)) {
  Push-Location $mcpDir
  try { Log "  npm install/build (engine updated)"; npm install 2>&1 | ForEach-Object { Log ("  npm " + $_) }; npm run build 2>&1 | ForEach-Object { Log ("  build " + $_) } }
  finally { Pop-Location }
}

$entry = Join-Path $mcpDir 'dist\server.js'
# 仅当仓库内容有更新时才重注册(触发 MCP 下次会话重启、加载新知识/引擎)；无变化不动，省churn
if ($anyChanged -and (Has claude) -and (Test-Path $entry)) {
  $domainKb = Join-Path $mcpDir 'knowledge'
  $topoKb   = Join-Path $topoDir 'knowledge'
  claude mcp remove domain-knowledge -s $McpScope 2>$null | Out-Null
  # '--' 必须带引号：裸 -- 会被 PowerShell 吞掉，导致变参 -e 吞掉 node+路径而报 missing commandOrUrl
  claude mcp add domain-knowledge -s $McpScope -e "DOMAIN_KB_DIR=$domainKb" '--' node "$entry" 2>&1 | ForEach-Object { Log ("  mcp " + $_) }
  if (Test-Path $topoKb) {
    claude mcp remove cross-topology -s $McpScope 2>$null | Out-Null
    claude mcp add cross-topology -s $McpScope -e "DOMAIN_KB_DIR=$topoKb" '--' node "$entry" 2>&1 | ForEach-Object { Log ("  mcp " + $_) }
  }
}

# --- 插件：claude plugin 现为完整 CLI，可全自动更新(无需本地克隆源码，直接走已注册 marketplace) ---
# 必须用全限定名 plugin@marketplace(裸名会报 not found)；先 marketplace update 刷源，再逐个 update。
# 公司三插件的 marketplace 名与插件名一致 -> 用 "{0}@{0}"。
$pluginUpdated = @()
if (Has claude) {
  claude plugin marketplace update 2>&1 | ForEach-Object { Log ("  mkt " + $_) }
  foreach ($p in @('team-standards','project-coding-profiles','yoooni-daily-plugin')) {
    $ref = "{0}@{0}" -f $p
    $out = (claude plugin update $ref -s $McpScope 2>&1 | Out-String)
    ($out -split "`r?`n") | Where-Object { $_.Trim() } | ForEach-Object { Log ("  plg " + $_.Trim()) }
    $mm = [regex]::Match($out, 'updated from\s+(\S+)\s+to\s+(\S+)')
    if ($mm.Success) { $pluginUpdated += ("{0} {1}→{2}" -f $p, $mm.Groups[1].Value, $mm.Groups[2].Value) }
  }
}
if ($pluginUpdated.Count -gt 0) {
  [IO.File]::WriteAllText($notice, ("团队插件已自动更新：{0}。重启 Claude Code 会话即生效。" -f ($pluginUpdated -join '；')), $utf8)
} else {
  [IO.File]::WriteAllText($notice, "", $utf8)
}
Log ("=== update done (pdkChanged={0}, pluginsUpdated={1}) ===" -f $pdkChanged, $pluginUpdated.Count)
