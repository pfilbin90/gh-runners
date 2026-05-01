<#
.SYNOPSIS
    Updates the Flutter SDK in the shared Docker volume.

.DESCRIPTION
    Runs the flutter-sdk init container to install or update the Flutter SDK.
    Runners pick up the new version on their next ephemeral cycle.

.EXAMPLE
    .\update-flutter.ps1
    .\update-flutter.ps1 -Version 3.41.9
#>

param(
    [string]$Version
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== Flutter SDK Update ===" -ForegroundColor Cyan
Write-Host ""

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

    # Build args
    $env:FLUTTER_VERSION = $Version
    if ($Version) {
        Write-Host "Target version: $Version" -ForegroundColor Yellow
    } else {
        Write-Host "Target version: latest stable" -ForegroundColor Yellow
    }
    Write-Host ""

    # Run the init container
    Write-Host "Updating Flutter SDK..." -ForegroundColor Yellow
    docker compose run --rm flutter-sdk
    if (-not $?) {
        throw "Flutter SDK update failed"
    }
    Write-Host ""

    Write-Host "=== Update Complete ===" -ForegroundColor Green
    Write-Host ""
    Write-Host "Runners will use the new Flutter version on their next job." -ForegroundColor Cyan

} finally {
    # Clean up env var
    Remove-Item Env:\FLUTTER_VERSION -ErrorAction SilentlyContinue
    Pop-Location
}
