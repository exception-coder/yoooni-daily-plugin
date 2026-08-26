<#
.SYNOPSIS
  Stable launcher that resolves the newest installed Yoooni DDL sync script.
#>
$ErrorActionPreference = 'Continue'
$stateRoot = Join-Path $env:USERPROFILE '.kai-toolbox'
$logRoot = Join-Path $stateRoot 'logs\ddl-sync'
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null
$logFile = Join-Path $logRoot ((Get-Date -Format 'yyyyMMdd') + '.log')

function Write-LauncherLog([string]$Message) {
    Add-Content -LiteralPath $logFile -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message)
}

function Find-LatestScript([string]$CacheRoot) {
    if (-not (Test-Path -LiteralPath $CacheRoot)) { return $null }
    return Get-ChildItem -LiteralPath $CacheRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { Test-Path (Join-Path $_.FullName 'skills\yoooni-ddl-sync\sync-yoooni-ddl.ps1') } |
        ForEach-Object {
            $version = try { [version]($_.Name -replace '[^0-9.].*$', '') } catch { [version]'0.0.0' }
            [pscustomobject]@{
                Version = $version
                Path = Join-Path $_.FullName 'skills\yoooni-ddl-sync\sync-yoooni-ddl.ps1'
            }
        } |
        Sort-Object Version |
        Select-Object -Last 1
}

$targetCandidates = @(
    Find-LatestScript (Join-Path $env:USERPROFILE '.codex\plugins\cache\yoooni-daily-plugin\yoooni-daily-plugin')
    Find-LatestScript (Join-Path $env:USERPROFILE '.claude\plugins\cache\yoooni-daily-plugin\yoooni-daily-plugin')
) | Where-Object { $_ }
$target = $targetCandidates | Sort-Object Version | Select-Object -Last 1 | ForEach-Object { $_.Path }
if (-not $target) {
    $fallbackFile = Join-Path $stateRoot 'ddl-sync-script.path'
    if (Test-Path -LiteralPath $fallbackFile) {
        $fallback = (Get-Content -Raw -LiteralPath $fallbackFile).Trim()
        if (Test-Path -LiteralPath $fallback) { $target = $fallback }
    }
}
if (-not $target) {
    Write-LauncherLog 'sync-yoooni-ddl.ps1 was not found.'
    exit 3
}

Write-LauncherLog "starting $target"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $target -Mode Sync *>> $logFile
$exitCode = $LASTEXITCODE
Write-LauncherLog "completed exit=$exitCode"
Get-ChildItem -LiteralPath $logRoot -Filter '*.log' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Remove-Item -Force -ErrorAction SilentlyContinue
exit $exitCode
