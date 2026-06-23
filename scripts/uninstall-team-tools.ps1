<#
.SYNOPSIS
  公司团队套件「一键卸载」——只摘除本套件登记到 Claude Code 的东西：
    - 插件：team-standards / project-coding-profiles / yoooni-daily-plugin（本体）
    - MCP ：domain-knowledge / cross-topology
    - 定时任务：YoooniTeamToolsAutoUpdate
  **只动我们自己的项**（按白名单精确匹配），绝不碰 frontend-design / claude.ai 等其它插件与 MCP。
  默认**保留**克隆的源码仓库与 marketplace 登记（便于随后重装/继续开发）；要一并清掉用开关。

.PARAMETER Scope            插件/MCP 卸载范围 user(默认)/local/project。
.PARAMETER RemoveTask       默认连同删除定时更新任务；传 -RemoveTask:$false 可保留。
.PARAMETER RemoveMarketplace 额外移除我们两个插件的 marketplace 登记（默认不移）。
.PARAMETER RemoveRepos      额外删除克隆的源码仓库目录（危险，默认不删；只删本套件 4 个仓）。
.PARAMETER WorkspaceDir     源码仓库根（仅 -RemoveRepos 时用）；不传则读配置/默认。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\uninstall-team-tools.ps1
  powershell -ExecutionPolicy Bypass -File .\uninstall-team-tools.ps1 -RemoveMarketplace
#>
param(
    [ValidateSet('user', 'local', 'project')][string]$Scope = 'user',
    [bool]$RemoveTask = $true,
    [switch]$RemoveMarketplace,
    [switch]$RemoveRepos,
    [string]$WorkspaceDir
)

$ErrorActionPreference = 'Continue'
function Test-Cmd($n) { return [bool](Get-Command $n -ErrorAction SilentlyContinue) }

# 白名单：只摘我们自己的项
$OurPlugins = @('team-standards', 'project-coding-profiles', 'yoooni-daily-plugin')
$OurMcp = @('domain-knowledge', 'cross-topology')
$taskName = 'YoooniTeamToolsAutoUpdate'

$hasClaude = Test-Cmd claude
$removedPlugins = @(); $removedMcp = @(); $skipped = @()

Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ' 公司团队套件【一键卸载】（只摘本套件项）' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
if (-not $hasClaude) {
    Write-Host '========== 环境自查 ==========' -ForegroundColor Yellow
    Write-Host '  [缺失] Claude Code CLI —— 没它无法卸载插件/MCP。' -ForegroundColor Yellow
    Write-Host '         装：npm install -g @anthropic-ai/claude-code（需先装 Node）。' -ForegroundColor DarkYellow
    Write-Host '         或手动卸载：claude plugin uninstall <name>@<name> -s user -y ；claude mcp remove <name>' -ForegroundColor DarkYellow
    Write-Host '  定时任务仍会按设置删除（schtasks 为系统自带，不依赖 claude）。' -ForegroundColor Cyan
    Write-Host '==============================' -ForegroundColor Yellow
}

# --- 1) 卸载插件（本体放最后，避免先摘了本体影响其它）---
if ($hasClaude) {
    Write-Host ''
    Write-Host '[1/3] 卸载插件...' -ForegroundColor Green
    $pl = (claude plugin list 2>$null | Out-String)
    foreach ($p in $OurPlugins) {
        $ref = "{0}@{0}" -f $p
        if ($pl -match [regex]::Escape($ref)) {
            Write-Host "  - plugin uninstall $ref"
            claude plugin uninstall $ref -s $Scope -y
            $removedPlugins += $p
        }
        else { Write-Host "  = 未安装，跳过: $ref" -ForegroundColor DarkGray; $skipped += "plugin:$p" }
    }
    if ($RemoveMarketplace) {
        Write-Host '  移除 marketplace 登记...' -ForegroundColor DarkCyan
        foreach ($p in @('team-standards', 'project-coding-profiles', 'yoooni-daily-plugin')) {
            claude plugin marketplace remove $p 2>$null
        }
    }
}

# --- 2) 移除 MCP ---
if ($hasClaude) {
    Write-Host ''
    Write-Host '[2/3] 移除 MCP...' -ForegroundColor Green
    $ml = (claude mcp list 2>$null | Out-String)
    foreach ($m in $OurMcp) {
        if ($ml -match ("(?m)^\s*" + [regex]::Escape($m) + "\b")) {
            Write-Host "  - mcp remove $m"
            claude mcp remove $m -s $Scope 2>$null
            if ($LASTEXITCODE -ne 0) { claude mcp remove $m 2>$null }  # scope 不符则自动定位
            $removedMcp += $m
        }
        else { Write-Host "  = 未注册，跳过: $m" -ForegroundColor DarkGray; $skipped += "mcp:$m" }
    }
}

# --- 3) 删除定时任务 ---
Write-Host ''
Write-Host '[3/3] 定时更新任务...' -ForegroundColor Green
if ($RemoveTask) {
    $exist = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($exist) { schtasks /Delete /TN $taskName /F | Out-Null; Write-Host "  - 已删除任务 $taskName" }
    else { Write-Host "  = 任务不存在，跳过" -ForegroundColor DarkGray }
}
else { Write-Host '  (保留定时任务)' -ForegroundColor DarkGray }

# --- 可选：删源码仓库 ---
if ($RemoveRepos) {
    $cfg = Join-Path $env:USERPROFILE '.kai-toolbox\workspace.path'
    if (-not $WorkspaceDir -and (Test-Path $cfg)) { $WorkspaceDir = (((Get-Content $cfg -Raw) -replace "^\xEF\xBB\xBF", "")).Trim() }
    if ($WorkspaceDir) {
        Write-Host ''
        Write-Host "[+] 删除源码仓库（$WorkspaceDir）..." -ForegroundColor Yellow
        foreach ($r in @('team-standards', 'project-coding-profiles', 'project-domain-knowledge', 'cross-project-topology')) {
            $d = Join-Path $WorkspaceDir $r
            if (Test-Path $d) { Remove-Item $d -Recurse -Force; Write-Host "  - 删除 $d" }
        }
        Write-Host "  注意：本体 yoooni-daily-plugin 仓库未删（本脚本在其中）。如需手动删。" -ForegroundColor DarkYellow
    }
}

# --- 汇总 ---
Write-Host ''
Write-Host '==================== 卸载结果 ====================' -ForegroundColor Cyan
if ($removedPlugins.Count) { Write-Host ("已卸载插件 : " + ($removedPlugins -join ', ')) -ForegroundColor Green }
if ($removedMcp.Count) { Write-Host ("已移除 MCP : " + ($removedMcp -join ', ')) -ForegroundColor Green }
if (-not ($removedPlugins.Count -or $removedMcp.Count)) { Write-Host '没有可卸载项（可能本就没装）。' -ForegroundColor Green }
Write-Host ''
Write-Host '重装：scripts\bootstrap-install.ps1（全新机器，含本体 + 定时任务）' -ForegroundColor Cyan
Write-Host '      或 skills\yoooni-install-team-tools\install-team-tools.ps1（已有本体时）' -ForegroundColor Cyan
Write-Host '插件卸载在重启 Claude Code 会话后完全生效。' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
