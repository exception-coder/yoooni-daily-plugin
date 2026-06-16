<#
.SYNOPSIS
  查询 Yoooni 生产后台「接口注册日志」(apiRegistrylog_list.action)，用于线上排查。
  cookie 存用户主目录配置文件，不硬编码；过期会检测并提示替换。

.PARAMETER StartDate   制单日期起，yyyy-MM-dd，默认 3 天前
.PARAMETER EndDate     制单日期止，yyyy-MM-dd，默认今天
.PARAMETER ApiName     接口名 obj.apiname，可空
.PARAMETER Url         接口方法名 obj.url（主过滤条件，如 insertOrUpdatePoconfig），可空
.PARAMETER Content     内容关键词 obj.content，可空
.PARAMETER Enable      启用状态 obj.enable，可空
.PARAMETER OutDir      HTML 结果保存目录，默认 %TEMP%\yoooni-prod-log

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\query-prod-log.ps1 -Url insertOrUpdatePoconfig
  powershell -ExecutionPolicy Bypass -File .\query-prod-log.ps1 -StartDate 2026-06-13 -EndDate 2026-06-16 -Url insertOrUpdatePoconfig
#>
param(
    [string]$StartDate,
    [string]$EndDate,
    [string]$ApiName = '',
    [string]$Url = '',
    [string]$Content = '',
    [string]$Enable = '',
    [string]$OutDir = "$env:TEMP\yoooni-prod-log"
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- 配置文件（cookie 存这里，插件升级不会覆盖）---
$cfgDir = "$env:USERPROFILE\.config\yoooni"
$cfgFile = "$cfgDir\prod-backend.json"

if (-not (Test-Path $cfgFile)) {
    New-Item -ItemType Directory -Force $cfgDir | Out-Null
    @'
{
  "base_url": "https://wyoooni.net",
  "_comment": "从浏览器开发者工具复制生产后台请求里的整段 cookie 值粘到下面；过期后重新复制替换即可。",
  "cookie": "请粘贴生产后台的 cookie，例如 JSESSIONID=xxx; rmbUser=true; userName=xxx; passWord=xxx"
}
'@ | Set-Content -Encoding UTF8 $cfgFile
    Write-Host "已创建配置模板：$cfgFile" -ForegroundColor Yellow
    Write-Host "请在浏览器登录生产后台后，从开发者工具复制整段 cookie 填入该文件的 cookie 字段，填好后重新执行。" -ForegroundColor Yellow
    exit 2
}

$cfg = Get-Content -Encoding UTF8 $cfgFile -Raw | ConvertFrom-Json
$baseUrl = if ($cfg.base_url) { $cfg.base_url.TrimEnd('/') } else { 'https://wyoooni.net' }
$cookie = $cfg.cookie
if (-not $cookie -or $cookie -like '请粘贴*') {
    Write-Host "配置文件里 cookie 还没填：$cfgFile" -ForegroundColor Yellow
    Write-Host "请填入生产后台 cookie 后重试。" -ForegroundColor Yellow
    exit 2
}

# --- 默认日期 ---
if (-not $StartDate) { $StartDate = (Get-Date).AddDays(-3).ToString('yyyy-MM-dd') }
if (-not $EndDate)   { $EndDate   = (Get-Date).ToString('yyyy-MM-dd') }

# --- 组装请求 ---
$endpoint = "$baseUrl/sys/apiRegistrylog_list.action"
function Enc($s) { [System.Uri]::EscapeDataString([string]$s) }
$body = "obj.startmakedate=$(Enc $StartDate)" +
        "&obj.endmakedate=$(Enc $EndDate)" +
        "&obj.apiname=$(Enc $ApiName)" +
        "&obj.url=$(Enc $Url)" +
        "&obj.content=$(Enc $Content)" +
        "&obj.enable=$(Enc $Enable)"

$headers = @{
    'Cookie'       = $cookie
    'Referer'      = $endpoint
    'User-Agent'   = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 yoooni-daily-plugin'
    'Content-Type' = 'application/x-www-form-urlencoded'
}

Write-Host "查询生产后台接口注册日志 ..." -ForegroundColor Cyan
Write-Host "  endpoint : $endpoint"
Write-Host "  日期     : $StartDate ~ $EndDate"
Write-Host "  url/方法 : $(if ($Url) { $Url } else { '(全部)' })  apiname=$(if ($ApiName) { $ApiName } else { '(空)' })  enable=$(if ($Enable) { $Enable } else { '(空)' })"
Write-Host ""

try {
    $resp = Invoke-WebRequest -Uri $endpoint -Method Post -Body $body -Headers $headers -UseBasicParsing -TimeoutSec 60
}
catch {
    Write-Host "请求失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "排查：1) 是否在公司网络/可达 $baseUrl  2) cookie 是否过期(见下)。" -ForegroundColor Red
    exit 1
}

$content = $resp.Content
$finalUri = ''
try { $finalUri = $resp.BaseResponse.ResponseUri.AbsoluteUri } catch {}

# --- cookie 过期 / 未登录检测 ---
$looksLogin = ($finalUri -match '(?i)login') -or
              ($content -match '(?i)login\.jsp') -or
              (($content -match '(?i)密\s*码') -and ($content -notmatch 'apiRegistrylog'))
$looksExpected = $content -match 'apiRegistrylog' -or $content -match 'obj\.startmakedate'

if ($looksLogin -or -not $looksExpected) {
    Write-Host "==================================================" -ForegroundColor Yellow
    Write-Host " cookie 可能已过期 / 未登录" -ForegroundColor Yellow
    Write-Host "==================================================" -ForegroundColor Yellow
    Write-Host "返回页面不像日志列表（疑似跳到登录页）。final-uri=$finalUri" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "请替换 cookie 后重试：" -ForegroundColor Yellow
    Write-Host "  1. 浏览器登录 $baseUrl" -ForegroundColor Yellow
    Write-Host "  2. F12 开发者工具 → Network → 任一请求 → 复制 Request Headers 里整段 cookie 值" -ForegroundColor Yellow
    Write-Host "  3. 粘贴到配置文件的 cookie 字段：$cfgFile" -ForegroundColor Yellow
    Write-Host "  4. 重新执行本次查询" -ForegroundColor Yellow
    # 仍保存返回内容，便于人工确认是不是登录页
    New-Item -ItemType Directory -Force $OutDir | Out-Null
    $dbg = Join-Path $OutDir ("expired_{0}.html" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    [System.IO.File]::WriteAllText($dbg, $content, [System.Text.UTF8Encoding]::new($false))
    Write-Host "（返回内容已存：$dbg）" -ForegroundColor DarkGray
    exit 3
}

# --- 保存 + 概要 ---
New-Item -ItemType Directory -Force $OutDir | Out-Null
$outFile = Join-Path $OutDir ("apilog_{0}.html" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
[System.IO.File]::WriteAllText($outFile, $content, [System.Text.UTF8Encoding]::new($false))

$rowCount = ([regex]::Matches($content, '(?i)<tr')).Count
Write-Host "查询成功。" -ForegroundColor Green
Write-Host "  原始 HTML 已保存：$outFile" -ForegroundColor Green
Write-Host "  HTML 大小：$([math]::Round($content.Length/1KB,1)) KB，<tr> 行数约：$rowCount"
Write-Host ""
Write-Host "提示：可让 AI 直接 Read 上面的 HTML 文件解析日志表格，或在浏览器打开核对。" -ForegroundColor DarkGray
