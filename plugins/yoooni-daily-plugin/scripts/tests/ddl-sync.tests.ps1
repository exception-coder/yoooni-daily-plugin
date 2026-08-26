$ErrorActionPreference = 'Stop'
$skillRoot = Resolve-Path (Join-Path $PSScriptRoot '..\..\skills\yoooni-ddl-sync')
$sync = Join-Path $skillRoot 'sync-yoooni-ddl.ps1'
$javaSource = Join-Path $skillRoot 'OracleDdlSnapshot.java'
$launcher = Join-Path $skillRoot 'run-ddl-sync.ps1'

& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $sync -Mode SelfTest
if ($LASTEXITCODE -ne 0) { throw "DDL sync self-test failed: exit $LASTEXITCODE" }

$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('yoooni-ddl-java-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
try {
    & javac.exe -encoding UTF-8 -d $testRoot $javaSource
    if ($LASTEXITCODE -ne 0) { throw "OracleDdlSnapshot.java compile failed: exit $LASTEXITCODE" }
    if (-not (Test-Path -LiteralPath (Join-Path $testRoot 'OracleDdlSnapshot.class'))) {
        throw 'OracleDdlSnapshot.class was not generated.'
    }

    $codexSkill = Join-Path $testRoot '.codex\plugins\cache\yoooni-daily-plugin\yoooni-daily-plugin\0.28.0\skills\yoooni-ddl-sync'
    $claudeSkill = Join-Path $testRoot '.claude\plugins\cache\yoooni-daily-plugin\yoooni-daily-plugin\0.29.0\skills\yoooni-ddl-sync'
    New-Item -ItemType Directory -Force -Path $codexSkill, $claudeSkill | Out-Null
    $fakeScript = 'Add-Content -LiteralPath $env:DDL_LAUNCHER_RESULT -Value $PSScriptRoot; exit 0'
    [IO.File]::WriteAllText((Join-Path $codexSkill 'sync-yoooni-ddl.ps1'), $fakeScript)
    [IO.File]::WriteAllText((Join-Path $claudeSkill 'sync-yoooni-ddl.ps1'), $fakeScript)
    $oldProfile = $env:USERPROFILE
    $oldResult = $env:DDL_LAUNCHER_RESULT
    $resultFile = Join-Path $testRoot 'launcher-result.txt'
    try {
        $env:USERPROFILE = $testRoot
        $env:DDL_LAUNCHER_RESULT = $resultFile
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $launcher
        if ($LASTEXITCODE -ne 0) { throw "DDL launcher test failed: exit $LASTEXITCODE" }
    }
    finally {
        $env:USERPROFILE = $oldProfile
        $env:DDL_LAUNCHER_RESULT = $oldResult
    }
    $launchedPath = Get-Content -Raw -LiteralPath $resultFile
    if ($launchedPath -notmatch [regex]::Escape('0.29.0')) {
        throw "DDL launcher did not select the newest cross-client cache: $launchedPath"
    }
}
finally {
    $resolved = [IO.Path]::GetFullPath($testRoot)
    $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if (-not $resolved.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Split-Path -Leaf $resolved).StartsWith('yoooni-ddl-java-test-')) {
        throw "Unsafe test cleanup path: $resolved"
    }
    if (Test-Path -LiteralPath $resolved) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}

Write-Host 'ddl-sync.tests.ps1 passed.' -ForegroundColor Green
