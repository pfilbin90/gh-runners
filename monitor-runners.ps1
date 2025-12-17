<#
.SYNOPSIS
    Monitors GitHub Actions runners and sends Slack alerts when they go offline.

.DESCRIPTION
    This script checks the status of all self-hosted GitHub Actions runners via the GitHub API
    and sends Slack notifications when runners transition from online to offline.

.PARAMETER SlackWebhookUrl
    Slack webhook URL for notifications. If not provided, will try to read from .env file.

.PARAMETER StateFile
    Path to file where previous runner state is stored. Defaults to .runner-state.json

.EXAMPLE
    .\monitor-runners.ps1 -SlackWebhookUrl "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
#>

param(
    [string]$SlackWebhookUrl = "",
    [string]$StateFile = ".runner-state.json"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Load environment variables from .env file
$envFile = Join-Path $ScriptDir ".env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        if ($_ -match '^\s*([^#][^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if ($key -and $value) {
                [Environment]::SetEnvironmentVariable($key, $value, "Process")
            }
        }
    }
}

# Get required environment variables
$GH_OWNER = $env:GH_OWNER
$GH_REPO = $env:GH_REPO
$GH_PAT = $env:GH_PAT
$SLACK_WEBHOOK = if ($SlackWebhookUrl) { $SlackWebhookUrl } else { $env:SLACK_WEBHOOK_URL }

# Validate required variables
if (-not $GH_OWNER) {
    Write-Error "GH_OWNER environment variable is required. Set it in .env file or environment."
    exit 1
}
if (-not $GH_REPO) {
    Write-Error "GH_REPO environment variable is required. Set it in .env file or environment."
    exit 1
}
if (-not $GH_PAT) {
    Write-Error "GH_PAT environment variable is required. Set it in .env file or environment."
    exit 1
}
if (-not $SLACK_WEBHOOK) {
    Write-Error "SLACK_WEBHOOK_URL environment variable or -SlackWebhookUrl parameter is required."
    exit 1
}

# GitHub API endpoint for runners
$API_URL = "https://api.github.com/repos/$GH_OWNER/$GH_REPO/actions/runners"

Write-Host "=== GitHub Actions Runner Monitor ===" -ForegroundColor Cyan
Write-Host "Repository: $GH_OWNER/$GH_REPO" -ForegroundColor Gray
Write-Host ""

# Fetch current runner status from GitHub API
Write-Host "Fetching runner status from GitHub..." -ForegroundColor Yellow
try {
    $headers = @{
        "Authorization" = "token $GH_PAT"
        "Accept" = "application/vnd.github+json"
        "X-GitHub-Api-Version" = "2022-11-28"
        "User-Agent" = "gh-runners-monitor"
    }
    
    $response = Invoke-RestMethod -Uri $API_URL -Method Get -Headers $headers -ErrorAction Stop
    $currentRunners = $response.runners
} catch {
    Write-Error "Failed to fetch runner status: $_"
    exit 1
}

Write-Host "Found $($currentRunners.Count) runner(s)" -ForegroundColor Green
Write-Host ""

# Load previous state
$previousState = @{}
$stateFilePath = Join-Path $ScriptDir $StateFile
if (Test-Path $stateFilePath) {
    try {
        $previousStateJson = Get-Content $stateFilePath -Raw | ConvertFrom-Json
        $previousStateJson.PSObject.Properties | ForEach-Object {
            $previousState[$_.Name] = $_.Value
        }
        Write-Host "Loaded previous state for $($previousState.Count) runner(s)" -ForegroundColor Gray
    } catch {
        Write-Warning "Failed to load previous state: $_"
    }
}

# Build current state and detect changes
$currentState = @{}
$offlineRunners = @()
$onlineRunners = @()

foreach ($runner in $currentRunners) {
    $runnerName = $runner.name
    $runnerStatus = $runner.status
    $runnerBusy = $runner.busy
    
    $currentState[$runnerName] = @{
        status = $runnerStatus
        busy = $runnerBusy
        os = $runner.os
        architecture = $runner.architecture
    }
    
    # Check if runner went offline
    if ($previousState.ContainsKey($runnerName)) {
        $prevStatus = $previousState[$runnerName].status
        if ($prevStatus -eq "online" -and $runnerStatus -eq "offline") {
            $offlineRunners += $runner
            Write-Host "⚠️  Runner went offline: $runnerName" -ForegroundColor Red
        } elseif ($prevStatus -eq "offline" -and $runnerStatus -eq "online") {
            $onlineRunners += $runner
            Write-Host "✅ Runner came online: $runnerName" -ForegroundColor Green
        }
    } elseif ($runnerStatus -eq "offline") {
        # New runner that's already offline (might be initial check)
        Write-Host "ℹ️  Runner is offline: $runnerName (initial check)" -ForegroundColor Yellow
    }
}

# Save current state
try {
    $currentStateJson = $currentState | ConvertTo-Json -Depth 3
    Set-Content -Path $stateFilePath -Value $currentStateJson -Force
    Write-Host "State saved to $StateFile" -ForegroundColor Gray
} catch {
    Write-Warning "Failed to save state: $_"
}

# Send Slack notifications for offline runners
if ($offlineRunners.Count -gt 0) {
    Write-Host ""
    Write-Host "Sending Slack notification for $($offlineRunners.Count) offline runner(s)..." -ForegroundColor Yellow
    
    $runnerList = $offlineRunners | ForEach-Object {
        $labels = if ($_.labels) { ($_.labels | ForEach-Object { $_.name }) -join ", " } else { "none" }
        "• *$($_.name)* (OS: $($_.os), Arch: $($_.architecture), Labels: $labels)"
    } | Out-String
    
    $message = @{
        text = "⚠️ *GitHub Actions Runner Alert*"
        blocks = @(
            @{
                type = "header"
                text = @{
                    type = "plain_text"
                    text = "⚠️ GitHub Actions Runner Offline"
                }
            },
            @{
                type = "section"
                text = @{
                    type = "mrkdwn"
                    text = "The following runner(s) have gone *offline*:`n`n$runnerList"
                }
            },
            @{
                type = "section"
                fields = @(
                    @{
                        type = "mrkdwn"
                        text = "*Repository:*`n$GH_OWNER/$GH_REPO"
                    },
                    @{
                        type = "mrkdwn"
                        text = "*Time:*`n$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')"
                    }
                )
            },
            @{
                type = "actions"
                elements = @(
                    @{
                        type = "button"
                        text = @{
                            type = "plain_text"
                            text = "View Runners"
                        }
                        url = "https://github.com/$GH_OWNER/$GH_REPO/settings/actions/runners"
                        style = "danger"
                    }
                )
            }
        )
    }
    
    try {
        $body = $message | ConvertTo-Json -Depth 10 -Compress
        $response = Invoke-RestMethod -Uri $SLACK_WEBHOOK -Method Post -Body $body -ContentType "application/json" -ErrorAction Stop
        Write-Host "✅ Slack notification sent successfully" -ForegroundColor Green
    } catch {
        Write-Error "Failed to send Slack notification: $_"
    }
} elseif ($onlineRunners.Count -gt 0) {
    Write-Host ""
    Write-Host "✅ $($onlineRunners.Count) runner(s) came back online (no notification sent)" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "✅ All runners are in expected state" -ForegroundColor Green
}

# Display current status summary
Write-Host ""
Write-Host "=== Current Runner Status ===" -ForegroundColor Cyan
foreach ($runner in $currentRunners | Sort-Object name) {
    $statusColor = if ($runner.status -eq "online") { "Green" } else { "Red" }
    $busyText = if ($runner.busy) { " (busy)" } else { "" }
    Write-Host "  $($runner.name): " -NoNewline
    Write-Host "$($runner.status)$busyText" -ForegroundColor $statusColor
}

Write-Host ""
Write-Host "=== Monitor Complete ===" -ForegroundColor Cyan




