#!/bin/bash
# Update script for Synology NAS runners
#
# Usage:
#   1. Upload this script to your Synology (e.g., /volume1/docker/)
#   2. Edit the configuration variables below
#   3. Run: bash update-synology-runners.sh
#
# This script will:
#   - Pull the latest runner image from GHCR
#   - Stop and remove existing runner containers
#   - Recreate them with the new image
#   - Preserve all cached data in shared folders

set -e

# =============================================================================
# Configuration - EDIT THESE VALUES
# =============================================================================
GH_OWNER="your-github-username"
GH_REPO="your-repo-name"
GH_PAT="ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
RUNNER_GROUP="Default"
RUNNER_LABELS="self-hosted,Linux,X64"
IMAGE="ghcr.io/${GH_OWNER}/actions-runner-flutter:latest"

# Runner names
RUNNER_1_NAME="synology-runner-1"
RUNNER_2_NAME="synology-runner-2"

# Shared folder paths
RUNNER_1_PATH="/volume1/gh-runner"
RUNNER_2_PATH="/volume1/gh-runner2"

# =============================================================================
# Update Process
# =============================================================================

echo "=============================================="
echo "  Synology GitHub Actions Runner Update"
echo "=============================================="
echo ""
echo "Image: $IMAGE"
echo "Runner 1: $RUNNER_1_NAME"
echo "Runner 2: $RUNNER_2_NAME"
echo ""

# Pull latest image
echo "[1/4] Pulling latest image..."
docker pull "$IMAGE"
echo "✓ Image pulled successfully"
echo ""

# Stop and remove existing containers
echo "[2/4] Stopping existing runners..."
docker stop gh-runner-1 2>/dev/null || echo "  gh-runner-1 not running"
docker stop gh-runner-2 2>/dev/null || echo "  gh-runner-2 not running"

docker rm gh-runner-1 2>/dev/null || echo "  gh-runner-1 already removed"
docker rm gh-runner-2 2>/dev/null || echo "  gh-runner-2 already removed"
echo "✓ Old containers removed"
echo ""

# Recreate runner 1
echo "[3/4] Creating gh-runner-1..."
docker run -d \
  --name gh-runner-1 \
  --restart always \
  -e GH_OWNER="$GH_OWNER" \
  -e GH_REPO="$GH_REPO" \
  -e GH_PAT="$GH_PAT" \
  -e RUNNER_GROUP="$RUNNER_GROUP" \
  -e RUNNER_LABELS="$RUNNER_LABELS" \
  -e RUNNER_NAME="$RUNNER_1_NAME" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ${RUNNER_1_PATH}/register-and-run.sh:/home/runner/register-and-run.sh:ro \
  -v ${RUNNER_1_PATH}/work:/_work \
  -v ${RUNNER_1_PATH}/pub-cache:/home/runner/.pub-cache \
  -v ${RUNNER_1_PATH}/npm-cache:/home/runner/.npm \
  -v ${RUNNER_1_PATH}/pnpm-store:/home/runner/.local/share/pnpm \
  -v ${RUNNER_1_PATH}/flutter-cache:/home/runner/.cache/flutter \
  --entrypoint /bin/bash \
  "$IMAGE" \
  -lc /home/runner/register-and-run.sh

echo "✓ gh-runner-1 created"

# Recreate runner 2
echo ""
echo "[4/4] Creating gh-runner-2..."
docker run -d \
  --name gh-runner-2 \
  --restart always \
  -e GH_OWNER="$GH_OWNER" \
  -e GH_REPO="$GH_REPO" \
  -e GH_PAT="$GH_PAT" \
  -e RUNNER_GROUP="$RUNNER_GROUP" \
  -e RUNNER_LABELS="$RUNNER_LABELS" \
  -e RUNNER_NAME="$RUNNER_2_NAME" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v ${RUNNER_2_PATH}/register-and-run.sh:/home/runner/register-and-run.sh:ro \
  -v ${RUNNER_2_PATH}/work:/_work \
  -v ${RUNNER_2_PATH}/pub-cache:/home/runner/.pub-cache \
  -v ${RUNNER_2_PATH}/npm-cache:/home/runner/.npm \
  -v ${RUNNER_2_PATH}/pnpm-store:/home/runner/.local/share/pnpm \
  -v ${RUNNER_2_PATH}/flutter-cache:/home/runner/.cache/flutter \
  --entrypoint /bin/bash \
  "$IMAGE" \
  -lc /home/runner/register-and-run.sh

echo "✓ gh-runner-2 created"
echo ""

# Wait for containers to start
echo "Waiting for containers to initialize..."
sleep 5

# Show status
echo ""
echo "=============================================="
echo "  Update Complete"
echo "=============================================="
echo ""
echo "Container Status:"
docker ps -a --filter name=gh-runner --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"
echo ""

# Show recent logs
echo "Recent logs from gh-runner-1:"
echo "---"
docker logs --tail 10 gh-runner-1
echo ""

echo "Recent logs from gh-runner-2:"
echo "---"
docker logs --tail 10 gh-runner-2
echo ""

echo "✓ Both runners should now be registering with GitHub"
echo "✓ Check Settings → Actions → Runners in your repository"
echo ""
