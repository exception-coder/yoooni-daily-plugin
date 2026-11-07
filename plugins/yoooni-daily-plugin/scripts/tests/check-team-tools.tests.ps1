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

    # 只加载更新器函数，避免测试触发真实拉取、安装或宿主配置写入。
    $updater = Join-Path $PSScriptRoot '..\update-team-tools.ps1'
    $tokens = $null; $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($updater, [ref]$tokens, [ref]$parseErrors)
    Assert-Equal 0 $parseErrors.Count 'Updater must parse in Windows PowerShell.'
    $functionNames = @('Escape-TomlString', 'Read-CodexConfigUtf8', 'Write-CodexConfigUtf8', 'New-CodexMcpBlock', 'Sync-CodexMcpConfig')
    $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $false) |
        Where-Object { $functionNames -contains $_.Name } |
        ForEach-Object { Invoke-Expression $_.Extent.Text }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $maxCodexConfigBytes = 16MB
    $codexRoot = Join-Path $testRoot 'codex'
    New-Item -ItemType Directory -Path $codexRoot -Force | Out-Null
    $configPath = Join-Path $codexRoot 'config.toml'
    $servers = [ordered]@{
        'cross-topology' = [pscustomobject]@{ command = 'node'; args = @('C:/tools/cross-project-topology/dist/server.js') }
    }

    $result = Sync-CodexMcpConfig $codexRoot $configPath $servers
    Assert-Equal $false (Test-Path -LiteralPath $configPath) 'Update must not create a missing MCP config.'
    Assert-Equal 'cross-topology' ($result.Skipped -join ',') 'Absent MCP must be skipped.'

    $otherConfig = "[mcp_servers.other]`n# 用户保留的配置`ncommand = `"other`"`n"
    [IO.File]::WriteAllText($configPath, $otherConfig, $utf8)
    $result = Sync-CodexMcpConfig $codexRoot $configPath $servers
    Assert-Equal $otherConfig ([IO.File]::ReadAllText($configPath)) 'Removed MCP must stay removed without changing other settings.'

    $disabledConfig = "[mcp_servers.cross-topology]`ncommand = `"node`"`nargs = [`"old/server.js`"]`nenabled = false # 用户停用`n`n$otherConfig"
    [IO.File]::WriteAllText($configPath, $disabledConfig, $utf8)
    $result = Sync-CodexMcpConfig $codexRoot $configPath $servers
    Assert-Equal $disabledConfig ([IO.File]::ReadAllText($configPath)) 'Disabled MCP must remain byte-for-byte unchanged.'
    Assert-Equal 0 $result.Updated.Count 'Disabled MCP must not be refreshed.'

    $enabledConfig = "[mcp_servers.cross-topology]`ncommand = `"node`"`nargs = [`"old/server.js`"]`n`n$otherConfig"
    [IO.File]::WriteAllText($configPath, $enabledConfig, $utf8)
    $result = Sync-CodexMcpConfig $codexRoot $configPath $servers
    Assert-Equal 'cross-topology' ($result.Updated -join ',') 'Existing enabled MCP must still migrate to the independent runtime.'
    $updatedConfig = [IO.File]::ReadAllText($configPath)
    Assert-Equal $true ($updatedConfig.Contains('C:/tools/cross-project-topology/dist/server.js')) 'Updated runtime path is missing.'
    Assert-Equal $true ($updatedConfig.Contains($otherConfig)) 'Other settings must be preserved during migration.'
    $result = Sync-CodexMcpConfig $codexRoot $configPath $servers
    Assert-Equal 0 $result.Updated.Count 'Repeated refresh must be idempotent.'
    Assert-Equal $updatedConfig ([IO.File]::ReadAllText($configPath)) 'Repeated refresh must not rewrite settings.'
    Write-Host '[PASS] Codex MCP removal, disablement, migration and repeat-update tests'
}
finally {
    if ((Test-Path -LiteralPath $testRoot) -and $testRoot.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase)) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force
    }
}
