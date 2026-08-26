<#
.SYNOPSIS
  用户触发后，一次刷新公司团队套件的两个部分：
    [MCP 仓] git pull project-domain-knowledge / cross-project-topology
             若 project-domain-knowledge 有更新 -> npm ci（有 lockfile）+ npm run build
             幂等重注册 domain-knowledge / cross-topology 两个 MCP 实例
    [插件]   claude plugin marketplace update 刷新源 ->
             claude plugin update <plugin>@<marketplace> 逐个更新
             (team-standards / project-coding-profiles / yoooni-daily-plugin)，
             幂等(已最新则空跑)，有更新写 notice 提示「重启会话生效」。
  注：`claude plugin` 现已是完整 CLI，插件更新可全脚本化；早期"插件只能走 slash"的限制已不再适用。
.NOTES 由用户手动运行、显式注册的 Windows 计划任务或 update-team-tools skill 调用。
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
$maxCodexConfigBytes = 16MB
function Log($m){
  if ((Test-Path $log) -and (Get-Item $log).Length -gt 10MB) {
    Move-Item -LiteralPath $log -Destination "$log.1" -Force
  }
  Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m)
}
$lockHelper = Join-Path $PSScriptRoot 'update-lock.ps1'
if (-not (Test-Path -LiteralPath $lockHelper)) { throw "update lock helper is missing: $lockHelper" }
. $lockHelper
$updateMutex = Enter-YoooniUpdateMutex
if ($null -eq $updateMutex) { Log 'skip: another team-tools update is already running'; return }
try {
function Has($c){ [bool](Get-Command $c -ErrorAction SilentlyContinue) }
function HasPdk($w){ return ($w -and (Test-Path (Join-Path $w 'project-domain-knowledge\.git'))) }
function Escape-TomlString($s){ return (($s -replace '\\','/') -replace '"','\"') }

function Read-CodexConfigUtf8($configPath) {
  if (-not (Test-Path -LiteralPath $configPath)) { return '' }
  $size = (Get-Item -LiteralPath $configPath).Length
  if ($size -gt $maxCodexConfigBytes) {
    throw "Refuse to read oversized Codex config ($size bytes; limit $maxCodexConfigBytes): $configPath"
  }
  $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
  return $strictUtf8.GetString([IO.File]::ReadAllBytes($configPath))
}

function Write-CodexConfigUtf8($configPath, $text, $expectedText) {
  $dir = Split-Path $configPath
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $tmp = Join-Path $dir (".{0}.{1}.tmp" -f (Split-Path $configPath -Leaf), [guid]::NewGuid().ToString('N'))
  $backup = "$configPath.yoooni-safe.bak"
  try {
    [IO.File]::WriteAllText($tmp, $text, $utf8)
    $null = (New-Object System.Text.UTF8Encoding($false, $true)).GetString([IO.File]::ReadAllBytes($tmp))
    if ((Get-Item $tmp).Length -gt $maxCodexConfigBytes) { throw "Refuse to write oversized Codex config: $tmp" }
    if ((Read-CodexConfigUtf8 $configPath) -ne $expectedText) { throw "Codex config changed concurrently; refusing to overwrite: $configPath" }
    if (Test-Path $configPath) { [IO.File]::Replace($tmp, $configPath, $backup, $true) }
    else { [IO.File]::Move($tmp, $configPath) }
  }
  finally { if (Test-Path $tmp) { Remove-Item -LiteralPath $tmp -Force } }
}

function New-CodexMcpBlock($name, $server) {
  $argsToml = ($server.args | ForEach-Object { '"' + (Escape-TomlString $_) + '"' }) -join ', '
  $envPairs = @()
  if ($server.env) {
    foreach ($p in $server.env.PSObject.Properties) {
      $envPairs += '"' + $p.Name + '" = "' + (Escape-TomlString $p.Value) + '"'
    }
  }
  $envToml = $envPairs -join ', '
  $block = "`n[mcp_servers.`"$name`"]`n"
  $block += "command = `"$($server.command)`"`n"
  $block += "args = [$argsToml]`n"
  if ($envToml) { $block += "env = { $envToml }`n" }
  return $block
}

function Sync-CodexMcpConfig($codexRoot, $configPath, $servers) {
  if (-not (Test-Path $codexRoot)) { return $null }
  $existing = ''
  $existing = Read-CodexConfigUtf8 $configPath
  if ($null -eq $existing) { $existing = '' }

  $text = $existing
  $added = @()
  $updated = @()
  foreach ($name in $servers.Keys) {
    $block = New-CodexMcpBlock $name $servers[$name]
    $escaped = [regex]::Escape($name)
    $pattern = '(?ms)^\[mcp_servers\.(?:"' + $escaped + '"|' + $escaped + ')\]\s*\r?\n.*?(?=^\[(?!mcp_servers\.(?:"' + $escaped + '"|' + $escaped + ')\.)|\z)'
    if ($text -match $pattern) {
      $current = $Matches[0]
      if ($current.Trim() -ne $block.Trim()) {
        $text = [regex]::Replace($text, $pattern, $block.TrimStart(), 1)
        $updated += $name
      }
    }
    else {
      $sep = if ($text -and -not $text.EndsWith("`n")) { "`n" } else { '' }
      $text += $sep + $block
      $added += $name
    }
  }

  if ($text -ne $existing) {
    $dir = Split-Path $configPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Write-CodexConfigUtf8 $configPath $text $existing
  }
  return [pscustomobject]@{ Added = $added; Updated = $updated }
}

function Sync-JsonMcpConfig($toolRoot, $configPath, $servers) {
  if (-not (Test-Path $toolRoot)) { return $null }
  $root = $null
  if (Test-Path $configPath) {
    try { $root = Get-Content $configPath -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $root = $null }
  }
  if (-not $root) { $root = [pscustomobject]@{} }
  if (-not ($root.PSObject.Properties.Name -contains 'mcpServers')) {
    $root | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([pscustomobject]@{})
  }

  $added = @()
  $updated = @()
  foreach ($name in $servers.Keys) {
    $nextJson = $servers[$name] | ConvertTo-Json -Depth 12 -Compress
    if ($root.mcpServers.PSObject.Properties.Name -contains $name) {
      $currentJson = $root.mcpServers.$name | ConvertTo-Json -Depth 12 -Compress
      if ($currentJson -ne $nextJson) {
        $root.mcpServers.$name = $servers[$name]
        $updated += $name
      }
    }
    else {
      $root.mcpServers | Add-Member -NotePropertyName $name -NotePropertyValue $servers[$name]
      $added += $name
    }
  }

  if ($added.Count -or $updated.Count) {
    $dir = Split-Path $configPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($configPath, ($root | ConvertTo-Json -Depth 12), $utf8)
  }
  return [pscustomobject]@{ Added = $added; Updated = $updated }
}

function Find-RepoDir($name, $workspaceDir) {
  $candidate = Join-Path $workspaceDir $name
  if (Test-Path (Join-Path $candidate '.git')) { return $candidate }

  $dir = $PSScriptRoot
  while ($dir) {
    if ((Split-Path $dir -Leaf) -eq $name -and (Test-Path (Join-Path $dir '.git'))) { return $dir }
    $parent = Split-Path $dir -Parent
    if (-not $parent -or $parent -eq $dir) { break }
    $dir = $parent
  }
  return $candidate
}

function Get-GitRevision($repoDir) {
  if (-not (Test-Path (Join-Path $repoDir '.git'))) { return '' }
  return ((git -C $repoDir rev-parse HEAD 2>$null) | Out-String).Trim()
}

function Get-CodexPluginDir($repoDir, $pluginName) {
  $dir = Join-Path $repoDir ("plugins\{0}" -f $pluginName)
  if (Test-Path (Join-Path $dir '.codex-plugin\plugin.json')) { return $dir }
  if (Test-Path (Join-Path $repoDir '.codex-plugin\plugin.json')) { return $repoDir }
  return $dir
}

function New-CodexMarketplaceBlock($name, $source, $revision) {
  $updated = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
  $block = "`n[marketplaces.$name]`n"
  $block += "last_updated = `"$updated`"`n"
  if ($revision) { $block += "last_revision = `"$revision`"`n" }
  $block += "source_type = `"git`"`n"
  $block += "source = `"$source`"`n"
  return $block
}

function New-CodexPluginBlock($pluginRef) {
  return "`n[plugins.`"$pluginRef`"]`nenabled = true`n"
}

function Sync-TomlTableBlock($text, $pattern, $block, [ref]$changed) {
  if ($text -match $pattern) {
    $current = $Matches[0]
    if ($current.Trim() -ne $block.Trim()) {
      $changed.Value = $true
      return [regex]::Replace($text, $pattern, $block.TrimStart(), 1)
    }
    return $text
  }

  $sep = if ($text -and -not $text.EndsWith("`n")) { "`n" } else { '' }
  $changed.Value = $true
  return $text + $sep + $block
}

function Sync-CodexPlugins($codexRoot, $configPath, $plugins) {
  if (-not (Test-Path $codexRoot)) { return $null }
  $existing = ''
  $existing = Read-CodexConfigUtf8 $configPath
  if ($null -eq $existing) { $existing = '' }

  $text = $existing
  $configured = @()
  $cached = @()
  $skipped = @()
  foreach ($p in $plugins) {
    $manifest = Join-Path $p.PluginDir '.codex-plugin\plugin.json'
    if (-not (Test-Path $manifest)) {
      $skipped += $p.Name
      continue
    }

    $version = '0.0.0'
    try {
      $manifestJson = Get-Content $manifest -Raw -Encoding UTF8 | ConvertFrom-Json
      if ($manifestJson.version) { $version = $manifestJson.version }
    } catch {}

    $cacheRoot = [IO.Path]::GetFullPath((Join-Path $codexRoot 'plugins\cache'))
    $cacheDir = [IO.Path]::GetFullPath((Join-Path $cacheRoot ("{0}\{1}\{2}" -f $p.Marketplace, $p.Name, $version)))
    if (-not $cacheDir.StartsWith($cacheRoot, [StringComparison]::OrdinalIgnoreCase)) {
      throw "Refuse to write outside Codex plugin cache: $cacheDir"
    }
    $stagingDir = "$cacheDir.staging.$([guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Force -Path (Split-Path $cacheDir) | Out-Null
    Copy-Item -LiteralPath $p.PluginDir -Destination $stagingDir -Recurse -Force
    if (-not (Test-Path (Join-Path $stagingDir '.codex-plugin\plugin.json'))) { throw "Invalid staged Codex plugin: $stagingDir" }
    if (Test-Path $cacheDir) { Remove-Item -LiteralPath $cacheDir -Recurse -Force }
    Move-Item -LiteralPath $stagingDir -Destination $cacheDir
    $cached += ("{0}@{1}" -f $p.Name, $version)

    $revision = Get-GitRevision $p.RepoDir
    $marketPattern = '(?ms)^\[marketplaces\.' + [regex]::Escape($p.Marketplace) + '\]\s*\r?\n.*?(?=^\[|\z)'
    $pluginRef = "{0}@{1}" -f $p.Name, $p.Marketplace
    $pluginPattern = '(?ms)^\[plugins\."' + [regex]::Escape($pluginRef) + '"\]\s*\r?\n.*?(?=^\[|\z)'
    $changed = $false
    $marketBlock = New-CodexMarketplaceBlock $p.Marketplace $p.Url $revision
    if ($text -match $marketPattern) {
      $currentStable = [regex]::Replace($Matches[0], '(?m)^last_updated\s*=.*\r?\n?', '')
      $nextStable = [regex]::Replace($marketBlock, '(?m)^last_updated\s*=.*\r?\n?', '')
      if ($currentStable.Trim() -ne $nextStable.Trim()) {
        $text = Sync-TomlTableBlock $text $marketPattern $marketBlock ([ref]$changed)
      }
    }
    else {
      $text = Sync-TomlTableBlock $text $marketPattern $marketBlock ([ref]$changed)
    }
    $text = Sync-TomlTableBlock $text $pluginPattern (New-CodexPluginBlock $pluginRef) ([ref]$changed)
    $configured += $pluginRef
  }

  if ($text -ne $existing) {
    $dir = Split-Path $configPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Write-CodexConfigUtf8 $configPath $text $existing
  }

  return [pscustomobject]@{ Configured = $configured; Cached = $cached; Skipped = $skipped }
}

function Sync-CursorRules($cursorRoot, $sourceRulesDir) {
  if (-not (Test-Path $cursorRoot)) { return $null }
  if (-not (Test-Path $sourceRulesDir)) { return [pscustomobject]@{ Synced = @(); Skipped = @('missing source rules') } }

  $targetDir = Join-Path $cursorRoot 'rules'
  New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
  $synced = @()
  foreach ($file in @(Get-ChildItem -Path $sourceRulesDir -Filter '*.mdc' -File -ErrorAction SilentlyContinue)) {
    $target = Join-Path $targetDir ("yoooni-{0}" -f $file.Name)
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    $synced += (Split-Path $target -Leaf)
  }
  return [pscustomobject]@{ Synced = $synced; Skipped = @() }
}

function Sync-KiroSteering($kiroRoot, $workspaceDir, $pluginRepos) {
  if (-not (Test-Path $kiroRoot)) { return $null }
  $targetDir = Join-Path $kiroRoot 'steering'
  New-Item -ItemType Directory -Force -Path $targetDir | Out-Null
  $target = Join-Path $targetDir 'yoooni-team-tools.md'
  $lines = @(
    '# Yoooni Team Tools',
    '',
    'Use the installed Yoooni team tools as the default coding guidance for company projects.',
    '',
    ('Workspace: {0}' -f $workspaceDir),
    ('team-standards: {0}' -f $pluginRepos['team-standards']),
    ('project-coding-profiles: {0}' -f $pluginRepos['project-coding-profiles']),
    ('yoooni-daily-plugin: {0}' -f $pluginRepos['yoooni-daily-plugin']),
    '',
    'Before editing code, follow the relevant coding standards, project profile, encoding profile, and registered MCP knowledge sources.'
  )
  [IO.File]::WriteAllText($target, ($lines -join "`n") + "`n", $utf8)
  return $target
}

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
$pluginUrls = @{
  'team-standards' = 'https://gitee.com/wyoooni/team-standards.git'
  'project-coding-profiles' = 'https://gitee.com/wyoooni/project-coding-profiles.git'
  'yoooni-daily-plugin' = 'https://gitee.com/wyoooni/yoooni-daily-plugin.git'
}
$pluginRepos = @{}
foreach ($pluginName in $pluginUrls.Keys) {
  $pluginRepos[$pluginName] = Find-RepoDir $pluginName $WorkspaceDir
}
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

foreach ($pluginName in $pluginUrls.Keys) {
  $repoDir = $pluginRepos[$pluginName]
  if (Test-Path (Join-Path $repoDir '.git')) {
    git -C $repoDir pull --ff-only 2>&1 | ForEach-Object { Log ("  git plugin " + $_) }
  } else {
    Log ("  skip plugin repo (not cloned): " + $repoDir)
  }
}

if ($pdkChanged -and (Has npm)) {
  Push-Location $mcpDir
  try {
    $installArgs = if (Test-Path (Join-Path $mcpDir 'package-lock.json')) { @('ci', '--no-audit', '--no-fund') } else { @('install', '--no-audit', '--no-fund') }
    Log ("  npm {0}/build (engine updated)" -f $installArgs[0])
    & npm @installArgs 2>&1 | ForEach-Object { Log ("  npm " + $_) }
    if ($LASTEXITCODE -ne 0) { throw "npm $($installArgs[0]) failed: exit $LASTEXITCODE" }
    & npm run build 2>&1 | ForEach-Object { Log ("  build " + $_) }
    if ($LASTEXITCODE -ne 0) { throw "npm run build failed: exit $LASTEXITCODE" }
  }
  finally { Pop-Location }
}

$entry = Join-Path $mcpDir 'dist\server.js'
$domainKb = Join-Path $mcpDir 'knowledge'
$topoKb   = Join-Path $topoDir 'knowledge'
# 仅当仓库内容有更新时才重注册(触发 MCP 下次会话重启、加载新知识/引擎)；无变化不动，省churn
if ($anyChanged -and (Has claude) -and (Test-Path $entry)) {
  claude mcp remove domain-knowledge -s $McpScope 2>$null | Out-Null
  # '--' 必须带引号：裸 -- 会被 PowerShell 吞掉，导致变参 -e 吞掉 node+路径而报 missing commandOrUrl
  claude mcp add domain-knowledge -s $McpScope -e "DOMAIN_KB_DIR=$domainKb" '--' node "$entry" 2>&1 | ForEach-Object { Log ("  mcp " + $_) }
  if (Test-Path $topoKb) {
    claude mcp remove cross-topology -s $McpScope 2>$null | Out-Null
    claude mcp add cross-topology -s $McpScope -e "DOMAIN_KB_DIR=$topoKb" '--' node "$entry" 2>&1 | ForEach-Object { Log ("  mcp " + $_) }
  }
}

if (Test-Path $entry) {
  $codexRoot = Join-Path $env:USERPROFILE '.codex'
  $codexCfg = Join-Path $codexRoot 'config.toml'
  $entryFwd = $entry -replace '\\','/'
  $domainKbFwd = $domainKb -replace '\\','/'
  $codexMcp = [ordered]@{
    'domain-knowledge' = [pscustomobject]@{ command = 'node'; args = @($entryFwd); env = [pscustomobject]@{ DOMAIN_KB_DIR = $domainKbFwd } }
  }
  if (Test-Path $topoKb) {
    $topoKbFwd = $topoKb -replace '\\','/'
    $codexMcp['cross-topology'] = [pscustomobject]@{ command = 'node'; args = @($entryFwd); env = [pscustomobject]@{ DOMAIN_KB_DIR = $topoKbFwd } }
  }
  $codexResult = Sync-CodexMcpConfig $codexRoot $codexCfg $codexMcp
  if ($null -eq $codexResult) {
    Log "  codex: ~/.codex 不存在，跳过 MCP 配置同步"
  }
  elseif ($codexResult.Added.Count -or $codexResult.Updated.Count) {
    Log ("  codex: MCP synced added={0}, updated={1}" -f ($codexResult.Added -join ','), ($codexResult.Updated -join ','))
  }
  else {
    Log "  codex: MCP config already current"
  }

  $jsonMcp = [ordered]@{
    'domain-knowledge' = [pscustomobject]@{ command = 'node'; args = @($entryFwd); env = [pscustomobject]@{ DOMAIN_KB_DIR = $domainKbFwd } }
  }
  if (Test-Path $topoKb) {
    $jsonMcp['cross-topology'] = [pscustomobject]@{ command = 'node'; args = @($entryFwd); env = [pscustomobject]@{ DOMAIN_KB_DIR = $topoKbFwd } }
  }
  $toolTargets = @(
    @{ Name = 'cursor'; Root = (Join-Path $env:USERPROFILE '.cursor'); Config = (Join-Path $env:USERPROFILE '.cursor\mcp.json') },
    @{ Name = 'kiro'; Root = (Join-Path $env:USERPROFILE '.kiro'); Config = (Join-Path $env:USERPROFILE '.kiro\settings\mcp.json') }
  )
  foreach ($target in $toolTargets) {
    $syncResult = Sync-JsonMcpConfig $target.Root $target.Config $jsonMcp
    if ($null -eq $syncResult) {
      Log ("  {0}: root not found, skip MCP config" -f $target.Name)
    }
    elseif ($syncResult.Added.Count -or $syncResult.Updated.Count) {
      Log ("  {0}: MCP synced added={1}, updated={2}" -f $target.Name, ($syncResult.Added -join ','), ($syncResult.Updated -join ','))
    }
    else {
      Log ("  {0}: MCP config already current" -f $target.Name)
    }
  }
}

$codexPluginDefs = @(
  [pscustomobject]@{ Name = 'team-standards'; Marketplace = 'team-standards'; Url = $pluginUrls['team-standards']; RepoDir = $pluginRepos['team-standards']; PluginDir = (Get-CodexPluginDir $pluginRepos['team-standards'] 'team-standards') },
  [pscustomobject]@{ Name = 'project-coding-profiles'; Marketplace = 'project-coding-profiles'; Url = $pluginUrls['project-coding-profiles']; RepoDir = $pluginRepos['project-coding-profiles']; PluginDir = (Get-CodexPluginDir $pluginRepos['project-coding-profiles'] 'project-coding-profiles') },
  [pscustomobject]@{ Name = 'yoooni-daily-plugin'; Marketplace = 'yoooni-daily-plugin'; Url = $pluginUrls['yoooni-daily-plugin']; RepoDir = $pluginRepos['yoooni-daily-plugin']; PluginDir = (Get-CodexPluginDir $pluginRepos['yoooni-daily-plugin'] 'yoooni-daily-plugin') }
)
$codexPluginResult = Sync-CodexPlugins (Join-Path $env:USERPROFILE '.codex') (Join-Path $env:USERPROFILE '.codex\config.toml') $codexPluginDefs
if ($null -eq $codexPluginResult) {
  Log "  codex: ~/.codex 不存在，跳过 plugin 安装/更新"
}
else {
  Log ("  codex: plugins configured={0}, cached={1}, skipped={2}" -f ($codexPluginResult.Configured -join ','), ($codexPluginResult.Cached -join ','), ($codexPluginResult.Skipped -join ','))
}

$profilePluginDir = Get-CodexPluginDir $pluginRepos['project-coding-profiles'] 'project-coding-profiles'
$cursorRuleResult = Sync-CursorRules (Join-Path $env:USERPROFILE '.cursor') (Join-Path $profilePluginDir '.cursor\rules')
if ($null -eq $cursorRuleResult) {
  Log "  cursor: ~/.cursor 不存在，跳过规则同步"
}
else {
  Log ("  cursor: rules synced={0}" -f ($cursorRuleResult.Synced -join ','))
}

$kiroSteering = Sync-KiroSteering (Join-Path $env:USERPROFILE '.kiro') $WorkspaceDir $pluginRepos
if ($null -eq $kiroSteering) {
  Log "  kiro: ~/.kiro 不存在，跳过 steering 同步"
}
else {
  Log ("  kiro: steering synced -> " + $kiroSteering)
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
# --- best-effort 同步 hook 命中事件到公司共享(每人一文件，无写冲突)；off 热路径，连不上就跳过 ---
# 事件由 team-standards / project-coding-profiles 的 warn hook 写到本地 ~/.kai-toolbox/hook-events.jsonl，
# 这里把整份快照复制到 \\IT01\版本更新\vibecoding\hook-events-<用户>-<机器>.jsonl，供周报 skill 聚合。
$evLocal = Join-Path $state 'hook-events.jsonl'
$evShareDir = '\\IT01\版本更新\vibecoding'
if (Test-Path $evLocal) {
  try {
    if (Test-Path $evShareDir) {
      $evDest = Join-Path $evShareDir ("hook-events-{0}-{1}.jsonl" -f $env:USERNAME, $env:COMPUTERNAME)
      Copy-Item -Path $evLocal -Destination $evDest -Force
      Log ("  hooklog synced -> " + $evDest)
    } else {
      Log "  hooklog: 共享 \\IT01\版本更新\vibecoding 不可达，跳过同步"
    }
  } catch { Log ("  hooklog sync skipped: " + $_.Exception.Message) }
}

# --- best-effort 同步「团队疑问/纠正信号」到公司共享(每人一文件，无写冲突)；off 热路径，连不上就跳过 ---
# 信号由 team-standards 的 prompt-signal-capture(UserPromptSubmit) hook 写到本地
# ~/.kai-toolbox/prompt-signals-<用户>-<机器>.jsonl(本地文件名已含用户+机器，整文件覆盖即幂等)，
# 这里把每份快照原名复制到 \\IT01\版本更新\vibecoding\，供聚合 skill 反推缺失的知识图谱/标准约束。
# prompt 原文比普通 hook 标签更敏感：上行默认关闭，只有显式设为 on 才推共享。
$promptSignalUpload = [string]$env:YOOONI_PROMPT_SIGNAL_UPLOAD
if ($promptSignalUpload.ToLowerInvariant() -eq 'on') {
  try {
    $psShareDir = '\\IT01\版本更新\vibecoding'
    $psLocal = @(Get-ChildItem -Path $state -Filter 'prompt-signals-*.jsonl' -File -ErrorAction SilentlyContinue)
    if ($psLocal.Count -gt 0) {
      if (Test-Path $psShareDir) {
        foreach ($f in $psLocal) {
          Copy-Item -Path $f.FullName -Destination (Join-Path $psShareDir $f.Name) -Force
          Log ("  promptsignal synced -> " + (Join-Path $psShareDir $f.Name))
        }
      } else {
        Log "  promptsignal: 共享 \\IT01\版本更新\vibecoding 不可达，跳过同步"
      }
    }
  } catch { Log ("  promptsignal sync skipped: " + $_.Exception.Message) }
} else {
  Log "  promptsignal: 默认仅留本地；设 YOOONI_PROMPT_SIGNAL_UPLOAD=on 才上行"
}

# --- best-effort 同步「知识图谱 + 术语表」到公司共享(每人一文件夹)；只上行可复用知识资产 ---
# 源：{用户文档}\ai-docs\<project>\{knowledge-graph\, glossary\, *glossary*.md}
#  → \\IT01\版本更新\vibecoding\<用户>-<机器>\ai-docs\<project>\...（robocopy /MIR 镜像，含删除）
# 本地永远是源(只 local→共享)；连不上/无源就跳过。off 热路径(随更新周期跑)。
# YOOONI_KG_UPLOAD=off 关闭上行(仅本地沉淀)。work-log / bug 等个人内容不上行。
$knowledgeUpload = [string]$env:YOOONI_KG_UPLOAD
if ($knowledgeUpload.ToLowerInvariant() -ne 'off') {
  try {
    $aiDocsRoot = Join-Path $env:USERPROFILE 'Documents\ai-docs'
    $kgShareRoot = '\\IT01\版本更新\vibecoding\{0}-{1}\ai-docs' -f $env:USERNAME, $env:COMPUTERNAME
    if ((Test-Path $aiDocsRoot) -and (Test-Path '\\IT01\版本更新\vibecoding')) {
      foreach ($proj in @(Get-ChildItem -Path $aiDocsRoot -Directory -ErrorAction SilentlyContinue)) {
        $projDst = Join-Path $kgShareRoot $proj.Name
        foreach ($sub in @('knowledge-graph', 'glossary')) {
          $src = Join-Path $proj.FullName $sub
          if (Test-Path $src) {
            robocopy "$src" (Join-Path $projDst $sub) /MIR /NJH /NJS /NFL /NDL /NP /R:1 /W:1 2>&1 | Out-Null
            if ($LASTEXITCODE -lt 8) { Log ("  kg synced -> " + (Join-Path $projDst $sub)) }
            else { Log ("  kg robocopy exit $LASTEXITCODE : " + $src) }
            $global:LASTEXITCODE = 0
          }
        }
        foreach ($gf in @(Get-ChildItem -Path $proj.FullName -Filter '*glossary*' -File -ErrorAction SilentlyContinue)) {
          New-Item -ItemType Directory -Force -Path $projDst | Out-Null
          Copy-Item $gf.FullName (Join-Path $projDst $gf.Name) -Force
          Log ("  kg glossary synced -> " + (Join-Path $projDst $gf.Name))
        }
      }
    } else { Log "  kg: ai-docs 或共享 \\IT01\版本更新\vibecoding 不可达，跳过同步" }
  } catch { Log ("  kg sync skipped: " + $_.Exception.Message) }
} else {
  Log "  kg: YOOONI_KG_UPLOAD=off，知识图谱仅留本地不上行"
}

# --- 自愈：若计划任务已存在，确保它指向稳定启动器(防插件自更新后版本化路径失效) ---
# 仅校准已存在的任务，绝不擅自创建。
$reg = Join-Path $PSScriptRoot 'register-autoupdate-task.ps1'
if (Test-Path $reg) {
  # register 用 Write-Host 输出，PS 5.1 下 2>&1 捕获不到，这里只记一条固定日志，副作用照常发生
  try { & $reg -OnlyIfExists | Out-Null; Log "  task: 自愈校准计划任务(指向稳定启动器，仅当任务已存在)" }
  catch { Log ("  task self-heal skipped: " + $_.Exception.Message) }
}

Log ("=== update done (pdkChanged={0}, pluginsUpdated={1}) ===" -f $pdkChanged, $pluginUpdated.Count)
}
finally {
  Exit-YoooniUpdateMutex $updateMutex
}
