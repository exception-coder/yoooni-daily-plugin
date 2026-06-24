# Run this PowerShell script as Administrator.
# 一键修复访问内网共享 \\IT01 时弹"输入网络凭据"的问题（SMB Guest 访客访问）。
$ErrorActionPreference = "Continue"

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Please right-click PowerShell and choose 'Run as administrator', then run this script again." -ForegroundColor Red
    exit 1
}

$regFile = Join-Path $PSScriptRoot "fix_smb_guest_it01.reg"
Write-Host "Importing registry file: $regFile"
reg import $regFile

Write-Host "`nApplying SMB client configuration..."
Set-SmbClientConfiguration -EnableInsecureGuestLogons $true -RequireSecuritySignature $false -EnableSecuritySignature $false -Force

Write-Host "`nRestarting Workstation service so settings are re-read..."
Restart-Service LanmanWorkstation -Force

Write-Host "`nClearing any existing IT01 SMB session..."
& net.exe use "\\IT01\IPC$" /delete /y 2>$null | Out-Null
& net.exe use "\\192.168.9.253\IPC$" /delete /y 2>$null | Out-Null

Write-Host "`nTesting IT01 Guest connection..."
& net.exe use "\\IT01\IPC$" "" "/user:guest"

Write-Host "`nListing IT01 shares..."
& net.exe view "\\IT01"

Write-Host "`nCurrent SMB client settings:"
Get-SmbClientConfiguration | Select-Object EnableInsecureGuestLogons, RequireSecuritySignature, EnableSecuritySignature | Format-List

Write-Host "`nDone. Try opening \\IT01 or \\IT01\版本更新 in File Explorer."
