<#
.SYNOPSIS
  公司团队工具「一键首次安装」（全部走 Gitee 源）。
  本脚本只负责【首次安装缺失的部分】：已安装的一律跳过，不重装、不更新——
  需要更新请用『更新公司套件』skill(yoooni-update-team-tools) 或 scripts\update-team-tools.ps1。
    - 仓库：缺失才 git clone（已存在则跳过，不 pull）
    - MCP ：未注册才 build + claude mcp add（已注册则跳过）
    - 插件：未安装才 claude plugin marketplace add + claude plugin install（已安装则跳过）
            （claude plugin 现为完整 CLI，插件可全自动安装，无需手敲 slash）
  注：claude mcp add 在 PowerShell 里必须用引号包住 '--'（裸 -- 会被 PS 吞掉，导致
      变参 -e 吞掉 node+路径，报 "missing required argument 'commandOrUrl'"）。

.PARAMETER WorkspaceDir
  仓库克隆根目录。不传则自动定位：已克隆过的目录(任意盘) > 配置 > 默认 $env:USERPROFILE\myWork。

.PARAMETER Scope
  MCP 与插件的安装范围：user(默认，全局可用) / local / project。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install-team-tools.ps1
  powershell -ExecutionPolicy Bypass -File .\install-team-tools.ps1 -WorkspaceDir D:\Users\zhang\myWork -Scope user
#>
param(
    [string]$WorkspaceDir,
    [ValidateSet('user', 'local', 'project')]
    [string]$Scope = 'user'
)

# 用 Continue：原生命令(claude mcp get/list 等)写 stderr 时，Stop 会把它当终止错误中断脚本。
# git 缺失已在前置检查里显式 exit 1；其余失败按步骤各自处理。
$ErrorActionPreference = 'Continue'
$utf8 = New-Object System.Text.UTF8Encoding($false)   # 无 BOM
$cfg  = Join-Path $env:USERPROFILE '.kai-toolbox\workspace.path'

function Test-Cmd($name) { return [bool](Get-Command $name -ErrorAction SilentlyContinue) }
function HasPdk($w) { return ($w -and (Test-Path (Join-Path $w 'project-domain-knowledge\.git'))) }

# 幂等把若干 MCP server 写进某 AI 工具的 mcpServers JSON 配置(Cursor / Kiro 同格式)。
#   - 工具根目录不存在 => 视为未安装,返回 $null(跳过)。
#   - 已有同名 server => 跳过,不覆盖(更新交给 update skill)。
#   - 路径统一用正斜杠(node 跨平台可用,且免 JSON 反斜杠转义困扰)。
function Add-McpToJsonConfig($toolRoot, $configPath, $servers) {
    if (-not (Test-Path $toolRoot)) { return $null }   # 工具未安装
    $dir = Split-Path $configPath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $root = $null
    if (Test-Path $configPath) {
        try { $root = (Get-Content $configPath -Raw -ErrorAction Stop | ConvertFrom-Json) } catch { $root = $null }
    }
    if (-not $root) { $root = [PSCustomObject]@{} }
    if (-not ($root.PSObject.Properties.Name -contains 'mcpServers')) {
        $root | Add-Member -NotePropertyName 'mcpServers' -NotePropertyValue ([PSCustomObject]@{})
    }
    $added = @()
    foreach ($name in $servers.Keys) {
        if ($root.mcpServers.PSObject.Properties.Name -contains $name) { continue }  # 已存在,不覆盖
        $root.mcpServers | Add-Member -NotePropertyName $name -NotePropertyValue $servers[$name]
        $added += $name
    }
    [IO.File]::WriteAllText($configPath, ($root | ConvertTo-Json -Depth 12), $utf8)
    return $added
}

# 幂等把若干 MCP server 追加进 Codex 的 TOML 配置(~/.codex/config.toml)。
#   Codex MCP 格式: [mcp_servers.<name>] command/args/env。TOML 不便整体重写,故采用
#   "检测已存在 -> 不动;缺失 -> 追加表块到文件末尾" 的策略(幂等、不破坏现有内容)。
#   仅当 ~/.codex 目录存在(即装了 Codex)才写;否则返回 $null。
function Add-McpToTomlConfig($codexRoot, $configPath, $servers) {
    if (-not (Test-Path $codexRoot)) { return $null }   # 未装 Codex
    $existing = ''
    if (Test-Path $configPath) { $existing = (Get-Content $configPath -Raw -ErrorAction SilentlyContinue) }
    if ($null -eq $existing) { $existing = '' }
    $added = @()
    $append = ''
    foreach ($name in $servers.Keys) {
        # 已有 [mcp_servers.<name>] 表头(允许点号 key 带或不带引号)=> 跳过
        $pat = '(?m)^\s*\[mcp_servers\.(?:"' + [regex]::Escape($name) + '"|' + [regex]::Escape($name) + ')\]'
        if ($existing -match $pat) { continue }
        $s = $servers[$name]
        $argsToml = ($s.args | ForEach-Object { '"' + ($_ -replace '\\', '/') + '"' }) -join ', '
        # env 是 PSCustomObject:遍历其属性名取值
        $envPairs = @()
        if ($s.env) { foreach ($p in $s.env.PSObject.Properties) { $envPairs += '"' + $p.Name + '" = "' + ($p.Value -replace '\\', '/') + '"' } }
        $envToml = $envPairs -join ', '
        $append += "`n[mcp_servers.$name]`n"
        $append += "command = `"$($s.command)`"`n"
        $append += "args = [$argsToml]`n"
        if ($envToml) { $append += "env = { $envToml }`n" }
        $added += $name
    }
    if ($append) {
        $sep = if ($existing -and -not $existing.EndsWith("`n")) { "`n" } else { '' }
        [IO.File]::WriteAllText($configPath, $existing + $sep + $append, $utf8)
    }
    return $added
}

# Gitee 是公司当前源码管理（GitHub 仅部分仓库镜像，安装一律用 Gitee）
$Repos = @(
    @{ Name = 'team-standards';           Url = 'https://gitee.com/wyoooni/team-standards.git';           Type = 'plugin' }
    @{ Name = 'project-coding-profiles';  Url = 'https://gitee.com/wyoooni/project-coding-profiles.git';  Type = 'plugin' }
    @{ Name = 'project-domain-knowledge'; Url = 'https://gitee.com/wyoooni/project-domain-knowledge.git'; Type = 'mcp(engine)' }
    @{ Name = 'cross-project-topology';   Url = 'https://gitee.com/wyoooni/cross-project-topology.git';   Type = 'mcp(shared-engine)' }
)
# 两个 Claude Code 插件：marketplace 名与插件名一致 -> 安装引用 name@name
$Plugins = @(
    @{ Name = 'team-standards';          Url = 'https://gitee.com/wyoooni/team-standards.git' }
    @{ Name = 'project-coding-profiles'; Url = 'https://gitee.com/wyoooni/project-coding-profiles.git' }
)

# --- 前置检查 ---
if (-not (Test-Cmd git)) { Write-Error "未检测到 git，请先安装 Git 并加入 PATH。"; exit 1 }
$hasNode = Test-Cmd node
$hasNpm  = Test-Cmd npm
$hasClaude = Test-Cmd claude

# --- 自动定位 WorkspaceDir：优先复用"已克隆过的目录"(任意盘)，避免在默认 C 盘重复克隆一份 ---
$cands = @()
if ($WorkspaceDir) { $cands += $WorkspaceDir }
if ($env:YOOONI_WORKSPACE_DIR) { $cands += $env:YOOONI_WORKSPACE_DIR }
if (Test-Path $cfg) { $cands += (((Get-Content $cfg -Raw) -replace "^\xEF\xBB\xBF", "") -replace "﻿", "").Trim() }
if ($hasClaude) {
    $info = @((claude mcp get domain-knowledge 2>$null); (claude mcp list 2>$null)) -join "`n"
    $m = [regex]::Match($info, '([A-Za-z]:[\/].*?)[\/]project-domain-knowledge[\/]dist[\/]server\.js')
    if ($m.Success) { $cands += $m.Groups[1].Value }
}
foreach ($drv in @('C:', 'D:', 'E:', 'F:')) { $cands += ("{0}\Users\{1}\myWork" -f $drv, $env:USERNAME) }
$resolved = $null
foreach ($c in $cands) { if (HasPdk $c) { $resolved = $c; break } }     # 1) 已有克隆所在目录优先
if (-not $resolved) {                                                   # 2) 全新机器：参数 > 配置 > 默认
    if ($WorkspaceDir) { $resolved = $WorkspaceDir }
    elseif (Test-Path $cfg) { $resolved = (((Get-Content $cfg -Raw) -replace "^\xEF\xBB\xBF", "")).Trim() }
    else { $resolved = (Join-Path $env:USERPROFILE 'myWork') }
}
$WorkspaceDir = $resolved
New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
[IO.File]::WriteAllText($cfg, $WorkspaceDir, $utf8)                     # 记住(无 BOM)，与 update 脚本共用

# 结果分类（最后汇总；区分"本次新装" vs "已存在/已跳过 -> 去用更新 skill"）
$newRepos = @();    $haveRepos = @()
$newMcp = @();      $haveMcp = @()
$newPlugins = @();  $havePlugins = @()

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " 公司团队工具一键【首次安装】（Gitee 源）" -ForegroundColor Cyan
Write-Host " 已安装的不重装/不更新 —— 更新请用『更新公司套件』skill" -ForegroundColor DarkCyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "工作区目录: $WorkspaceDir"
Write-Host "安装范围  : $Scope"
if (-not $hasNode -or -not $hasNpm) { Write-Warning "未检测到 node/npm（>=18）。MCP 构建会被跳过，其余照常拉取。" }
if (-not $hasClaude) { Write-Warning "未检测到 claude CLI。MCP/插件的自动安装会被跳过，稍后打印手动命令。" }
Write-Host ""

if (-not (Test-Path $WorkspaceDir)) {
    New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null
    Write-Host "已创建工作区目录: $WorkspaceDir"
}

# --- 第 1 步：克隆缺失的仓库（已存在则跳过，不 pull —— 更新交给 update skill）---
Write-Host ""
Write-Host "[1/3] 克隆缺失仓库（已存在跳过）..." -ForegroundColor Green
foreach ($r in $Repos) {
    $dest = Join-Path $WorkspaceDir $r.Name
    if (Test-Path (Join-Path $dest '.git')) {
        Write-Host "  = 已存在，跳过: $($r.Name)" -ForegroundColor DarkGray
        $haveRepos += $r.Name
    }
    else {
        Write-Host "  + 克隆 $($r.Name) ($($r.Url))"
        git clone $r.Url $dest
        $newRepos += $r.Name
    }
}

# --- 第 2 步：MCP（未注册才 build + 注册；已注册跳过，更新交给 update skill）---
# 复用引擎：project-domain-knowledge 的 dist/server.js 是通用 md+frontmatter 知识引擎，
# 用 DOMAIN_KB_DIR 指向不同知识根目录 -> 一份代码两个实例：
#   domain-knowledge -> 业务公共认知；cross-topology -> 跨项目拓扑
Write-Host ""
Write-Host "[2/3] 注册 MCP（domain-knowledge + cross-topology，已注册跳过）..." -ForegroundColor Green
$mcpDir = Join-Path $WorkspaceDir 'project-domain-knowledge'
$mcpEntry = Join-Path $mcpDir 'dist\server.js'
$domainKbDir = Join-Path $mcpDir 'knowledge'
$topoDir = Join-Path $WorkspaceDir 'cross-project-topology'
$topoKbDir = Join-Path $topoDir 'knowledge'

$script:mcpList = if ($hasClaude) { (claude mcp list 2>$null | Out-String) } else { '' }
function McpRegistered($n) { return $script:mcpList -match ("(?m)^\s*" + [regex]::Escape($n) + "\b") }

$needDomain = $hasClaude -and -not (McpRegistered 'domain-knowledge')
$needTopo   = $hasClaude -and (Test-Path $topoKbDir) -and -not (McpRegistered 'cross-topology')
if ($hasClaude -and -not $needDomain) { $haveMcp += 'domain-knowledge' }
if ($hasClaude -and (Test-Path $topoKbDir) -and -not $needTopo) { $haveMcp += 'cross-topology' }

if (($needDomain -or $needTopo) -and $hasNode -and $hasNpm) {
    if (-not (Test-Path $mcpEntry)) {
        Push-Location $mcpDir
        try { Write-Host "  -> npm install"; npm install; Write-Host "  -> npm run build"; npm run build }
        finally { Pop-Location }
    }
    if (Test-Path $mcpEntry) {
        # 注意：'--' 必须带引号，否则 PowerShell 会吞掉它（见文件头说明）
        if ($needDomain) {
            Write-Host "  + 注册 domain-knowledge (DOMAIN_KB_DIR=$domainKbDir)"
            claude mcp add domain-knowledge -s $Scope -e "DOMAIN_KB_DIR=$domainKbDir" '--' node "$mcpEntry"
            $newMcp += 'domain-knowledge'
        }
        if ($needTopo) {
            Write-Host "  + 注册 cross-topology (DOMAIN_KB_DIR=$topoKbDir)"
            claude mcp add cross-topology -s $Scope -e "DOMAIN_KB_DIR=$topoKbDir" '--' node "$mcpEntry"
            $newMcp += 'cross-topology'
        }
    }
    else { Write-Warning "构建后未找到 $mcpEntry，跳过 MCP 注册。请检查 npm run build 是否成功。" }
}
elseif (($needDomain -or $needTopo) -and -not ($hasNode -and $hasNpm)) {
    Write-Host "  (需注册 MCP 但缺少 node/npm，已跳过 build/注册)" -ForegroundColor DarkYellow
}
elseif (-not $hasClaude) {
    Write-Host "  (claude CLI 缺失，MCP 注册已跳过)" -ForegroundColor DarkYellow
}
else {
    Write-Host "  = MCP 已注册，跳过（更新走 update skill）" -ForegroundColor DarkGray
}
if ($hasClaude -and -not (Test-Path $topoKbDir)) {
    Write-Warning "未找到 $topoKbDir（cross-project-topology 尚无 knowledge/ 根目录），cross-topology 未注册。内容就绪后用 update skill 刷新即可。"
}

# --- 第 2.5 步：把同两个 MCP 也注册进 Cursor / Kiro（同格式 mcpServers JSON，幂等不覆盖）---
# Claude Code 的 MCP 走 claude CLI（上面第 2 步）；Cursor / Kiro 走各自的 JSON 配置文件。
# 一份 dist/server.js + DOMAIN_KB_DIR 指不同知识根 => 各工具里都得到 domain-knowledge + cross-topology 两实例。
Write-Host ""
Write-Host "[2.5] 注册 MCP 到 Cursor / Kiro / Codex（各自配置格式，已存在跳过）..." -ForegroundColor Green
$entryFwd = ($mcpEntry -replace '\\', '/')
$domainKbFwd = ($domainKbDir -replace '\\', '/')
$topoKbFwd = ($topoKbDir -replace '\\', '/')

$otherMcp = [ordered]@{}
if (Test-Path $mcpEntry) {
    $otherMcp['domain-knowledge'] = [PSCustomObject]@{ command = 'node'; args = @($entryFwd); env = [PSCustomObject]@{ DOMAIN_KB_DIR = $domainKbFwd } }
    if (Test-Path $topoKbDir) {
        $otherMcp['cross-topology'] = [PSCustomObject]@{ command = 'node'; args = @($entryFwd); env = [PSCustomObject]@{ DOMAIN_KB_DIR = $topoKbFwd } }
    }
}

# 各工具的【用户级】MCP 配置路径（与 Scope=user 对齐；项目级各工具放项目根，按需另配）
$toolTargets = @(
    @{ Tool = 'Cursor'; Root = (Join-Path $env:USERPROFILE '.cursor'); Config = (Join-Path $env:USERPROFILE '.cursor\mcp.json') }
    @{ Tool = 'Kiro';   Root = (Join-Path $env:USERPROFILE '.kiro');   Config = (Join-Path $env:USERPROFILE '.kiro\settings\mcp.json') }
)
$newOtherMcp = @(); $skipOtherMcp = @()
if ($otherMcp.Count -gt 0) {
    foreach ($t in $toolTargets) {
        $res = Add-McpToJsonConfig $t.Root $t.Config $otherMcp
        if ($null -eq $res) { Write-Host "  - $($t.Tool) 未安装（无 $($t.Root)），跳过" -ForegroundColor DarkGray }
        elseif ($res.Count -gt 0) { Write-Host "  + $($t.Tool): 写入 $($res -join ', ') -> $($t.Config)"; $newOtherMcp += "$($t.Tool)($($res -join '/'))" }
        else { Write-Host "  = $($t.Tool): 已有同名 MCP，跳过" -ForegroundColor DarkGray; $skipOtherMcp += $t.Tool }
    }
    # Codex：TOML 配置（~/.codex/config.toml），格式不同，单独处理
    $codexRoot = Join-Path $env:USERPROFILE '.codex'
    $codexCfg  = Join-Path $codexRoot 'config.toml'
    $cres = Add-McpToTomlConfig $codexRoot $codexCfg $otherMcp
    if ($null -eq $cres) { Write-Host "  - Codex 未安装（无 $codexRoot），跳过" -ForegroundColor DarkGray }
    elseif ($cres.Count -gt 0) { Write-Host "  + Codex: 追加 $($cres -join ', ') -> $codexCfg"; $newOtherMcp += "Codex($($cres -join '/'))" }
    else { Write-Host "  = Codex: 已有同名 MCP，跳过" -ForegroundColor DarkGray; $skipOtherMcp += 'Codex' }
} else {
    Write-Host "  (未找到 dist/server.js，Cursor/Kiro/Codex 的 MCP 注册跳过；先让 MCP 引擎构建成功)" -ForegroundColor DarkYellow
}

# --- 第 3 步：插件（claude plugin CLI 全自动；已安装跳过，更新交给 update skill）---
Write-Host ""
Write-Host "[3/3] 安装插件（claude plugin CLI，已安装跳过）..." -ForegroundColor Green
if ($hasClaude) {
    $pluginList = (claude plugin list 2>$null | Out-String)
    $mktList    = (claude plugin marketplace list 2>$null | Out-String)
    foreach ($p in $Plugins) {
        $ref = "{0}@{0}" -f $p.Name
        if ($pluginList -match [regex]::Escape($ref)) {
            Write-Host "  = 已安装，跳过: $ref" -ForegroundColor DarkGray
            $havePlugins += $p.Name
            continue
        }
        if (-not ($mktList -match [regex]::Escape($p.Name))) {
            Write-Host "  + marketplace add $($p.Url)"
            claude plugin marketplace add $p.Url
        }
        Write-Host "  + plugin install $ref"
        claude plugin install $ref -s $Scope
        $newPlugins += $p.Name
    }
}
else {
    Write-Warning "claude CLI 缺失，插件未安装。装好后执行（plugin 名须带 @marketplace 全限定）："
    Write-Host "  claude plugin marketplace add https://gitee.com/wyoooni/team-standards.git"
    Write-Host "  claude plugin install team-standards@team-standards -s $Scope"
    Write-Host "  claude plugin marketplace add https://gitee.com/wyoooni/project-coding-profiles.git"
    Write-Host "  claude plugin install project-coding-profiles@project-coding-profiles -s $Scope"
}

# --- 汇总 ---
Write-Host ""
Write-Host "==================== 安装结果 ====================" -ForegroundColor Cyan
if ($newRepos.Count)   { Write-Host ("新克隆仓库 : " + ($newRepos -join ', ')) -ForegroundColor Green }
if ($newMcp.Count)     { Write-Host ("新注册 MCP (Claude Code): " + ($newMcp -join ', ')) -ForegroundColor Green }
if ($newOtherMcp.Count){ Write-Host ("新注册 MCP (其它工具): " + ($newOtherMcp -join ', ')) -ForegroundColor Green }
if ($newPlugins.Count) { Write-Host ("新安装插件 : " + ($newPlugins -join ', ')) -ForegroundColor Green }
if (-not ($newRepos.Count -or $newMcp.Count -or $newOtherMcp.Count -or $newPlugins.Count)) {
    Write-Host "本次没有新安装项——全部已就绪。" -ForegroundColor Green
}
if ($haveRepos.Count -or $haveMcp.Count -or $havePlugins.Count) {
    Write-Host ""
    Write-Host "以下已安装，本脚本未改动（不重装/不更新）：" -ForegroundColor DarkCyan
    if ($haveRepos.Count)   { Write-Host ("  仓库 : " + ($haveRepos -join ', ')) }
    if ($haveMcp.Count)     { Write-Host ("  MCP  : " + ($haveMcp -join ', ')) }
    if ($havePlugins.Count) { Write-Host ("  插件 : " + ($havePlugins -join ', ')) }
    Write-Host ""
    Write-Host ">> 需要更新？别重跑安装——用『更新公司套件』skill(yoooni-update-team-tools)，" -ForegroundColor Yellow
    Write-Host "  或直接跑 scripts\update-team-tools.ps1（git pull + 重建 MCP + claude plugin update）。" -ForegroundColor Yellow
}
if ($newPlugins.Count) {
    Write-Host ""
    Write-Host "插件已安装，重启 Claude Code 会话后生效（或 /reload-plugins）。" -ForegroundColor Cyan
}
Write-Host "==================================================" -ForegroundColor Cyan
