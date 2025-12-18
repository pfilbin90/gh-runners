#!/bin/bash
# Updates the self-hosted GitHub Actions runners to the latest image.
#
# Usage:
#   ./update-runners.sh
#   ./update-runners.sh --force
#   ./update-runners.sh --tag v1.0.0

set -e

FORCE=false
TAG="latest"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --force|-f)
            FORCE=true
            shift
            ;;
        --tag|-t)
            TAG="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            echo "Usage: $0 [--force] [--tag TAG]" >&2
            exit 1
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== GitHub Actions Runner Update ==="
echo ""

# Change to script directory
cd "$SCRIPT_DIR"

# Check Docker is available
echo "Checking Docker availability..."
if ! docker --version >/dev/null 2>&1; then
    echo "Error: Docker is not available. Please ensure Docker Desktop is running." >&2
    exit 1
fi
echo "  $(docker --version)"
echo ""

# Pull latest image
echo "Pulling latest runner image..."
docker compose pull
if [ $? -ne 0 ]; then
    echo "Error: Failed to pull latest image" >&2
    exit 1
fi
echo "  Image pulled successfully"
echo ""

# Show current container status
echo "Current container status:"
docker compose ps
echo ""

# Confirm update (unless --force is specified)
if [ "$FORCE" != "true" ]; then
    read -p "Do you want to restart the runners with the new image? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "Update cancelled."
        exit 0
    fi
fi

# Stop current containers
echo ""
echo "Stopping current runners..."
docker compose down
echo "  Runners stopped"
echo ""

# Start with new image
echo "Starting runners with new image..."
docker compose up -d
echo "  Runners started"
echo ""

# Wait a moment for containers to initialize
sleep 5

# Show new status
echo "New container status:"
docker compose ps
echo ""

# Show recent logs
echo "Recent logs (last 10 lines per container):"
docker compose logs --tail=10
echo ""

echo "=== Update Complete ==="
echo ""
echo "Your runners should now be registering with GitHub."
echo "Check the Actions tab in your repository to verify they appear."


