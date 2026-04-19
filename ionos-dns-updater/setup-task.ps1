#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Registers the IONOS DDNS updater as a Windows Scheduled Task.

.DESCRIPTION
    Run this script once as Administrator to set up the Task Scheduler job.
    After setup, ionos-ddns.ps1 runs automatically:
      - On every system startup
      - Every hour while the system is running

.NOTES
    Must be run as Administrator.
    Both setup-task.ps1 and ionos-ddns.ps1 must be in the same folder.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ==============================================================================
# CONFIGURATION
# ==============================================================================

# Full path to the DDNS script (must match where you placed ionos-ddns.ps1)
$ScriptPath = "C:\DNS\ionos-ddns.ps1"
$TaskName   = "IONOS-DDNS-Updater"

# ==============================================================================

if (-not (Test-Path $ScriptPath)) {
    Write-Error "ionos-ddns.ps1 not found at: $ScriptPath"
    exit 1
}

# Remove existing task if present
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Existing task removed."
}

# Action: run PowerShell silently, no window
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$ScriptPath`""

# Triggers: at system startup AND every hour
$triggerStartup = New-ScheduledTaskTrigger -AtStartup
$triggerHourly  = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 1) -Once -At (Get-Date)

# Settings: run in background, start as soon as possible if a run was missed
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances IgnoreNew `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable

# Run as SYSTEM - no user login required, always available
$principal = New-ScheduledTaskPrincipal `
    -UserId "SYSTEM" `
    -LogonType ServiceAccount `
    -RunLevel Highest

# Register the task
Register-ScheduledTask `
    -TaskName   $TaskName `
    -TaskPath   "\Custom\" `
    -Action     $action `
    -Trigger    $triggerStartup, $triggerHourly `
    -Settings   $settings `
    -Principal  $principal `
    -Description "Updates IONOS DNS A-Record with current public IP. Runs at startup and every hour." | Out-Null

Write-Host ""
Write-Host "Task '$TaskName' successfully registered!" -ForegroundColor Green
Write-Host "  Location in Task Scheduler: \Custom\$TaskName"
Write-Host "  Triggers: at system startup + every hour"
Write-Host "  Runs as: SYSTEM (no login required)"
Write-Host ""
Write-Host "Running first test now..."
Start-ScheduledTask -TaskPath "\Custom\" -TaskName $TaskName
Start-Sleep -Seconds 5

$log = "C:\DNS\ionos-ddns.log"
if (Test-Path $log) {
    Write-Host ""
    Write-Host "--- Log output ---"
    Get-Content $log | Select-Object -Last 10
} else {
    Write-Host "(No log entry yet - IP may already be up to date)"
}
