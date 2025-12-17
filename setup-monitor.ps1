<#
.SYNOPSIS
    Sets up scheduled monitoring for GitHub Actions runners.

.DESCRIPTION
    Creates a Windows Task Scheduler task to run monitor-runners.ps1 periodically.
    The task runs every 5 minutes by default.

.PARAMETER IntervalMinutes
    How often to check runner status (in minutes). Default is 5.

.PARAMETER SlackWebhookUrl
    Optional Slack webhook URL. If not provided, will use SLACK_WEBHOOK_URL from .env file.

.EXAMPLE
    .\setup-monitor.ps1 -IntervalMinutes 5
#>

param(
    [int]$IntervalMinutes = 5,
    [string]$SlackWebhookUrl = ""
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== GitHub Actions Runner Monitor Setup ===" -ForegroundColor Cyan
Write-Host ""

# Get the full path to the monitor script
$MonitorScript = Join-Path $ScriptDir "monitor-runners.ps1"
if (-not (Test-Path $MonitorScript)) {
    Write-Error "monitor-runners.ps1 not found in $ScriptDir"
    exit 1
}

# Task name
$TaskName = "GitHubActionsRunnerMonitor"

# Check if task already exists
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Host "Task '$TaskName' already exists." -ForegroundColor Yellow
    $response = Read-Host "Do you want to update it? (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Host "Setup cancelled." -ForegroundColor Yellow
        exit 0
    }
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Removed existing task." -ForegroundColor Green
}

# Build the action arguments
$actionArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$MonitorScript`""
if ($SlackWebhookUrl) {
    $actionArgs += " -SlackWebhookUrl `"$SlackWebhookUrl`""
}

# Create the action
$action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument $actionArgs `
    -WorkingDirectory $ScriptDir

# Create the trigger (every N minutes)
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 365)

# Create settings
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

# Create the principal (run as current user)
$principal = New-ScheduledTaskPrincipal `
    -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Highest

# Register the task
try {
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $action `
        -Trigger $trigger `
        -Settings $settings `
        -Principal $principal `
        -Description "Monitors GitHub Actions runners and sends Slack alerts when they go offline" `
        | Out-Null
    
    Write-Host "✅ Scheduled task created successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "Task Details:" -ForegroundColor Cyan
    Write-Host "  Name: $TaskName" -ForegroundColor Gray
    Write-Host "  Interval: Every $IntervalMinutes minute(s)" -ForegroundColor Gray
    Write-Host "  Script: $MonitorScript" -ForegroundColor Gray
    Write-Host ""
    Write-Host "You can manage this task in Task Scheduler:" -ForegroundColor Yellow
    Write-Host "  Task Scheduler → Task Scheduler Library → $TaskName" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To test the monitor, run:" -ForegroundColor Yellow
    Write-Host "  .\monitor-runners.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "To remove the scheduled task:" -ForegroundColor Yellow
    Write-Host "  Unregister-ScheduledTask -TaskName '$TaskName' -Confirm:`$false" -ForegroundColor Gray
    
} catch {
    Write-Error "Failed to create scheduled task: $_"
    exit 1
}




