$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot '..\check-team-tools.ps1'
. $scriptPath -FunctionsOnly

function Assert-Equal($Expected, $Actual, $Message) {
    if ($Expected -ne $Actual) {
        throw "$Message`nExpected: $Expected`nActual:   $Actual"
    }
}

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ("team-tools-cache-test-{0}" -f [guid]::NewGuid().ToString('N'))
try {
    foreach ($version in @('1.9.0', '1.10.0')) {
        $manifestDirectory = Join-Path $testRoot ("$version\.codex-plugin")
        New-Item -ItemType Directory -Force -Path $manifestDirectory | Out-Null
        @{ name = 'example'; version = $version } |
            ConvertTo-Json |
            Set-Content -LiteralPath (Join-Path $manifestDirectory 'plugin.json') -Encoding UTF8
    }

    Assert-Equal '1.10.0' (Get-LatestCodexCacheVersion $testRoot) 'Cache selection must use SemVer, not path ordering.'
    Assert-Equal 'current 1.10.0' (Get-CodexCacheState '1.10.0' '1.10.0') 'Matching source and cache versions must be current.'
    Assert-Equal 'stale 1.9.0; expected 1.10.0' (Get-CodexCacheState '1.10.0' '1.9.0') 'Older cache must be stale.'
    Assert-Equal 'missing' (Get-CodexCacheState '1.10.0' $null) 'Missing cache must be reported.'
    Assert-Equal 'version 1.10.0; source manifest missing' (Get-CodexCacheState $null '1.10.0') 'Missing source version must not be Ready.'

    Write-Host '[PASS] check-team-tools cache version tests'
}
finally {
    if ((Test-Path -LiteralPath $testRoot) -and $testRoot.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
