<#
.SYNOPSIS
  一键拉取/更新公司团队工具仓库（全部走 Gitee），并完成可脚本化的安装：
  - git clone / git pull 四个仓库
  - project-domain-knowledge：npm install + build + 注册为 Claude Code MCP
  - 输出两个插件的 /plugin 安装命令（slash 命令需用户在 Claude Code 里执行）

.PARAMETER WorkspaceDir
  仓库克隆/更新的根目录。默认 $env:USERPROFILE\myWork。
  已存在的仓库会执行 git pull 更新，不会重复克隆。

.PARAMETER McpScope
  project-domain-knowledge MCP 的注册范围：user(默认，全局可用) / local / project。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\install-team-tools.ps1
  powershell -ExecutionPolicy Bypass -File .\install-team-tools.ps1 -WorkspaceDir D:\Users\zhang\myWork -McpScope user
#>
param(
    [string]$WorkspaceDir = "$env:USERPROFILE\myWork",
    [ValidateSet('user', 'local', 'project')]
    [string]$McpScope = 'user'
)

$ErrorActionPreference = 'Stop'

# Gitee 是公司当前源码管理（GitHub 仅部分仓库镜像，安装一律用 Gitee）
$Repos = @(
    @{ Name = 'team-standards';          Url = 'https://gitee.com/wyoooni/team-standards.git';          Type = 'plugin' }
    @{ Name = 'project-coding-profiles'; Url = 'https://gitee.com/wyoooni/project-coding-profiles.git'; Type = 'plugin' }
    @{ Name = 'project-domain-knowledge';Url = 'https://gitee.com/wyoooni/project-domain-knowledge.git';Type = 'mcp(engine)' }
    @{ Name = 'cross-project-topology';  Url = 'https://gitee.com/wyoooni/cross-project-topology.git';  Type = 'mcp(shared-engine)' }
)

function Test-Cmd($name) {
    return [bool](Get-Command $name -ErrorAction SilentlyContinue)
}

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host " 公司团队工具一键拉取/安装（Gitee 源）" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "工作区目录: $WorkspaceDir"
Write-Host "MCP 注册范围: $McpScope"
Write-Host ""

# --- 前置检查 ---
if (-not (Test-Cmd git)) {
    Write-Error "未检测到 git，请先安装 Git 并加入 PATH。"
    exit 1
}
$hasNode = Test-Cmd node
$hasNpm  = Test-Cmd npm
$hasClaude = Test-Cmd claude
if (-not $hasNode -or -not $hasNpm) {
    Write-Warning "未检测到 node/npm（>=18）。project-domain-knowledge(MCP) 的构建会被跳过，其余仓库照常拉取。"
}
if (-not $hasClaude) {
    Write-Warning "未检测到 claude CLI。MCP 自动注册会被跳过，稍后会打印手动注册命令。"
}

if (-not (Test-Path $WorkspaceDir)) {
    New-Item -ItemType Directory -Force -Path $WorkspaceDir | Out-Null
    Write-Host "已创建工作区目录: $WorkspaceDir"
}

# --- 第 1 步：拉取/更新全部仓库 ---
Write-Host ""
Write-Host "[1/3] 拉取/更新仓库 ..." -ForegroundColor Green
foreach ($r in $Repos) {
    $dest = Join-Path $WorkspaceDir $r.Name
    if (Test-Path (Join-Path $dest '.git')) {
        Write-Host "  -> 更新 $($r.Name) (git pull)"
        git -C $dest pull --ff-only
    }
    else {
        Write-Host "  -> 克隆 $($r.Name) ($($r.Url))"
        git clone $r.Url $dest
    }
}

# --- 第 2 步：构建 project-domain-knowledge，并用同一引擎注册两个 MCP 实例 ---
# 复用引擎：project-domain-knowledge 的 dist/server.js 是通用 md+frontmatter 知识引擎，
# 用 DOMAIN_KB_DIR 环境变量指向不同知识根目录即可服务不同知识库。一份代码、两个实例：
#   domain-knowledge -> 业务公共认知（project-domain-knowledge/knowledge）
#   cross-topology   -> 跨项目拓扑   （cross-project-topology/knowledge）
Write-Host ""
Write-Host "[2/3] 构建引擎并注册 MCP（domain-knowledge + cross-topology）..." -ForegroundColor Green
$mcpDir = Join-Path $WorkspaceDir 'project-domain-knowledge'
$mcpEntry = Join-Path $mcpDir 'dist\server.js'
$domainKbDir = Join-Path $mcpDir 'knowledge'
$topoDir = Join-Path $WorkspaceDir 'cross-project-topology'
$topoKbDir = Join-Path $topoDir 'knowledge'

# 用同一 server.js 注册一个 MCP 实例（幂等：先 remove 再 add），可带 DOMAIN_KB_DIR
function Register-Mcp($name, $kbDir) {
    Write-Host "  -> claude mcp add $name (DOMAIN_KB_DIR=$kbDir)"
    claude mcp remove $name -s $McpScope 2>$null | Out-Null
    if ($kbDir) {
        claude mcp add $name -s $McpScope -e "DOMAIN_KB_DIR=$kbDir" -- node "$mcpEntry"
    }
    else {
        claude mcp add $name -s $McpScope -- node "$mcpEntry"
    }
}

if ($hasNode -and $hasNpm) {
    Push-Location $mcpDir
    try {
        Write-Host "  -> npm install"
        npm install
        Write-Host "  -> npm run build"
        npm run build
    }
    finally {
        Pop-Location
    }
    if ($hasClaude) {
        if (Test-Path $mcpEntry) {
            # 实例 1：业务公共认知（默认根目录，省略 env 也行，这里显式指明更清楚）
            Register-Mcp 'domain-knowledge' $domainKbDir
            # 实例 2：跨项目拓扑——同一 server.js，DOMAIN_KB_DIR 指向 topology 仓库
            if (Test-Path $topoKbDir) {
                Register-Mcp 'cross-topology' $topoKbDir
            }
            else {
                Write-Warning "未找到 $topoKbDir（cross-project-topology 尚未建立 knowledge/ 知识根目录），跳过 cross-topology 注册。内容就绪后重跑本脚本即可注册。"
            }
        }
        else {
            Write-Warning "构建后未找到 $mcpEntry，跳过 MCP 注册。请检查 npm run build 是否成功。"
        }
    }
}
else {
    Write-Host "  (已跳过：缺少 node/npm)"
}

# --- 第 3 步：插件安装命令（slash 命令需在 Claude Code 里手动执行）---
Write-Host ""
Write-Host "[3/3] 安装两个插件（在 Claude Code 会话里执行以下 slash 命令）" -ForegroundColor Green
Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray
Write-Host "/plugin marketplace add https://gitee.com/wyoooni/team-standards.git"
Write-Host "/plugin install team-standards@team-standards"
Write-Host ""
Write-Host "/plugin marketplace add https://gitee.com/wyoooni/project-coding-profiles.git"
Write-Host "/plugin install project-coding-profiles@project-coding-profiles"
Write-Host ""
Write-Host "/reload-plugins"
Write-Host "----------------------------------------------------------------" -ForegroundColor DarkGray

Write-Host ""
Write-Host "完成。" -ForegroundColor Cyan
Write-Host "已就绪的本地仓库（在 $WorkspaceDir 下）："
foreach ($r in $Repos) { Write-Host "  - $($r.Name)  [$($r.Type)]" }
if (-not $hasClaude) {
    Write-Host ""
    Write-Warning "claude CLI 缺失，MCP 未自动注册。装好 claude CLI 后手动执行（同一 server.js，两个实例）："
    Write-Host "  claude mcp add domain-knowledge -s $McpScope -e `"DOMAIN_KB_DIR=$domainKbDir`" -- node `"$mcpEntry`""
    Write-Host "  claude mcp add cross-topology   -s $McpScope -e `"DOMAIN_KB_DIR=$topoKbDir`" -- node `"$mcpEntry`""
}
