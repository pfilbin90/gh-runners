#!/bin/bash
# Start GitHub Actions runners on macOS startup
# This script is designed to be run by launchd

set -e

# Get the script directory (where docker-compose.yml is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Wait for Docker to be ready (Docker Desktop may take time to start)
MAX_WAIT=60
WAIT_COUNT=0
echo "Waiting for Docker to be ready..."

while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
    if docker info >/dev/null 2>&1; then
        echo "Docker is ready!"
        break
    fi
    sleep 2
    WAIT_COUNT=$((WAIT_COUNT + 2))
    echo "Still waiting... ($WAIT_COUNT/$MAX_WAIT seconds)"
done

if [ $WAIT_COUNT -ge $MAX_WAIT ]; then
    echo "Error: Docker did not become ready within $MAX_WAIT seconds" >&2
    exit 1
fi

# Start the containers
echo "Starting GitHub Actions runners..."
docker compose up -d

if [ $? -eq 0 ]; then
    echo "Runners started successfully!"
    # Show status
    sleep 2
    docker compose ps
else
    echo "Error: Failed to start runners" >&2
    exit 1
fi



