<#
.SYNOPSIS
  Registers and manages the current-user weekly Yoooni DDL sync task.
#>
param(
    [ValidateSet('Register', 'Status', 'Run', 'Disable', 'Enable', 'Remove')]
    [string]$Action = 'Status',
    [ValidateSet('SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT')]
    [string]$Day = 'SUN',
    [ValidatePattern('^([01]\d|2[0-3]):[0-5]\d$')]
    [string]$At = '03:00'
)

$ErrorActionPreference = 'Stop'
$taskName = 'YoooniDdlSnapshotSync'
$stateRoot = Join-Path $env:USERPROFILE '.kai-toolbox'
$launcher = Join-Path $stateRoot 'run-ddl-sync.ps1'

function Install-StableLauncher {
    New-Item -ItemType Directory -Force -Path $stateRoot | Out-Null
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'run-ddl-sync.ps1') -Destination $launcher -Force
    $fallback = Join-Path $PSScriptRoot 'sync-yoooni-ddl.ps1'
    [IO.File]::WriteAllText(
        (Join-Path $stateRoot 'ddl-sync-script.path'),
        $fallback,
        (New-Object Text.UTF8Encoding($false))
    )
}

switch ($Action) {
    'Register' {
        Install-StableLauncher
        $dayMap = @{ SUN = 'Sunday'; MON = 'Monday'; TUE = 'Tuesday'; WED = 'Wednesday'; THU = 'Thursday'; FRI = 'Friday'; SAT = 'Saturday' }
        $time = [DateTime]::ParseExact($At, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)
        $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek $dayMap[$Day] -At $time
        $taskAction = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
            '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $launcher + '"'
        )
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $principal = New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 2)
        Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $trigger `
            -Principal $principal -Settings $settings -Force | Out-Null
        Write-Host "Registered ${taskName}: weekly $Day $At as $identity" -ForegroundColor Green
    }
    'Status' {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if (-not $task) { Write-Host "$taskName is not registered."; exit 2 }
        $info = Get-ScheduledTaskInfo -TaskName $taskName
        Write-Host "Task=$taskName State=$($task.State) NextRun=$($info.NextRunTime) LastResult=$($info.LastTaskResult)"
    }
    'Run' { Start-ScheduledTask -TaskName $taskName; Write-Host "Started $taskName." }
    'Disable' { Disable-ScheduledTask -TaskName $taskName | Out-Null; Write-Host "Disabled $taskName." }
    'Enable' { Enable-ScheduledTask -TaskName $taskName | Out-Null; Write-Host "Enabled $taskName." }
    'Remove' {
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
        Write-Host "Removed $taskName. Local config and logs were preserved."
    }
}
