$ErrorActionPreference = 'Stop'
$helper = (Resolve-Path (Join-Path $PSScriptRoot '..\update-lock.ps1')).Path
. $helper

$name = 'Local\YoooniTeamToolsUpdateTest-' + [guid]::NewGuid().ToString('N')
$first = Enter-YoooniUpdateMutex -Name $name
if ($null -eq $first) { throw 'first mutex acquisition failed' }

function Invoke-MutexProbe([string]$MutexName, [bool]$ExpectAcquired, [bool]$Abandon = $false) {
  $escapedHelper = $helper.Replace("'", "''")
  $escapedName = $MutexName.Replace("'", "''")
  $body = "`$ProgressPreference = 'SilentlyContinue'; . '$escapedHelper'; `$m = Enter-YoooniUpdateMutex -Name '$escapedName'; "
  if ($Abandon) {
    $body += "if (`$null -eq `$m) { exit 21 }; [Environment]::Exit(0)"
  }
  elseif ($ExpectAcquired) {
    $body += "if (`$null -eq `$m) { exit 22 }; Exit-YoooniUpdateMutex `$m; exit 0"
  }
  else {
    $body += "if (`$null -ne `$m) { Exit-YoooniUpdateMutex `$m; exit 23 }; exit 0"
  }
  $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
  & powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded
  if ($LASTEXITCODE -ne 0) { throw "mutex probe failed with exit $LASTEXITCODE" }
}

try {
  Invoke-MutexProbe $name $false
}
finally {
  Exit-YoooniUpdateMutex $first
}

Invoke-MutexProbe $name $true
Invoke-MutexProbe $name $true $true
$recovered = Enter-YoooniUpdateMutex -Name $name
if ($null -eq $recovered) { throw 'abandoned mutex was not recovered' }
Exit-YoooniUpdateMutex $recovered
Write-Host 'update mutex tests passed'
