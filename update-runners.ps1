<#
.SYNOPSIS
    Updates the self-hosted GitHub Actions runners to the latest image.

.DESCRIPTION
    Pulls the latest runner image from GHCR, stops current containers,
    and restarts them with the new image.

.EXAMPLE
    .\update-runners.ps1
#>

param(
    [switch]$Force,
    [string]$Tag = "latest"
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== GitHub Actions Runner Update ===" -ForegroundColor Cyan
Write-Host ""

# Change to script directory
Push-Location $ScriptDir

try {
    # Check Docker is available
    Write-Host "Checking Docker availability..." -ForegroundColor Yellow
    $dockerVersion = docker --version
    if (-not $?) {
        throw "Docker is not available. Please ensure Docker Desktop is running."
    }
    Write-Host "  $dockerVersion" -ForegroundColor Green
    Write-Host ""

    # Pull latest image
    Write-Host "Pulling latest runner image..." -ForegroundColor Yellow
    docker compose pull
    if (-not $?) {
        throw "Failed to pull latest image"
    }
    Write-Host "  Image pulled successfully" -ForegroundColor Green
    Write-Host ""

    # Show current container status
    Write-Host "Current container status:" -ForegroundColor Yellow
    docker compose ps
    Write-Host ""

    # Confirm update (unless -Force is specified)
    if (-not $Force) {
        $confirm = Read-Host "Do you want to restart the runners with the new image? (y/N)"
        if ($confirm -ne "y" -and $confirm -ne "Y") {
            Write-Host "Update cancelled." -ForegroundColor Yellow
            exit 0
        }
    }

    # Stop current containers
    Write-Host ""
    Write-Host "Stopping current runners..." -ForegroundColor Yellow
    docker compose down
    Write-Host "  Runners stopped" -ForegroundColor Green
    Write-Host ""

    # Start with new image
    Write-Host "Starting runners with new image..." -ForegroundColor Yellow
    docker compose up -d
    Write-Host "  Runners started" -ForegroundColor Green
    Write-Host ""

    # Wait a moment for containers to initialize
    Start-Sleep -Seconds 5

    # Show new status
    Write-Host "New container status:" -ForegroundColor Yellow
    docker compose ps
    Write-Host ""

    # Show recent logs
    Write-Host "Recent logs (last 10 lines per container):" -ForegroundColor Yellow
    docker compose logs --tail=10
    Write-Host ""

    Write-Host "=== Update Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Your runners should now be registering with GitHub." -ForegroundColor Cyan
    Write-Host "Check the Actions tab in your repository to verify they appear." -ForegroundColor Cyan

} finally {
    Pop-Location
}
