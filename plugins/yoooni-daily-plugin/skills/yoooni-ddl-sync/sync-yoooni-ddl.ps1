<#
.SYNOPSIS
  Safely checks or publishes the Yoooni Oracle DDL baseline.
#>
param(
    [ValidateSet('SetCredential', 'Check', 'Sync', 'Status', 'SelfTest')]
    [string]$Mode = 'Sync',
    [string]$ProjectRoot,
    [string]$KnowledgeRepoRoot,
    [string]$JdbcUrl,
    [string]$Username,
    [string]$JdbcDriver,
    [string]$Schema = 'YOOONI',
    [string]$ConfigFile = "$env:USERPROFILE\.config\yoooni\ddl-sync.json",
    [switch]$AllowShrink
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$GeneratedStart = '<!-- AUTO-GENERATED-DDL:START -->'
$GeneratedEnd = '<!-- AUTO-GENERATED-DDL:END -->'
$MutexName = 'Local\YoooniDdlSnapshotSync'

function Protect-Password([string]$PlainText) {
    $bytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
    try {
        $protected = [Security.Cryptography.ProtectedData]::Protect(
            $bytes,
            $null,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
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
        $bytes = [Security.Cryptography.ProtectedData]::Unprotect(
            $protected,
            $null,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        return [Text.Encoding]::UTF8.GetString($bytes)
    }
    finally {
        if ($protected) { [Array]::Clear($protected, 0, $protected.Length) }
        if ($bytes) { [Array]::Clear($bytes, 0, $bytes.Length) }
    }
}

function Convert-SecureStringToPlainText([Security.SecureString]$Value) {
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}

function Protect-LocalFile([string]$FilePath) {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $owner = New-Object Security.Principal.NTAccount($identity)
        $acl = New-Object Security.AccessControl.FileSecurity
        $acl.SetOwner($owner)
        $acl.SetAccessRuleProtection($true, $false)
        $rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $owner,
            [Security.AccessControl.FileSystemRights]::FullControl,
            [Security.AccessControl.AccessControlType]::Allow
        )
        $acl.AddAccessRule($rule)
        Set-Acl -LiteralPath $FilePath -AclObject $acl
    }
    catch {
        Write-Warning "Unable to restrict local config ACL: $FilePath"
    }
}

function Save-Config($Config, [string]$FilePath) {
    $directory = Split-Path -Parent $FilePath
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $temporary = "$FilePath.tmp-$PID"
    try {
        [IO.File]::WriteAllText($temporary, ($Config | ConvertTo-Json -Depth 8), $Utf8NoBom)
        Move-Item -LiteralPath $temporary -Destination $FilePath -Force
        Protect-LocalFile $FilePath
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-LastPropertyValue([string]$FilePath, [string]$Key) {
    if (-not (Test-Path -LiteralPath $FilePath)) { return $null }
    $value = $null
    foreach ($line in Get-Content -LiteralPath $FilePath) {
        if ($line -match '^\s*[#!]') { continue }
        $parts = $line -split '=', 2
        if ($parts.Count -eq 2 -and $parts[0].Trim() -eq $Key) { $value = $parts[1].Trim() }
    }
    return $value
}

function Resolve-DriverPath([string]$Root, [string]$Requested) {
    if ($Requested) { return [IO.Path]::GetFullPath($Requested) }
    foreach ($candidate in @('lib\ojdbc14.jar', 'WebRoot\WEB-INF\lib\ojdbc14.jar')) {
        $path = Join-Path $Root $candidate
        if (Test-Path -LiteralPath $path) { return [IO.Path]::GetFullPath($path) }
    }
    return $null
}

function Initialize-Credential {
    $existing = if (Test-Path -LiteralPath $ConfigFile) {
        Get-Content -Raw -LiteralPath $ConfigFile -Encoding UTF8 | ConvertFrom-Json
    } else { $null }
    $resolvedProject = if ($ProjectRoot) { $ProjectRoot } elseif ($existing) { $existing.project_root } else { '' }
    $resolvedKnowledge = if ($KnowledgeRepoRoot) { $KnowledgeRepoRoot } elseif ($existing) { $existing.knowledge_repo_root } else { '' }
    if (-not $resolvedProject -or -not $resolvedKnowledge) {
        throw 'ProjectRoot and KnowledgeRepoRoot are required for first-time configuration.'
    }
    $resolvedProject = [IO.Path]::GetFullPath($resolvedProject)
    $resolvedKnowledge = [IO.Path]::GetFullPath($resolvedKnowledge)
    $properties = Join-Path $resolvedProject 'src\jdbc.properties'
    $resolvedUrl = if ($JdbcUrl) { $JdbcUrl } elseif ($existing) { $existing.jdbc_url } else {
        Get-LastPropertyValue $properties 'jdbc.url'
    }
    $resolvedUser = if ($Username) { $Username } elseif ($existing) { $existing.username } else {
        Get-LastPropertyValue $properties 'jdbc.username'
    }
    $resolvedDriver = Resolve-DriverPath $resolvedProject $(if ($JdbcDriver) { $JdbcDriver } elseif ($existing) { $existing.jdbc_driver } else { '' })
    if (-not $resolvedUrl -or $resolvedUrl -notmatch '^jdbc:oracle:thin:@') {
        throw 'A jdbc:oracle:thin URL is required.'
    }
    if (-not $resolvedUser -or -not $resolvedDriver -or -not (Test-Path -LiteralPath $resolvedDriver)) {
        throw 'Oracle username or JDBC driver is missing.'
    }
    $securePassword = Read-Host 'Oracle password (input hidden)' -AsSecureString
    $plainPassword = Convert-SecureStringToPlainText $securePassword
    if (-not $plainPassword) { throw 'Oracle password cannot be empty.' }
    try {
        $config = [ordered]@{
            project_root = $resolvedProject
            knowledge_repo_root = $resolvedKnowledge
            jdbc_driver = $resolvedDriver
            jdbc_url = $resolvedUrl
            username = $resolvedUser
            password_protected = Protect-Password $plainPassword
            schema = $Schema.ToUpperInvariant()
            min_table_ratio = 0.95
        }
        Save-Config $config $ConfigFile
    }
    finally {
        $plainPassword = $null
    }
    Write-Host "DDL sync configuration saved with DPAPI protection: $ConfigFile" -ForegroundColor Green
}

function Read-ProtectedConfig {
    if (-not (Test-Path -LiteralPath $ConfigFile)) {
        throw "DDL sync config is missing: $ConfigFile"
    }
    $config = Get-Content -Raw -LiteralPath $ConfigFile -Encoding UTF8 | ConvertFrom-Json
    foreach ($property in @('project_root', 'knowledge_repo_root', 'jdbc_driver', 'jdbc_url', 'username',
            'password_protected', 'schema', 'min_table_ratio')) {
        if (-not $config.PSObject.Properties[$property] -or -not $config.$property) {
            throw "DDL sync config property is missing: $property"
        }
    }
    if ([string]$config.jdbc_url -notmatch '^jdbc:oracle:thin:@') {
        throw 'Configured JDBC URL is not an Oracle thin URL.'
    }
    $config | Add-Member -NotePropertyName password_plain -NotePropertyValue (
        Unprotect-Password ([string]$config.password_protected)
    ) -Force
    return $config
}

function Normalize-GeneratedText([string]$Content) {
    return (($Content -replace "`r`n", "`n").TrimEnd() + "`n")
}

function Get-TextHash([string]$Content) {
    $bytes = [Text.Encoding]::UTF8.GetBytes((Normalize-GeneratedText $Content))
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Get-PreviousTableCount([string]$Baseline) {
    $match = [regex]::Match($Baseline, 'DDL-SNAPSHOT-TABLE-COUNT:\s*(\d+)')
    if ($match.Success) { return [int]$match.Groups[1].Value }
    $match = [regex]::Match($Baseline, '表数量：\*\*(\d+)\*\*')
    if ($match.Success) { return [int]$match.Groups[1].Value }
    $match = [regex]::Match($Baseline, 'total\s+(\d+)\)')
    if ($match.Success) { return [int]$match.Groups[1].Value }
    throw 'Cannot determine previous DDL table count.'
}

function Get-GeneratedRegion([string]$Baseline) {
    $start = $Baseline.IndexOf($GeneratedStart, [StringComparison]::Ordinal)
    if ($start -ge 0) {
        $contentStart = $start + $GeneratedStart.Length
        $end = $Baseline.IndexOf($GeneratedEnd, $contentStart, [StringComparison]::Ordinal)
        if ($end -lt 0) { throw 'DDL baseline generated region has no end marker.' }
        return $Baseline.Substring($contentStart, $end - $contentStart).Trim()
    }
    $match = [regex]::Match($Baseline, '(?m)^## table list')
    if (-not $match.Success) { throw 'Legacy DDL generated region was not found.' }
    return $Baseline.Substring($match.Index).Trim()
}

function Test-Snapshot([string]$Content, [int]$PreviousCount, [double]$MinimumRatio, [bool]$ShrinkAllowed) {
    $countMatch = [regex]::Match($Content, 'DDL-SNAPSHOT-TABLE-COUNT:\s*(\d+)')
    if (-not $countMatch.Success) { throw 'Candidate snapshot is missing its table-count marker.' }
    $declaredCount = [int]$countMatch.Groups[1].Value
    $headings = [regex]::Matches($Content, '(?m)^## (?!table list)(.+?)\s*$')
    if ($declaredCount -lt 1 -or $headings.Count -ne $declaredCount) {
        throw "Candidate table count mismatch: declared=$declaredCount headings=$($headings.Count)"
    }
    if ($Content -notmatch '(?m)^\s*CREATE TABLE\s+') {
        throw 'Candidate snapshot contains no CREATE TABLE statement.'
    }
    $minimum = [Math]::Floor($PreviousCount * $MinimumRatio)
    if (-not $ShrinkAllowed -and $declaredCount -lt $minimum) {
        throw "Candidate table count $declaredCount is below safety floor $minimum."
    }
    return [pscustomobject]@{ table_count = $declaredCount; sha256 = Get-TextHash $Content }
}

function Merge-Baseline([string]$Baseline, [string]$Generated, [int]$TableCount) {
    $newBlock = $GeneratedStart + "`n" + (Normalize-GeneratedText $Generated) + $GeneratedEnd
    $start = $Baseline.IndexOf($GeneratedStart, [StringComparison]::Ordinal)
    if ($start -ge 0) {
        $contentStart = $start + $GeneratedStart.Length
        $end = $Baseline.IndexOf($GeneratedEnd, $contentStart, [StringComparison]::Ordinal)
        if ($end -lt 0) { throw 'DDL baseline generated region has no end marker.' }
        $tail = $end + $GeneratedEnd.Length
        $merged = $Baseline.Substring(0, $start) + $newBlock + $Baseline.Substring($tail)
    }
    else {
        $match = [regex]::Match($Baseline, '(?m)^## table list')
        if (-not $match.Success) { throw 'Legacy DDL generated region was not found.' }
        $merged = $Baseline.Substring(0, $match.Index).TrimEnd() + "`n`n" + $newBlock + "`n"
    }
    $merged = [regex]::Replace($merged, '表数量：\*\*\d+\*\*', "表数量：**$TableCount**")
    $merged = [regex]::Replace($merged, '生成日期：\d{4}-\d{2}-\d{2}', '生成日期：' + (Get-Date -Format 'yyyy-MM-dd'))
    return Normalize-GeneratedText $merged
}

function Write-AtomicFile([string]$Target, [string]$Content) {
    $directory = Split-Path -Parent $Target
    $temporary = Join-Path $directory ((Split-Path -Leaf $Target) + ".tmp-$PID")
    $backup = Join-Path $directory ((Split-Path -Leaf $Target) + ".backup-$PID")
    [IO.File]::WriteAllText($temporary, $Content, $Utf8NoBom)
    if (Test-Path -LiteralPath $Target) {
        [IO.File]::Replace($temporary, $Target, $backup)
        return $backup
    }
    Move-Item -LiteralPath $temporary -Destination $Target
    return $null
}

function Restore-AtomicFile([string]$Target, [string]$Backup) {
    if ($Backup -and (Test-Path -LiteralPath $Backup)) {
        [IO.File]::Replace($Backup, $Target, $null)
    }
}

function Invoke-OracleSnapshot($Config, [string]$Output) {
    $java = Get-Command java -ErrorAction SilentlyContinue
    if (-not $java) { throw 'Java executable was not found.' }
    if (-not (Test-Path -LiteralPath $Config.jdbc_driver)) { throw 'Oracle JDBC driver was not found.' }
    $source = Join-Path $PSScriptRoot 'OracleDdlSnapshot.java'
    $oldUrl = $env:YOOONI_DDL_JDBC_URL
    $oldUser = $env:YOOONI_DDL_USERNAME
    $oldPassword = $env:YOOONI_DDL_PASSWORD
    try {
        $env:YOOONI_DDL_JDBC_URL = [string]$Config.jdbc_url
        $env:YOOONI_DDL_USERNAME = [string]$Config.username
        $env:YOOONI_DDL_PASSWORD = [string]$Config.password_plain
        & $java.Source --class-path ([string]$Config.jdbc_driver) $source $Output ([string]$Config.schema)
        if ($LASTEXITCODE -ne 0) { throw "Oracle DDL exporter failed with exit code $LASTEXITCODE." }
    }
    finally {
        $env:YOOONI_DDL_JDBC_URL = $oldUrl
        $env:YOOONI_DDL_USERNAME = $oldUser
        $env:YOOONI_DDL_PASSWORD = $oldPassword
        $Config.password_plain = $null
    }
}

function Assert-SafeTemporaryDirectory([string]$Directory) {
    $resolved = [IO.Path]::GetFullPath($Directory)
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Split-Path -Leaf $resolved).StartsWith('yoooni-ddl-sync-')) {
        throw "Unsafe temporary directory: $resolved"
    }
}

function Invoke-SelfTest {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('yoooni-ddl-sync-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $root | Out-Null
    try {
        $secret = 'ddl-self-test-secret'
        if ((Unprotect-Password (Protect-Password $secret)) -ne $secret) { throw 'DPAPI round-trip failed.' }
        $legacy = @'
# DDL baseline

> 表数量：**2**｜ 生成日期：2026-01-01

人工语义保留。

## table list (real dump, alpha, total 2)

- `A`
- `B`

## A
```sql
CREATE TABLE A (ID NUMBER);
```

## B
```sql
CREATE TABLE B (ID NUMBER);
```
'@
        $candidate = @'
<!-- DDL-SNAPSHOT-TABLE-COUNT: 2 -->

## table list (real dump, alpha, total 2)

- `A`
- `B`

## A
```sql
CREATE TABLE A (ID NUMBER);
```

## B
```sql
CREATE TABLE B (ID NUMBER, CODE VARCHAR2(20));
```
'@
        $info = Test-Snapshot $candidate 2 0.95 $false
        if ($info.table_count -ne 2) { throw 'Snapshot count validation failed.' }
        $merged = Merge-Baseline $legacy $candidate 2
        if ($merged -notmatch '人工语义保留' -or $merged -notmatch [regex]::Escape($GeneratedStart)) {
            throw 'Baseline merge did not preserve the curated region.'
        }
        $target = Join-Path $root 'baseline.md'
        [IO.File]::WriteAllText($target, 'old', $Utf8NoBom)
        $backup = Write-AtomicFile $target $merged
        if ((Get-Content -Raw -LiteralPath $target) -notmatch 'CODE VARCHAR2') { throw 'Atomic publish failed.' }
        if ($backup -and (Test-Path -LiteralPath $backup)) { Remove-Item -LiteralPath $backup -Force }
        $shrunk = @'
<!-- DDL-SNAPSHOT-TABLE-COUNT: 1 -->

## table list (real dump, alpha, total 1)

- `A`

## A
```sql
CREATE TABLE A (ID NUMBER);
```
'@
        try {
            $null = Test-Snapshot $shrunk 10 0.95 $false
            throw 'Shrink safety gate did not fail.'
        }
        catch {
            if ($_.Exception.Message -eq 'Shrink safety gate did not fail.') { throw }
        }
        Write-Host 'DDL sync self-test passed.' -ForegroundColor Green
    }
    finally {
        Assert-SafeTemporaryDirectory $root
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
}

if ($Mode -eq 'SelfTest') { Invoke-SelfTest; exit 0 }
if ($Mode -eq 'SetCredential') {
    try { Initialize-Credential; exit 0 } catch { Write-Error $_.Exception.Message; exit 2 }
}
if ($Mode -eq 'Status') {
    if (-not (Test-Path -LiteralPath $ConfigFile)) { Write-Host 'DDL sync is not configured.'; exit 2 }
    $statusConfig = Get-Content -Raw -LiteralPath $ConfigFile -Encoding UTF8 | ConvertFrom-Json
    Write-Host "DDL sync configured: schema=$($statusConfig.schema) knowledge=$($statusConfig.knowledge_repo_root)"
    exit 0
}

$mutex = New-Object Threading.Mutex($false, $MutexName)
if (-not $mutex.WaitOne(0)) { Write-Error 'Another DDL sync is already running.'; exit 11 }
$tempDirectory = $null
try {
    try { $config = Read-ProtectedConfig } catch { Write-Error $_.Exception.Message; exit 2 }
    $knowledgeRoot = [IO.Path]::GetFullPath([string]$config.knowledge_repo_root)
    $baseline = Join-Path $knowledgeRoot 'knowledge\yoooni\impl\ddl-baseline.md'
    $metadata = Join-Path $knowledgeRoot 'knowledge\yoooni\impl\ddl-baseline.meta.json'
    if (-not (Test-Path -LiteralPath $baseline)) { Write-Error "DDL baseline not found: $baseline"; exit 3 }
    $tempDirectory = Join-Path ([IO.Path]::GetTempPath()) ('yoooni-ddl-sync-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tempDirectory | Out-Null
    $candidatePath = Join-Path $tempDirectory 'candidate.md'
    try { Invoke-OracleSnapshot $config $candidatePath } catch { Write-Error $_.Exception.Message; exit 4 }
    $existing = Get-Content -Raw -LiteralPath $baseline -Encoding UTF8
    $candidate = Get-Content -Raw -LiteralPath $candidatePath -Encoding UTF8
    try {
        $previousCount = Get-PreviousTableCount $existing
        $info = Test-Snapshot $candidate $previousCount ([double]$config.min_table_ratio) $AllowShrink.IsPresent
        $existingHash = Get-TextHash (Get-GeneratedRegion $existing)
    }
    catch { Write-Error $_.Exception.Message; exit 5 }
    if ($existingHash -eq $info.sha256) {
        Write-Host "DDL snapshot unchanged: tables=$($info.table_count) sha256=$($info.sha256)" -ForegroundColor Green
        exit 0
    }
    if ($Mode -eq 'Check') {
        Write-Host "DDL drift detected: old=$existingHash new=$($info.sha256) tables=$($info.table_count)" -ForegroundColor Yellow
        exit 10
    }
    $merged = Merge-Baseline $existing $candidate $info.table_count
    $metaObject = [ordered]@{
        schema_version = 1
        schema = ([string]$config.schema).ToUpperInvariant()
        generated_at = [DateTime]::UtcNow.ToString('o')
        table_count = $info.table_count
        sha256 = $info.sha256
        source = 'Oracle DBMS_METADATA'
    }
    $baselineBackup = $null
    $metadataBackup = $null
    $metadataExisted = Test-Path -LiteralPath $metadata
    try {
        $baselineBackup = Write-AtomicFile $baseline $merged
        $metadataBackup = Write-AtomicFile $metadata (($metaObject | ConvertTo-Json -Depth 4) + "`n")
        Push-Location $knowledgeRoot
        try {
            & node 'scripts\knowledge-health.mjs'
            if ($LASTEXITCODE -ne 0) { throw 'Knowledge health check failed after DDL publish.' }
        }
        finally { Pop-Location }
    }
    catch {
        if ($metadataExisted) {
            Restore-AtomicFile $metadata $metadataBackup
        }
        elseif (Test-Path -LiteralPath $metadata) {
            Remove-Item -LiteralPath $metadata -Force -ErrorAction SilentlyContinue
        }
        Restore-AtomicFile $baseline $baselineBackup
        Write-Error $_.Exception.Message
        exit 5
    }
    finally {
        foreach ($backup in @($baselineBackup, $metadataBackup)) {
            if ($backup -and (Test-Path -LiteralPath $backup)) {
                Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Write-Host "DDL baseline updated: tables=$($info.table_count) sha256=$($info.sha256)" -ForegroundColor Green
    Write-Host "Review changes in: $knowledgeRoot"
    exit 0
}
finally {
    if ($tempDirectory) {
        Assert-SafeTemporaryDirectory $tempDirectory
        if (Test-Path -LiteralPath $tempDirectory) {
            Remove-Item -LiteralPath $tempDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $mutex.ReleaseMutex()
    $mutex.Dispose()
}
