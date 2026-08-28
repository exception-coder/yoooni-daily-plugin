<#
.SYNOPSIS
  公司团队套件「全新机器一键引导安装」（全部走 Gitee 源）。

  与 scripts\install-team-tools.ps1 的区别：
    install-team-tools.ps1 跑在【本体插件内部】，装不了本体自己；
    本脚本是【零依赖引导】，会连「本体插件 yoooni-daily-plugin」自身一并克隆 + 安装。
    中间的「关联插件 + MCP」直接委托 install-team-tools.ps1（幂等、已装跳过），不重复实现。

  流程：1) 克隆+装本体 → 2) 委托装 team-standards/project-coding-profiles + MCP(domain-knowledge/cross-topology)
        → 3) 按显式参数选择是否注册定时更新任务。全程幂等，已就绪的跳过。

.PARAMETER WorkspaceDir 仓库克隆根目录；不传则自动定位（已克隆目录 > 配置 > 默认 %USERPROFILE%\myWork）。
.PARAMETER Scope        插件/MCP 安装范围 user(默认，全局)/local/project。
.PARAMETER EveryHours   定时更新周期（小时），默认 0（不注册）；仅显式设为正整数时注册定时任务。
.PARAMETER GiteeBase    Gitee 组织地址前缀，默认 https://gitee.com/wyoooni 。

.EXAMPLE
  # 发同事：把本文件 + team-tools-install.cmd 放同一文件夹，双击 .cmd 即可
  powershell -ExecutionPolicy Bypass -File .\bootstrap-install.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\bootstrap-install.ps1 -WorkspaceDir D:\Users\me\myWork -EveryHours 1
.NOTES
  Gitee 仓库为私有，raw 链接对外 403；故走「发文件 + git clone」模式（git clone 用同事自己的 Gitee 凭据，
  首次会提示登录、之后缓存）。不要用 irm raw 下载本脚本。
#>
param(
    [string]$WorkspaceDir,
    [ValidateSet('user', 'local', 'project')][string]$Scope = 'user',
    [int]$EveryHours = 0,
    [string]$GiteeBase = 'https://gitee.com/wyoooni'
)

$ErrorActionPreference = 'Continue'
$utf8 = New-Object System.Text.UTF8Encoding($false)   # 无 BOM（写配置文件用）
$cfg = Join-Path $env:USERPROFILE '.kai-toolbox\workspace.path'

function Test-Cmd($n) { return [bool](Get-Command $n -ErrorAction SilentlyContinue) }
function HasGitDir($d) { return ($d -and (Test-Path (Join-Path $d '.git'))) }

# --- PATH 兜底：claude 是 npm 全局命令（装在 %APPDATA%\npm），刚装完未重启时可能不在本进程 PATH。
#     若此刻 claude 不可见但该目录存在，补进 PATH，避免把"已装好的 claude"误判为缺失而跳过插件/MCP 安装。
$npmGlobalDir = Join-Path $env:APPDATA 'npm'
if ((-not (Test-Cmd claude)) -and (Test-Path -LiteralPath $npmGlobalDir)) {
    $env:PATH = "$env:PATH;$npmGlobalDir"
}

# --- 前置检查 + 缺失项指引（同事自查用）---
$hasGit = Test-Cmd git
$hasNode = Test-Cmd node
$hasNpm = Test-Cmd npm
$hasClaude = Test-Cmd claude

$missing = @()
if (-not $hasGit) { $missing += @{ N = 'Git'; Why = '必需 · 克隆全部仓库'; How = 'https://git-scm.com/download/win    或  winget install Git.Git' } }
if (-not $hasNode -or -not $hasNpm) { $missing += @{ N = 'Node.js + npm (>=18)'; Why = '构建 MCP 知识库引擎'; How = 'https://nodejs.org/zh-cn    或  winget install OpenJS.NodeJS.LTS' } }
if (-not $hasClaude) { $missing += @{ N = 'Claude Code CLI'; Why = '安装插件 + 注册 MCP'; How = '装好 Node 后执行：npm install -g @anthropic-ai/claude-code' } }

if ($missing.Count) {
    Write-Host ''
    Write-Host '========== 环境自查：检测到缺失项 ==========' -ForegroundColor Yellow
    foreach ($m in $missing) {
        Write-Host ("  [缺失] {0}  —— {1}" -f $m.N, $m.Why) -ForegroundColor Yellow
        Write-Host ("         安装：{0}" -f $m.How) -ForegroundColor DarkYellow
    }
    Write-Host '  装好后【重开终端】使 PATH 生效，再重跑本脚本（已装的会跳过，幂等安全）。' -ForegroundColor Cyan
    Write-Host '===========================================' -ForegroundColor Yellow
    Write-Host ''
}
else {
    Write-Host '环境自查：git / node / npm / claude 均就绪。' -ForegroundColor Green
}

if (-not $hasGit) { Write-Error 'Git 是必需项，已中止。请按上面提示安装 Git 后重跑。'; exit 1 }

# --- 定位 WorkspaceDir（与 install-team-tools.ps1 同口径：已克隆目录 > 配置 > 默认）---
$cands = @()
if ($WorkspaceDir) { $cands += $WorkspaceDir }
if ($env:YOOONI_WORKSPACE_DIR) { $cands += $env:YOOONI_WORKSPACE_DIR }
if (Test-Path $cfg) { $cands += (((Get-Content $cfg -Raw) -replace "^\xEF\xBB\xBF", "")).Trim() }
foreach ($drv in @('C:', 'D:', 'E:', 'F:')) { $cands += ("{0}\Users\{1}\myWork" -f $drv, $env:USERNAME) }
$resolved = $null
foreach ($c in $cands) { if (HasGitDir (Join-Path $c 'yoooni-daily-plugin')) { $resolved = $c; break } }
if (-not $resolved) {
    if ($WorkspaceDir) { $resolved = $WorkspaceDir }
    elseif (Test-Path $cfg) { $resolved = (((Get-Content $cfg -Raw) -replace "^\xEF\xBB\xBF", "")).Trim() }
    else { $resolved = (Join-Path $env:USERPROFILE 'myWork') }
}
$WorkspaceDir = $resolved
New-Item -ItemType Directory -Force -Path (Split-Path $cfg) | Out-Null
[IO.File]::WriteAllText($cfg, $WorkspaceDir, $utf8)     # 记住工作区（无 BOM），与 install/update 脚本共用
New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null

Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ' 公司团队套件【全新机器一键引导】(Gitee 源)' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host "工作区目录: $WorkspaceDir"
Write-Host "安装范围  : $Scope"
if ($EveryHours -gt 0) { Write-Host "定时更新  : 每 $EveryHours 小时（显式启用）" }
else { Write-Host '定时更新  : 未启用（默认手动更新）' }
if (-not $hasClaude) { Write-Warning '未检测到 claude CLI；插件/MCP 自动安装会被跳过（git clone 仍执行）。装好 claude 后重跑本脚本即可。' }

# --- 1) 本体 yoooni-daily-plugin：克隆 + 安装插件 ---
$selfName = 'yoooni-daily-plugin'
$selfDir = Join-Path $WorkspaceDir $selfName
$selfUrl = "$GiteeBase/$selfName.git"
$selfRef = "{0}@{0}" -f $selfName

Write-Host ''
Write-Host "[1/3] 本体 $selfName（克隆 + 安装插件）..." -ForegroundColor Green
if (HasGitDir $selfDir) { Write-Host '  = 仓库已存在，跳过克隆（更新请手动运行更新 skill）' -ForegroundColor DarkGray }
else { Write-Host "  + git clone $selfUrl"; git clone $selfUrl $selfDir }

if ($hasClaude) {
    $pl = (claude plugin list 2>$null | Out-String)
    if ($pl -match [regex]::Escape($selfRef)) {
        Write-Host "  = 插件已安装，跳过: $selfRef" -ForegroundColor DarkGray
    }
    else {
        $mk = (claude plugin marketplace list 2>$null | Out-String)
        if (-not ($mk -match [regex]::Escape($selfName))) { Write-Host "  + marketplace add $selfUrl"; claude plugin marketplace add $selfUrl }
        Write-Host "  + plugin install $selfRef"
        claude plugin install $selfRef -s $Scope
    }
}
else { Write-Host '  (claude 缺失，跳过本体插件安装)' -ForegroundColor DarkYellow }

# --- 2) 关联插件 + MCP：委托本体内的 install-team-tools.ps1（幂等）---
Write-Host ''
Write-Host '[2/3] 关联插件 + MCP（委托 install-team-tools.ps1）...' -ForegroundColor Green
# 兼容两种仓库布局：新版子目录布局 plugins\yoooni-daily-plugin\ 优先，旧版根布局兜底。
# （仓库已重构为子目录布局后，skills/ 与 scripts/ 都在 plugins\yoooni-daily-plugin\ 下。）
$pluginRoot = $selfDir
if (Test-Path (Join-Path $selfDir 'plugins\yoooni-daily-plugin\.claude-plugin\plugin.json')) {
    $pluginRoot = Join-Path $selfDir 'plugins\yoooni-daily-plugin'
}
$installer = Join-Path $pluginRoot 'scripts\install-team-tools.ps1'
if (Test-Path $installer) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installer -WorkspaceDir $WorkspaceDir -Scope $Scope
}
else { Write-Warning "未找到 $installer（本体克隆可能失败 / 布局变更）。检查网络后重跑本脚本。" }

# --- 3) 仅在显式指定周期时注册定时更新任务 ---
Write-Host ''
Write-Host '[3/3] 检查可选定时更新任务...' -ForegroundColor Green
$register = Join-Path $pluginRoot 'scripts\register-autoupdate-task.ps1'
if ($EveryHours -le 0) { Write-Host '  默认不注册；后续请手动运行更新 skill。' -ForegroundColor DarkGray }
elseif (Test-Path $register) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $register -EveryHours $EveryHours
}
else { Write-Warning "未找到 $register，跳过定时任务注册。" }

# --- 汇总 ---
Write-Host ''
Write-Host '================== 引导完成 ==================' -ForegroundColor Cyan
Write-Host '插件安装后需【重启 Claude Code 会话】生效（或 /reload-plugins）。' -ForegroundColor Cyan
Write-Host '后续更新默认由用户手动触发，不会在会话启动时或后台自动更新。' -ForegroundColor Cyan
Write-Host '手动更新：运行 scripts\update-team-tools.ps1。' -ForegroundColor Cyan
Write-Host '确需定时更新时，显式运行 scripts\register-autoupdate-task.ps1 -EveryHours <小时>。' -ForegroundColor DarkCyan
Write-Host '==============================================' -ForegroundColor Cyan
