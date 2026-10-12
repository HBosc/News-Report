<#
.SYNOPSIS
  Registers a Windows scheduled task that refreshes the news every day.
  Usage:  powershell -ExecutionPolicy Bypass -File .\register-daily-task.ps1 [-At 07:00]
  Remove: Unregister-ScheduledTask -TaskName "Daily Brief News Update" -Confirm:$false
#>
param([string]$At = '07:00')

$taskName = 'Daily Brief News Update'
$script = Join-Path $PSScriptRoot 'update-news.ps1'

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`"" `
    -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -Daily -At $At
# StartWhenAvailable: if the PC was off/asleep at the scheduled time, run as soon as it's back.
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -RunOnlyIfNetworkAvailable -ExecutionTimeLimit (New-TimeSpan -Minutes 15)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
    -Description 'Fetches politics, Brazil, tech, cybersecurity and gaming headlines for The Daily Brief.' -Force | Out-Null

Write-Host "Scheduled '$taskName' daily at $At."
