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
.PARAMETER RetentionDays  脱敏 HTML 的本地保留天数，默认 3 天（1~30）
.PARAMETER SetCredential  交互式录入账号密码，并以当前 Windows 用户 DPAPI 加密保存

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\query-prod-log.ps1 -Url insertOrUpdatePoconfig
  powershell -ExecutionPolicy Bypass -File .\query-prod-log.ps1 -StartDate 2026-06-13 -EndDate 2026-06-16 -Url insertOrUpdatePoconfig -AllPages
  powershell -ExecutionPolicy Bypass -File .\query-prod-log.ps1 -SetCredential

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
    [string]$OutDir = "$env:TEMP\yoooni-prod-log",
    [ValidateRange(1, 30)]
    [int]$RetentionDays = 3,
    [switch]$SetCredential,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Security
$UA = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36'
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Protect-Password([string]$PlainText) {
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($PlainText)
    try {
        $protected = [System.Security.Cryptography.ProtectedData]::Protect(
            $bytes,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [Convert]::ToBase64String($protected)
    }
    finally {
        if ($bytes) { [Array]::Clear($bytes, 0, $bytes.Length) }
    }
}

function Unprotect-Password([string]$CipherText) {
    $protected = [Convert]::FromBase64String($CipherText)
    $bytes = $null
    try {
        $bytes = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $protected,
            $null,
            [System.Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [System.Text.Encoding]::UTF8.GetString($bytes)
    }
    finally {
        if ($protected) { [Array]::Clear($protected, 0, $protected.Length) }
        if ($bytes) { [Array]::Clear($bytes, 0, $bytes.Length) }
    }
}

function Convert-SecureStringToPlainText([Security.SecureString]$Value) {
    $ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr) }
}

function Protect-LocalFile([string]$FilePath) {
    try {
        $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        $owner = New-Object System.Security.Principal.NTAccount($identity)
        $acl = New-Object System.Security.AccessControl.FileSecurity
        $acl.SetOwner($owner)
        $acl.SetAccessRuleProtection($true, $false)
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $owner,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            [System.Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $FilePath -AclObject $acl
    }
    catch {
        Write-Warning "无法收紧本地文件 ACL：$FilePath。$($_.Exception.Message)"
    }
}

function Save-Config($Config, [string]$FilePath) {
    $tmp = "$FilePath.tmp-$PID"
    $json = $Config | ConvertTo-Json -Depth 8
    try {
        [System.IO.File]::WriteAllText($tmp, $json, $Utf8NoBom)
        Move-Item -LiteralPath $tmp -Destination $FilePath -Force
        Protect-LocalFile $FilePath
    }
    finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Protect-LogHtml([string]$Html) {
    $value = [string]$Html
    $value = [regex]::Replace($value, '(?is)-----BEGIN [^-\r\n]*PRIVATE KEY-----.*?-----END [^-\r\n]*PRIVATE KEY-----', '[REDACTED_PRIVATE_KEY]')
    $value = [regex]::Replace($value, '(?i)\b(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]{8,}', '$1 [REDACTED]')
    $value = [regex]::Replace($value, '(?i)\b(?:sk-[A-Za-z0-9_-]{16,}|github_pat_[A-Za-z0-9_]{16,}|gh[pousr]_[A-Za-z0-9]{16,}|glpat-[A-Za-z0-9_-]{16,}|AKIA[A-Z0-9]{16})\b', '[REDACTED_TOKEN]')
    $value = [regex]::Replace($value, '(?i)((?:password|passwd|pwd|token|api[_-]?key|secret|client[_-]?secret|cookie|session[_-]?id)\s*(?:&quot;|["''])?\s*[:=]\s*(?:&quot;|["''])?)[^"''\s,;&<}]+', '$1[REDACTED]')
    $value = [regex]::Replace($value, '\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', '[REDACTED_EMAIL]', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $value = [regex]::Replace($value, '(^|\D)1[3-9]\d{9}(?!\d)', '$1[REDACTED_PHONE]')
    return $value
}

function Write-SanitizedHtml([string]$FilePath, [string]$Html) {
    [System.IO.File]::WriteAllText($FilePath, (Protect-LogHtml $Html), $Utf8NoBom)
    Protect-LocalFile $FilePath
}

function Remove-ExpiredOutputs([string]$Directory, [int]$Days) {
    $cutoff = (Get-Date).AddDays(-$Days)
    Get-ChildItem -LiteralPath $Directory -Filter 'apilog_*.html' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoff } |
        Remove-Item -Force -ErrorAction SilentlyContinue
}

function Convert-LegacyPassword($Config) {
    $property = $Config.PSObject.Properties['password']
    if (-not $property) { return $false }
    $legacy = [string]$property.Value
    if (-not $legacy -or $legacy -like '请填写*') { return $false }
    $Config | Add-Member -NotePropertyName password_protected -NotePropertyValue (Protect-Password $legacy) -Force
    $Config.PSObject.Properties.Remove('password')
    return $true
}

function Assert-ProductionBaseUrl([string]$Value) {
    try { $uri = [Uri]$Value } catch { throw "base_url 不是有效 URL：$Value" }
    if (-not $uri.IsAbsoluteUri -or $uri.Scheme -ne 'https' -or $uri.Host -ne 'wyoooni.net' -or -not $uri.IsDefaultPort) {
        throw '安全校验失败：base_url 必须是 https://wyoooni.net，拒绝把生产凭据发送到其它地址。'
    }
    if ($uri.UserInfo -or $uri.Query -or $uri.Fragment -or ($uri.AbsolutePath -and $uri.AbsolutePath -ne '/')) {
        throw '安全校验失败：base_url 只能填写站点根地址 https://wyoooni.net。'
    }
    return 'https://wyoooni.net'
}

if ($SelfTest) {
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $selfTestRoot = Join-Path $systemTemp ('yoooni-prod-log-selftest-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $selfTestRoot | Out-Null
    try {
        $secret = 'self-test-secret'
        $cipher = Protect-Password $secret
        if ((Unprotect-Password $cipher) -ne $secret) { throw 'DPAPI round-trip failed' }

        $legacyConfig = [pscustomobject]@{ username = 'tester'; password = $secret }
        if (-not (Convert-LegacyPassword $legacyConfig)) { throw 'legacy password was not migrated' }
        if ($legacyConfig.PSObject.Properties['password']) { throw 'plaintext password property remains after migration' }
        if ((Unprotect-Password $legacyConfig.password_protected) -ne $secret) { throw 'migrated password cannot be decrypted' }

        $configPath = Join-Path $selfTestRoot 'prod-backend.json'
        Save-Config $legacyConfig $configPath
        $savedConfig = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8
        if ($savedConfig -match [regex]::Escape($secret)) { throw 'saved config contains plaintext password' }
        $savedAcl = Get-Acl -LiteralPath $configPath
        if (-not $savedAcl.AreAccessRulesProtected) { throw 'config ACL still inherits access rules' }

        $sample = Protect-LogHtml 'password=hunter2 token=abc123456789 test@example.com 13800138000'
        if ($sample -match 'hunter2|abc123456789|test@example.com|13800138000') { throw 'redaction self-test failed' }

        if ((Assert-ProductionBaseUrl 'https://wyoooni.net') -ne 'https://wyoooni.net') { throw 'URL validation failed' }
        foreach ($unsafeUrl in @('http://wyoooni.net', 'https://example.com', 'https://wyoooni.net:444', 'https://wyoooni.net/login')) {
            try { $null = Assert-ProductionBaseUrl $unsafeUrl; throw "unsafe URL was accepted: $unsafeUrl" } catch {
                if ($_.Exception.Message -like 'unsafe URL was accepted:*') { throw }
            }
        }

        $oldOutput = Join-Path $selfTestRoot 'apilog_old.html'
        $newOutput = Join-Path $selfTestRoot 'apilog_new.html'
        $unrelated = Join-Path $selfTestRoot 'unrelated.html'
        [IO.File]::WriteAllText($oldOutput, 'old', $Utf8NoBom)
        [IO.File]::WriteAllText($newOutput, 'new', $Utf8NoBom)
        [IO.File]::WriteAllText($unrelated, 'keep', $Utf8NoBom)
        (Get-Item -LiteralPath $oldOutput).LastWriteTime = (Get-Date).AddDays(-10)
        (Get-Item -LiteralPath $unrelated).LastWriteTime = (Get-Date).AddDays(-10)
        Remove-ExpiredOutputs $selfTestRoot 3
        if (Test-Path -LiteralPath $oldOutput) { throw 'expired production-log output was not removed' }
        if (-not (Test-Path -LiteralPath $newOutput)) { throw 'current production-log output was removed' }
        if (-not (Test-Path -LiteralPath $unrelated)) { throw 'unrelated file was removed by retention cleanup' }
    }
    finally {
        $resolved = [IO.Path]::GetFullPath($selfTestRoot)
        if (-not $resolved.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -or
            -not ([IO.Path]::GetFileName($resolved)).StartsWith('yoooni-prod-log-selftest-')) {
            throw "unsafe self-test cleanup target: $resolved"
        }
        if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
    }
    Write-Host 'self-test passed'
    exit 0
}

# --- 配置文件（密码由当前 Windows 用户 DPAPI 加密，插件升级不会覆盖）---
$cfgDir = "$env:USERPROFILE\.config\yoooni"
$cfgFile = "$cfgDir\prod-backend.json"

if (-not (Test-Path $cfgFile)) {
    New-Item -ItemType Directory -Force $cfgDir | Out-Null
    $template = [ordered]@{
        base_url = 'https://wyoooni.net'
        _comment = '运行 query-prod-log.ps1 -SetCredential 安全录入；password_protected 由 Windows DPAPI CurrentUser 加密。'
        username = ''
        password_protected = ''
    }
    Save-Config $template $cfgFile
    Write-Host "已创建配置模板：$cfgFile" -ForegroundColor Yellow
    if (-not $SetCredential) {
        Write-Host "请运行本脚本并加 -SetCredential，以交互方式安全录入账号密码。" -ForegroundColor Yellow
        exit 2
    }
}

$cfg = Get-Content -Encoding UTF8 $cfgFile -Raw | ConvertFrom-Json
$baseUrl  = Assert-ProductionBaseUrl $(if ($cfg.base_url) { [string]$cfg.base_url } else { 'https://wyoooni.net' })
$username = $cfg.username

if ($SetCredential) {
    $enteredUsername = Read-Host "生产后台账号$(if ($username) { "（回车保留 $username）" })"
    if ($enteredUsername) { $username = $enteredUsername }
    if (-not $username -or $username -like '请填写*') {
        Write-Host '账号不能为空。' -ForegroundColor Yellow
        exit 2
    }
    $securePassword = Read-Host '生产后台密码（输入不会回显）' -AsSecureString
    $plainPassword = Convert-SecureStringToPlainText $securePassword
    if (-not $plainPassword) {
        Write-Host '密码不能为空。' -ForegroundColor Yellow
        exit 2
    }
    $cfg | Add-Member -NotePropertyName username -NotePropertyValue $username -Force
    $cfg | Add-Member -NotePropertyName password_protected -NotePropertyValue (Protect-Password $plainPassword) -Force
    $cfg.PSObject.Properties.Remove('password')
    Save-Config $cfg $cfgFile
    $plainPassword = $null
    Write-Host "凭据已用 Windows DPAPI(CurrentUser) 加密保存：$cfgFile" -ForegroundColor Green
    exit 0
}

$password = $null
$legacyPassword = if ($cfg.PSObject.Properties['password']) { [string]$cfg.password } else { '' }
if ($legacyPassword -and $legacyPassword -notlike '请填写*') {
    try {
        if (-not (Convert-LegacyPassword $cfg)) { throw '未找到可迁移的明文密码。' }
        Save-Config $cfg $cfgFile
        $password = $legacyPassword
        Write-Host '已将旧版明文密码原位迁移为 DPAPI 密文。' -ForegroundColor Green
    }
    catch {
        Write-Host "旧版明文密码迁移失败，未继续请求生产环境：$($_.Exception.Message)" -ForegroundColor Red
        exit 2
    }
}
elseif ($cfg.password_protected) {
    try { $password = Unprotect-Password ([string]$cfg.password_protected) }
    catch {
        Write-Host '无法解密密码（配置可能来自另一 Windows 账号）。请加 -SetCredential 重新录入。' -ForegroundColor Yellow
        exit 2
    }
}

if (-not $username -or -not $password -or $username -like '请填写*') {
    Write-Host "生产凭据尚未配置：$cfgFile" -ForegroundColor Yellow
    Write-Host "请运行：powershell -ExecutionPolicy Bypass -File `"$PSCommandPath`" -SetCredential" -ForegroundColor Yellow
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
Remove-ExpiredOutputs $OutDir $RetentionDays
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
    Write-SanitizedHtml $outFile $firstHtml
    $rowCount = ([regex]::Matches($firstHtml, 'onclick="deleteClick')).Count
    Write-Host "查询成功（第 1 页）。" -ForegroundColor Green
    Write-Host "  总记录:$total 条，总页数:$totalPages，本页数据行:$rowCount" -ForegroundColor Green
    Write-Host "  脱敏 HTML 已保存：$outFile（保留 $RetentionDays 天）" -ForegroundColor Green
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
Write-SanitizedHtml $outFile $combined

Write-Host "查询成功（已翻页合并）。" -ForegroundColor Green
Write-Host "  总记录:$total 条，总页数:$totalPages，合并去重数据行:$($dataRows.Count)" -ForegroundColor Green
Write-Host "  脱敏合并 HTML 已保存：$outFile（保留 $RetentionDays 天）" -ForegroundColor Green
Write-Host ""
Write-Host "提示：可让 AI 直接 Read 上面的合并 HTML 解析日志表格。" -ForegroundColor DarkGray
exit 0
