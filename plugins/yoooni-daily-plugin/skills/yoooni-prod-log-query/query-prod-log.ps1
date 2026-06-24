<#
.SYNOPSIS
  查询 Yoooni 生产后台「接口注册日志」(apiRegistrylog_list.action)，用于线上排查。
  用【账号密码】自动登录（Spring Security /j_spring_security_check）拿会话，不再手工复制 cookie。
  账号密码存用户主目录配置文件，不硬编码、不入仓库。

.PARAMETER StartDate   制单日期起，yyyy-MM-dd，默认 3 天前
.PARAMETER EndDate     制单日期止，yyyy-MM-dd，默认今天
.PARAMETER ApiName     接口名 obj.apiname，可空
.PARAMETER Url         接口方法名 obj.url（主过滤条件，如 insertOrUpdatePoconfig），可空
.PARAMETER Content     内容关键词 obj.content，可空
.PARAMETER Enable      启用状态 obj.enable，可空
.PARAMETER AllPages    开关：自动翻页抓取全部分页（默认只取第 1 页 20 条）
.PARAMETER MaxPages    AllPages 时最多翻几页，默认 50（防呆上限）
.PARAMETER OutDir      HTML 结果保存目录，默认 %TEMP%\yoooni-prod-log

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\query-prod-log.ps1 -Url insertOrUpdatePoconfig
  powershell -ExecutionPolicy Bypass -File .\query-prod-log.ps1 -StartDate 2026-06-13 -EndDate 2026-06-16 -Url insertOrUpdatePoconfig -AllPages

.NOTES
  退出码：0 成功 / 2 账号密码未配置 / 3 登录失败(账号密码错误或失效) / 1 请求失败
#>
param(
    [string]$StartDate,
    [string]$EndDate,
    [string]$ApiName = '',
    [string]$Url = '',
    [string]$Content = '',
    [string]$Enable = '',
    [switch]$AllPages,
    [int]$MaxPages = 50,
    [string]$OutDir = "$env:TEMP\yoooni-prod-log"
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36'

# --- 配置文件（账号密码存这里，插件升级不会覆盖）---
$cfgDir = "$env:USERPROFILE\.config\yoooni"
$cfgFile = "$cfgDir\prod-backend.json"

if (-not (Test-Path $cfgFile)) {
    New-Item -ItemType Directory -Force $cfgDir | Out-Null
    @'
{
  "base_url": "https://wyoooni.net",
  "_comment": "填入生产后台登录账号密码即可，脚本会自动登录拿会话；不需要手工复制 cookie。",
  "username": "请填写生产后台登录账号",
  "password": "请填写生产后台登录密码"
}
'@ | Set-Content -Encoding UTF8 $cfgFile
    Write-Host "已创建配置模板：$cfgFile" -ForegroundColor Yellow
    Write-Host "请填入生产后台登录【账号 username】和【密码 password】，填好后重新执行。" -ForegroundColor Yellow
    exit 2
}

$cfg = Get-Content -Encoding UTF8 $cfgFile -Raw | ConvertFrom-Json
$baseUrl  = if ($cfg.base_url) { $cfg.base_url.TrimEnd('/') } else { 'https://wyoooni.net' }
$username = $cfg.username
$password = $cfg.password

if (-not $username -or -not $password -or $username -like '请填写*' -or $password -like '请填写*') {
    Write-Host "配置文件里账号密码还没填：$cfgFile" -ForegroundColor Yellow
    Write-Host "请填入 username / password 后重试。" -ForegroundColor Yellow
    exit 2
}

# --- 默认日期 ---
if (-not $StartDate) { $StartDate = (Get-Date).AddDays(-3).ToString('yyyy-MM-dd') }
if (-not $EndDate)   { $EndDate   = (Get-Date).ToString('yyyy-MM-dd') }

function Enc($s) { [System.Uri]::EscapeDataString([string]$s) }

# --- 自动登录（Spring Security）---
Write-Host "登录生产后台 $baseUrl ..." -ForegroundColor Cyan
try {
    # 先 GET 登录页建立会话
    Invoke-WebRequest -Uri "$baseUrl/login/login.jsp" -SessionVariable sess -UserAgent $UA -UseBasicParsing -TimeoutSec 60 | Out-Null
    $loginBody = "j_username=$(Enc $username)&j_password=$(Enc $password)&app=app&rmbUser=true"
    $rl = Invoke-WebRequest -Uri "$baseUrl/j_spring_security_check" -Method Post -Body $loginBody `
            -WebSession $sess -UserAgent $UA -ContentType 'application/x-www-form-urlencoded' `
            -UseBasicParsing -TimeoutSec 60 -MaximumRedirection 5
}
catch {
    Write-Host "登录请求失败：$($_.Exception.Message)" -ForegroundColor Red
    Write-Host "排查：是否在公司网络/可达 $baseUrl（Test-NetConnection wyoooni.net -Port 443）。" -ForegroundColor Red
    exit 1
}

$loginFinal = ''
try { $loginFinal = $rl.BaseResponse.ResponseUri.AbsoluteUri } catch {}
if ($loginFinal -match 'error=true' -or $rl.Content -match '睿尚ERP系统登录') {
    Write-Host "==================================================" -ForegroundColor Yellow
    Write-Host " 登录失败：账号或密码不正确 / 账号被锁" -ForegroundColor Yellow
    Write-Host "==================================================" -ForegroundColor Yellow
    Write-Host "请检查配置文件里的 username / password：$cfgFile" -ForegroundColor Yellow
    Write-Host "（用浏览器登录 $baseUrl 验证账号密码是否能正常进后台）" -ForegroundColor Yellow
    exit 3
}
Write-Host "登录成功。" -ForegroundColor Green

# --- 组装查询 ---
$listAction = "$baseUrl/sys/apiRegistrylog_list.action"
$body = "obj.startmakedate=$(Enc $StartDate)" +
        "&obj.endmakedate=$(Enc $EndDate)" +
        "&obj.apiname=$(Enc $ApiName)" +
        "&obj.url=$(Enc $Url)" +
        "&obj.content=$(Enc $Content)" +
        "&obj.enable=$(Enc $Enable)"

Write-Host "查询接口注册日志 ..." -ForegroundColor Cyan
Write-Host "  日期     : $StartDate ~ $EndDate"
Write-Host "  url/方法 : $(if ($Url) { $Url } else { '(全部)' })  apiname=$(if ($ApiName) { $ApiName } else { '(空)' })  enable=$(if ($Enable) { $Enable } else { '(空)' })"
Write-Host "  分页     : $(if ($AllPages) { "全部(最多 $MaxPages 页)" } else { '仅第 1 页(20 条)' })"
Write-Host ""

function Invoke-Page([int]$page) {
    $ep = "$listAction`?currentPage=$page"
    Invoke-WebRequest -Uri $ep -Method Post -Body $body -WebSession $sess -UserAgent $UA `
        -Headers @{ 'Referer' = $listAction } -ContentType 'application/x-www-form-urlencoded' `
        -UseBasicParsing -TimeoutSec 90
}

New-Item -ItemType Directory -Force $OutDir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'

try {
    $first = Invoke-Page 1
}
catch {
    Write-Host "查询请求失败：$($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
$firstHtml = $first.Content

# 会话失效兜底（理论上刚登录不会，但防止并发挤掉）
if ($firstHtml -match 'login\.jsp' -or $firstHtml -match '睿尚ERP系统登录') {
    Write-Host "登录会话已失效（可能账号在别处重新登录挤掉了本会话），请重试。" -ForegroundColor Yellow
    exit 3
}

# 总记录 / 总页数
$total = ([regex]::Match($firstHtml, '总记录:(\d+)条')).Groups[1].Value
$totalPages = ([regex]::Match($firstHtml, '当前页:\d+/(\d+)总页数')).Groups[1].Value
if (-not $totalPages) { $totalPages = 1 }

if (-not $AllPages) {
    $outFile = Join-Path $OutDir ("apilog_{0}.html" -f $stamp)
    [System.IO.File]::WriteAllText($outFile, $firstHtml, [System.Text.UTF8Encoding]::new($false))
    $rowCount = ([regex]::Matches($firstHtml, 'onclick="deleteClick')).Count
    Write-Host "查询成功（第 1 页）。" -ForegroundColor Green
    Write-Host "  总记录:$total 条，总页数:$totalPages，本页数据行:$rowCount" -ForegroundColor Green
    Write-Host "  原始 HTML 已保存：$outFile" -ForegroundColor Green
    if ([int]$totalPages -gt 1) {
        Write-Host "  ⚠ 还有更多页未抓取，需要全部请加 -AllPages 重跑。" -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "提示：可让 AI 直接 Read 上面的 HTML 文件解析日志表格。" -ForegroundColor DarkGray
    exit 0
}

# --- AllPages：翻页抓取，把各页数据行 <tr> 拼进一个合并 HTML ---
$pages = [Math]::Min([int]$totalPages, $MaxPages)
$seen = @{}
$dataRows = New-Object System.Collections.Generic.List[string]
function Add-Rows([string]$html) {
    $trs = [regex]::Matches($html, '(?s)<tr[^>]*>.*?</tr>')
    $added = 0
    foreach ($tr in $trs) {
        if ($tr.Value -notmatch 'onclick="deleteClick') { continue }  # 只要数据行
        $key = [string]([regex]::Match($tr.Value, 'deleteClick\((\d+)\)')).Groups[1].Value
        if (-not $key) { $key = $tr.Value }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        $dataRows.Add($tr.Value)
        $added++
    }
    return $added
}
$null = Add-Rows $firstHtml
Write-Host ("page 1/{0}: 累计数据行 {1}" -f $pages, $dataRows.Count)
for ($p = 2; $p -le $pages; $p++) {
    try { $rp = Invoke-Page $p } catch { Write-Host "page $p 抓取失败：$($_.Exception.Message)" -ForegroundColor Yellow; break }
    $add = Add-Rows $rp.Content
    Write-Host ("page {0}/{1}: 本页新增 {2}，累计 {3}" -f $p, $pages, $add, $dataRows.Count)
    if ($add -eq 0) { break }
}

# 合并输出：表头 + 所有数据行
$tableHeader = ([regex]::Match($firstHtml, '(?s)<tr>\s*<th.*?</tr>')).Value
$combined = "<html><head><meta charset='utf-8'><title>apiRegistrylog 合并($($dataRows.Count)行)</title></head><body>" +
            "<p>总记录:$total 条，已合并 $($dataRows.Count) 条数据行（去重）。筛选 url=$Url 日期 $StartDate~$EndDate</p>" +
            "<table border='1' cellpadding='3'>" + $tableHeader + ($dataRows -join "`n") + "</table></body></html>"
$outFile = Join-Path $OutDir ("apilog_all_{0}.html" -f $stamp)
[System.IO.File]::WriteAllText($outFile, $combined, [System.Text.UTF8Encoding]::new($false))

Write-Host "查询成功（已翻页合并）。" -ForegroundColor Green
Write-Host "  总记录:$total 条，总页数:$totalPages，合并去重数据行:$($dataRows.Count)" -ForegroundColor Green
Write-Host "  合并 HTML 已保存：$outFile" -ForegroundColor Green
Write-Host ""
Write-Host "提示：可让 AI 直接 Read 上面的合并 HTML 解析日志表格。" -ForegroundColor DarkGray
exit 0
