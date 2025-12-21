<#
.SYNOPSIS
    Updates Claude Code in the shared Docker volume used by GitHub Actions runners.

.DESCRIPTION
    This script updates the pre-installed Claude Code CLI in the claude-code Docker volume.
    Run this script every 6 hours via Windows Task Scheduler to keep Claude Code up to date
    without rebuilding the runner Docker image.

.NOTES
    Schedule via Task Scheduler:
    1. Open Task Scheduler
    2. Create Basic Task -> "Update Claude Code"
    3. Trigger: Daily, repeat every 6 hours
    4. Action: Start a program
       Program: powershell.exe
       Arguments: -ExecutionPolicy Bypass -File "C:\repos\gh-runners\update-claude-code.ps1"
    5. Finish
#>

$ErrorActionPreference = "Stop"

$logFile = Join-Path $PSScriptRoot "claude-code-update.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Write-Log {
    param([string]$Message)
    $entry = "[$timestamp] $Message"
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}

Write-Log "Starting Claude Code update..."

# Get the first running runner container
$container = docker ps --filter "name=gh-runners-runner" --format "{{.Names}}" | Select-Object -First 1

if (-not $container) {
    Write-Log "ERROR: No running runner container found. Ensure runners are running."
    exit 1
}

Write-Log "Using container: $container"

# Update Claude Code
try {
    $output = docker exec $container npm update -g @anthropic-ai/claude-code --prefix /opt/claude-code 2>&1
    Write-Log "npm update output: $output"

    # Verify the installation
    $version = docker exec $container /opt/claude-code/bin/claude --version 2>&1
    Write-Log "Claude Code version: $version"

    Write-Log "Claude Code update completed successfully."
} catch {
    Write-Log "ERROR: Failed to update Claude Code: $_"
    exit 1
}
