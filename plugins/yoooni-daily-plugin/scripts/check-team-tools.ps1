<#
.SYNOPSIS
  Check whether the company Claude Code tool suite is installed and active.

.DESCRIPTION
  This script is read-only. It checks local dependencies, Claude Code plugins,
  MCP server connectivity, plugin cache manifests, and the auto-update task.
#>
param(
    [string]$WorkspaceDir
)

$ErrorActionPreference = 'Continue'
$script:FailedChecks = 0
$script:WarnChecks = 0

$ExpectedPlugins = @(
    'yoooni-daily-plugin@yoooni-daily-plugin',
    'team-standards@team-standards',
    'project-coding-profiles@project-coding-profiles'
)
$ExpectedMcpServers = @('domain-knowledge', 'cross-topology')
$AutoUpdateTaskName = 'YoooniTeamToolsAutoUpdate'
$InstalledPluginsFile = Join-Path $env:USERPROFILE '.claude\plugins\installed_plugins.json'
$WorkspaceConfigFile = Join-Path $env:USERPROFILE '.kai-toolbox\workspace.path'

function Write-Header($Text) {
    Write-Host ''
    Write-Host $Text -ForegroundColor Cyan
    Write-Host ('=' * $Text.Length) -ForegroundColor Cyan
}

function Write-Check($Status, $Text, $Detail = $null) {
    $color = 'Gray'
    if ($Status -eq 'OK') { $color = 'Green' }
    elseif ($Status -eq 'WARN') { $color = 'Yellow'; $script:WarnChecks++ }
    elseif ($Status -eq 'FAIL') { $color = 'Red'; $script:FailedChecks++ }

    Write-Host ("[{0}] {1}" -f $Status, $Text) -ForegroundColor $color
    if ($Detail) {
        Write-Host ("     {0}" -f $Detail) -ForegroundColor DarkGray
    }
}

function Test-Cmd($Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Invoke-TextCommand([scriptblock]$Command) {
    try {
        return (& $Command 2>&1 | Out-String)
    }
    catch {
        return $_.Exception.Message
    }
}

function Resolve-WorkspaceDir {
    if ($WorkspaceDir) { return $WorkspaceDir }
    if ($env:YOOONI_WORKSPACE_DIR) { return $env:YOOONI_WORKSPACE_DIR }
    if (Test-Path -LiteralPath $WorkspaceConfigFile) {
        $saved = ((Get-Content -LiteralPath $WorkspaceConfigFile -Raw -ErrorAction SilentlyContinue) -replace "^\xEF\xBB\xBF", "").Trim()
        if ($saved) { return $saved }
    }

    foreach ($drive in @('D:', 'C:', 'E:', 'F:')) {
        $candidate = Join-Path ("{0}\Users\{1}" -f $drive, $env:USERNAME) 'myWork'
        if (Test-Path -LiteralPath (Join-Path $candidate 'yoooni-daily-plugin')) {
            return $candidate
        }
    }

    return (Join-Path $env:USERPROFILE 'myWork')
}

function Read-InstalledPlugins {
    if (-not (Test-Path -LiteralPath $InstalledPluginsFile)) {
        Write-Check 'FAIL' 'Claude Code installed_plugins.json not found' $InstalledPluginsFile
        return $null
    }

    try {
        $json = Get-Content -LiteralPath $InstalledPluginsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        Write-Check 'OK' 'Claude Code plugin install record exists' $InstalledPluginsFile
        return $json
    }
    catch {
        Write-Check 'FAIL' 'Claude Code installed_plugins.json is not valid JSON' $_.Exception.Message
        return $null
    }
}

function Test-PluginRecord($InstalledPlugins) {
    if (-not $InstalledPlugins -or -not $InstalledPlugins.plugins) { return }

    $pluginProperties = $InstalledPlugins.plugins.PSObject.Properties
    foreach ($pluginRef in $ExpectedPlugins) {
        $entry = $pluginProperties | Where-Object { $_.Name -eq $pluginRef } | Select-Object -First 1
        if (-not $entry) {
            Write-Check 'FAIL' "Plugin install record missing: $pluginRef"
            continue
        }

        $instances = @($entry.Value)
        $latest = $instances | Select-Object -First 1
        if ($latest.installPath -and (Test-Path -LiteralPath $latest.installPath)) {
            $manifest = Join-Path $latest.installPath '.claude-plugin\plugin.json'
            if (Test-Path -LiteralPath $manifest) {
                Write-Check 'OK' "Plugin cache present: $pluginRef" ("version {0}" -f $latest.version)
            }
            else {
                Write-Check 'WARN' "Plugin cache exists but manifest missing: $pluginRef" $latest.installPath
            }
        }
        else {
            Write-Check 'FAIL' "Plugin cache path missing: $pluginRef" $latest.installPath
        }
    }
}

function Test-PluginCli {
    if (-not (Test-Cmd claude)) {
        Write-Check 'FAIL' 'Claude Code CLI not found in PATH' 'Install with: npm install -g @anthropic-ai/claude-code'
        return
    }

    $version = Invoke-TextCommand { claude --version }
    Write-Check 'OK' 'Claude Code CLI found' $version.Trim()

    $pluginList = Invoke-TextCommand { claude plugin list }
    foreach ($pluginRef in $ExpectedPlugins) {
        $pattern = "(?s)>\s*$([regex]::Escape($pluginRef)).*?Status:\s*.*enabled"
        if ($pluginList -match $pattern) {
            Write-Check 'OK' "Plugin enabled in Claude Code: $pluginRef"
        }
        elseif ($pluginList -match [regex]::Escape($pluginRef)) {
            Write-Check 'FAIL' "Plugin installed but not enabled: $pluginRef" 'Open /plugin, enable it, then run /reload-plugins.'
        }
        else {
            Write-Check 'FAIL' "Plugin not listed by Claude Code: $pluginRef" 'Re-run team-tools-install.cmd.'
        }
    }
}

function Test-McpCli {
    if (-not (Test-Cmd claude)) { return }

    $mcpList = Invoke-TextCommand { claude mcp list }
    foreach ($serverName in $ExpectedMcpServers) {
        $connectedPattern = "(?m)^\s*$([regex]::Escape($serverName)):\s+.*\bConnected\b"
        if ($mcpList -match $connectedPattern) {
            Write-Check 'OK' "MCP connected: $serverName"
        }
        elseif ($mcpList -match "(?m)^\s*$([regex]::Escape($serverName)):\s+(.*)$") {
            Write-Check 'FAIL' "MCP registered but not connected: $serverName" $Matches[1].Trim()
        }
        else {
            Write-Check 'FAIL' "MCP not registered: $serverName" 'Re-run team-tools-install.cmd.'
        }
    }
}

function Test-WorkspaceRepos($ResolvedWorkspaceDir) {
    Write-Check 'OK' 'Workspace directory resolved' $ResolvedWorkspaceDir

    $repoNames = @(
        'yoooni-daily-plugin',
        'project-coding-profiles',
        'project-domain-knowledge',
        'cross-project-topology'
    )

    foreach ($repoName in $repoNames) {
        $repoPath = Join-Path $ResolvedWorkspaceDir $repoName
        if (Test-Path -LiteralPath (Join-Path $repoPath '.git')) {
            Write-Check 'OK' "Source repo exists: $repoName" $repoPath
        }
        else {
            Write-Check 'WARN' "Source repo not found or not a git repo: $repoName" $repoPath
        }
    }
}

function Test-AutoUpdateTask {
    $taskOutput = Invoke-TextCommand { schtasks /Query /TN $AutoUpdateTaskName /FO LIST }
    if ($LASTEXITCODE -eq 0 -and $taskOutput -match [regex]::Escape($AutoUpdateTaskName)) {
        $statusLine = ($taskOutput -split "`r?`n") | Where-Object { $_ -match '^Status:' } | Select-Object -First 1
        Write-Check 'OK' 'Auto-update task exists' $statusLine
    }
    else {
        Write-Check 'WARN' 'Auto-update task not found' 'Run team-tools-install.cmd again, or scripts\register-autoupdate-task.ps1.'
    }
}

function Get-InstalledPluginMap {
    $map = @{}
    if (-not (Test-Path -LiteralPath $InstalledPluginsFile)) { return $map }

    try {
        $json = Get-Content -LiteralPath $InstalledPluginsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $json.plugins) { return $map }

        foreach ($property in $json.plugins.PSObject.Properties) {
            $instances = @($property.Value)
            $latest = $instances | Select-Object -First 1
            $map[$property.Name] = $latest
        }
    }
    catch {
        return $map
    }

    return $map
}

function Get-PluginCliMap {
    $map = @{}
    if (-not (Test-Cmd claude)) { return $map }

    $pluginList = Invoke-TextCommand { claude plugin list }
    foreach ($pluginRef in $ExpectedPlugins) {
        $escaped = [regex]::Escape($pluginRef)
        $blockPattern = "(?s)>\s*$escaped\s*(.*?)(?=\r?\n\s*>\s|\z)"
        if ($pluginList -match $blockPattern) {
            $block = $Matches[1]
            $version = '-'
            $status = 'unknown'
            $scope = '-'
            if ($block -match 'Version:\s*(.+)') { $version = $Matches[1].Trim() }
            if ($block -match 'Status:\s*(.+)') { $status = $Matches[1].Trim() }
            if ($block -match 'Scope:\s*(.+)') { $scope = $Matches[1].Trim() }

            $map[$pluginRef] = [pscustomobject]@{
                Version = $version
                Status = $status
                Scope = $scope
            }
        }
    }

    return $map
}

function Get-McpCliMap {
    $map = @{}
    if (-not (Test-Cmd claude)) { return $map }

    $mcpList = Invoke-TextCommand { claude mcp list }
    foreach ($serverName in $ExpectedMcpServers) {
        $linePattern = "(?m)^\s*$([regex]::Escape($serverName)):\s+(.*)$"
        if ($mcpList -match $linePattern) {
            $line = $Matches[1].Trim()
            $status = 'unknown'
            if ($line -match '\bConnected\b') { $status = 'connected' }
            elseif ($line -match 'Needs authentication') { $status = 'needs auth' }
            elseif ($line -match 'failed|error|disconnected') { $status = 'failed' }

            $map[$serverName] = [pscustomobject]@{
                Status = $status
                Detail = $line
            }
        }
    }

    return $map
}

function Write-FinalSummary {
    Write-Header 'Final Summary'

    $installedPluginMap = Get-InstalledPluginMap
    $pluginCliMap = Get-PluginCliMap
    $pluginRows = foreach ($pluginRef in $ExpectedPlugins) {
        $install = $installedPluginMap[$pluginRef]
        $cli = $pluginCliMap[$pluginRef]

        $version = '-'
        $scope = '-'
        $cache = 'missing'
        $enabled = 'not listed'
        $result = 'FAIL'
        $action = 'Run team-tools-install.cmd'

        if ($install) {
            $version = if ($install.version) { $install.version } else { 'unknown' }
            $scope = if ($install.scope) { $install.scope } else { '-' }
            if ($install.installPath -and (Test-Path -LiteralPath $install.installPath)) {
                $manifest = Join-Path $install.installPath '.claude-plugin\plugin.json'
                $cache = if (Test-Path -LiteralPath $manifest) { 'ok' } else { 'manifest missing' }
            }
        }

        if ($cli) {
            if ($cli.Version -and $cli.Version -ne '-' -and $version -eq '-') { $version = $cli.Version }
            if ($cli.Scope -and $cli.Scope -ne '-') { $scope = $cli.Scope }
            $enabled = if ($cli.Status -match 'enabled') { 'enabled' } else { $cli.Status }
        }

        if ($install -and $cache -eq 'ok' -and $enabled -eq 'enabled') {
            $result = 'OK'
            $action = 'Ready'
        }
        elseif ($install -and $enabled -ne 'enabled') {
            $action = 'Enable in /plugin, then run /reload-plugins'
        }
        elseif ($install -and $cache -ne 'ok') {
            $action = 'Re-run installer to refresh plugin cache'
        }

        [pscustomobject]@{
            Plugin = $pluginRef
            Version = $version
            Scope = $scope
            Cache = $cache
            'Claude CLI' = $enabled
            Result = $result
            Action = $action
        }
    }

    Write-Host ''
    Write-Host 'Plugin installation table:' -ForegroundColor Cyan
    $pluginRows | Format-Table -AutoSize | Out-String | Write-Host

    $mcpCliMap = Get-McpCliMap
    $mcpRows = foreach ($serverName in $ExpectedMcpServers) {
        $mcp = $mcpCliMap[$serverName]
        if ($mcp -and $mcp.Status -eq 'connected') {
            [pscustomobject]@{
                MCP = $serverName
                Status = 'connected'
                Result = 'OK'
                Action = 'Ready'
            }
        }
        elseif ($mcp) {
            [pscustomobject]@{
                MCP = $serverName
                Status = $mcp.Status
                Result = 'FAIL'
                Action = 'Open /mcp for details, then re-run installer if needed'
            }
        }
        else {
            [pscustomobject]@{
                MCP = $serverName
                Status = 'not registered'
                Result = 'FAIL'
                Action = 'Run team-tools-install.cmd'
            }
        }
    }

    Write-Host 'MCP connection table:' -ForegroundColor Cyan
    $mcpRows | Format-Table -AutoSize | Out-String | Write-Host

    $taskOutput = Invoke-TextCommand { schtasks /Query /TN $AutoUpdateTaskName /FO LIST }
    $taskStatus = 'missing'
    if ($LASTEXITCODE -eq 0 -and $taskOutput -match [regex]::Escape($AutoUpdateTaskName)) {
        $taskStatus = 'exists'
        if ($taskOutput -match '(?m)^Status:\s*(.+)$') {
            $taskStatus = $Matches[1].Trim()
        }
    }

    Write-Host ("Auto-update task: {0} ({1})" -f $AutoUpdateTaskName, $taskStatus) -ForegroundColor Cyan
}

Write-Host '==================================================' -ForegroundColor Cyan
Write-Host ' Company Team Tools - One-click Check' -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan

Write-Header '1. Dependencies'
foreach ($cmd in @('git', 'node', 'npm', 'claude')) {
    if (Test-Cmd $cmd) {
        $version = ''
        if ($cmd -eq 'git') { $version = (Invoke-TextCommand { git --version }).Trim() }
        elseif ($cmd -eq 'node') { $version = (Invoke-TextCommand { node --version }).Trim() }
        elseif ($cmd -eq 'npm') { $version = (Invoke-TextCommand { npm --version }).Trim() }
        elseif ($cmd -eq 'claude') { $version = (Invoke-TextCommand { claude --version }).Trim() }
        Write-Check 'OK' "$cmd is available" $version
    }
    else {
        $hint = switch ($cmd) {
            'git' { 'Install: https://git-scm.com/download/win' }
            'node' { 'Install Node.js LTS: https://nodejs.org/zh-cn' }
            'npm' { 'Reinstall Node.js LTS, npm is bundled with Node.' }
            'claude' { 'Install: npm install -g @anthropic-ai/claude-code' }
        }
        Write-Check 'FAIL' "$cmd is missing" $hint
    }
}

Write-Header '2. Local Files'
$resolvedWorkspaceDir = Resolve-WorkspaceDir
Test-WorkspaceRepos $resolvedWorkspaceDir
$installedPlugins = Read-InstalledPlugins
Test-PluginRecord $installedPlugins

Write-Header '3. Claude Code Plugins'
Test-PluginCli

Write-Header '4. MCP Servers'
Test-McpCli

Write-Header '5. Auto Update'
Test-AutoUpdateTask

Write-FinalSummary

Write-Header 'Result'
if ($script:FailedChecks -eq 0) {
    if ($script:WarnChecks -eq 0) {
        Write-Host '[PASS] Company team tools are installed and active.' -ForegroundColor Green
    }
    else {
        Write-Host ("[PASS WITH WARNINGS] No blocking failures, warnings: {0}" -f $script:WarnChecks) -ForegroundColor Yellow
    }
    Write-Host 'Friendly reminder: this machine looks ready. In Claude Code, run /reload-plugins or restart the session to confirm the current session has loaded the plugins.' -ForegroundColor Cyan
    exit 0
}

Write-Host ("[FAIL] Blocking failures: {0}; warnings: {1}" -f $script:FailedChecks, $script:WarnChecks) -ForegroundColor Red
Write-Host 'Suggested order: run team-tools-install.cmd -> restart Claude Code -> check /plugin Errors and /mcp details.' -ForegroundColor Yellow
exit 1
