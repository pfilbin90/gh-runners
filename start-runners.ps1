# Start GitHub Actions runners on Windows startup
# This script is designed to be run by Task Scheduler

$ErrorActionPreference = "Stop"

# Get the script directory (where docker-compose.yml is located)
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Wait for Docker to be ready (Docker Desktop may take time to start)
$MaxWait = 60
$WaitCount = 0
Write-Host "Waiting for Docker to be ready..."

while ($WaitCount -lt $MaxWait) {
    try {
        docker info 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Docker is ready!"
            break
        }
    } catch {
        # Docker not ready yet
    }
    Start-Sleep -Seconds 2
    $WaitCount += 2
    Write-Host "Still waiting... ($WaitCount/$MaxWait seconds)"
}

if ($WaitCount -ge $MaxWait) {
    Write-Error "Docker did not become ready within $MaxWait seconds"
    exit 1
}

# Start the containers
Write-Host "Starting GitHub Actions runners..."
docker-compose up -d

if ($LASTEXITCODE -eq 0) {
    Write-Host "Runners started successfully!"
    # Show status
    Start-Sleep -Seconds 2
    docker-compose ps
} else {
    Write-Error "Failed to start runners"
    exit 1
}




