# Setup script to configure GitHub Actions runners to start on Windows startup
# Run this script as Administrator: Right-click PowerShell -> "Run as Administrator"

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Error "This script must be run as Administrator. Right-click PowerShell and select 'Run as Administrator'"
    exit 1
}

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$StartScript = Join-Path $ScriptDir "start-runners.ps1"

# Create the scheduled task
$TaskName = "GitHub Actions Runners - Auto Start"
$TaskDescription = "Automatically starts GitHub Actions runner containers on Windows startup"

# Remove existing task if it exists
$ExistingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($ExistingTask) {
    Write-Host "Removing existing task..."
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# Create the action (run PowerShell script)
$Action = New-ScheduledTaskAction -Execute "powershell.exe" `
    -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$StartScript`""

# Create the trigger (on system startup)
$Trigger = New-ScheduledTaskTrigger -AtStartup

# Create the principal (run as current user, highest privileges)
$Principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" `
    -LogonType Interactive `
    -RunLevel Highest

# Create settings
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)

# Register the task
Write-Host "Creating scheduled task: $TaskName"
Register-ScheduledTask -TaskName $TaskName `
    -Description $TaskDescription `
    -Action $Action `
    -Trigger $Trigger `
    -Principal $Principal `
    -Settings $Settings

Write-Host ''
Write-Host 'Scheduled task created successfully!'
Write-Host ''
Write-Host 'The task will:'
Write-Host '  - Start when Windows boots'
Write-Host '  - Wait for Docker to be ready'
Write-Host '  - Start all runner containers'
Write-Host '  - Retry up to 3 times if it fails'
Write-Host ''
Write-Host 'To test the task manually, run:'
Write-Host ('  Start-ScheduledTask -TaskName ' + $TaskName)
Write-Host ''
Write-Host 'To view/edit the task:'
Write-Host '  - Open Task Scheduler (taskschd.msc)'
Write-Host ('  - Look for: ' + $TaskName)

