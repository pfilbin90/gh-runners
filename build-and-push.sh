#!/bin/bash
# Build and push GitHub Actions runner image to GHCR
# Usage: ./build-and-push.sh [github-username-or-org] [image-tag]

set -e

# Parse arguments
GITHUB_OWNER="${1:-}"
IMAGE_TAG="${2:-latest}"

# Get GitHub owner if not provided
if [ -z "$GITHUB_OWNER" ]; then
    read -p "Enter your GitHub username or organization name: " GITHUB_OWNER
fi

if [ -z "$GITHUB_OWNER" ]; then
    echo "Error: GitHub owner is required" >&2
    exit 1
fi

# GHCR image name (must match docker-compose.yml)
IMAGE_NAME="ghcr.io/$GITHUB_OWNER/actions-runner-flutter"
FULL_IMAGE_TAG="${IMAGE_NAME}:${IMAGE_TAG}"

echo ""
echo "Building and pushing image to GHCR"
echo "Image: $FULL_IMAGE_TAG"
echo ""

# Check if logged into GHCR
echo "Checking Docker login status..."
if ! docker info 2>&1 | grep -q "ghcr.io"; then
    echo ""
    echo "You need to login to GHCR first."
    echo "Create a Personal Access Token (PAT) with 'write:packages' permission at:"
    echo "https://github.com/settings/tokens"
    echo ""
    read -sp "Enter your GitHub PAT (or press Enter to skip login check): " token
    echo ""
    if [ -n "$token" ]; then
        echo "Logging into GHCR..."
        echo "$token" | docker login ghcr.io -u "$GITHUB_OWNER" --password-stdin
        if [ $? -ne 0 ]; then
            echo "Error: Failed to login to GHCR" >&2
            exit 1
        fi
    fi
fi

# Build the image
echo ""
echo "Building image: $FULL_IMAGE_TAG"
echo "This may take several minutes..."
docker build -f Dockerfile.runner -t "$FULL_IMAGE_TAG" .

if [ $? -ne 0 ]; then
    echo "Error: Build failed" >&2
    exit 1
fi

echo ""
echo "Build successful!"
echo ""

# Ask if user wants to push
read -p "Push image to GHCR? (Y/n): " push
if [ -z "$push" ] || [ "$push" = "Y" ] || [ "$push" = "y" ]; then
    echo ""
    echo "Pushing image to GHCR..."
    docker push "$FULL_IMAGE_TAG"
    
    if [ $? -ne 0 ]; then
        echo "Error: Push failed. Make sure you're logged in and have write permissions." >&2
        echo ""
        echo "To login manually, run:"
        echo "  echo YOUR_PAT | docker login ghcr.io -u $GITHUB_OWNER --password-stdin"
        exit 1
    fi
    
    echo ""
    echo "Successfully pushed: $FULL_IMAGE_TAG"
    echo ""
    echo "To use this image, update your docker-compose.yml:"
    echo "  image: $FULL_IMAGE_TAG"
    echo ""
    echo "Or pull it later with:"
    echo "  docker pull $FULL_IMAGE_TAG"
else
    echo ""
    echo "Image built but not pushed: $FULL_IMAGE_TAG"
    echo "Push manually with: docker push $FULL_IMAGE_TAG"
fi

