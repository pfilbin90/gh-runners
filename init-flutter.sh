#!/usr/bin/env bash
set -euo pipefail

FLUTTER_HOME=/opt/flutter
RELEASES_URL="https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json"

# Fetch the latest stable version from Flutter's releases API
get_latest_stable() {
  curl -fsSL "$RELEASES_URL" \
    | jq -r '[.releases[] | select(.channel == "stable")][0].version'
}

# Determine target version: pinned or latest stable
TARGET_VERSION="${FLUTTER_VERSION:-}"
if [ -z "$TARGET_VERSION" ]; then
  echo "[flutter-sdk] No FLUTTER_VERSION set, fetching latest stable..."
  TARGET_VERSION=$(get_latest_stable)
fi
test -n "$TARGET_VERSION" || { echo "[flutter-sdk] ERROR: Failed to determine Flutter version"; exit 1; }
echo "[flutter-sdk] Target Flutter version: $TARGET_VERSION"

# Check current state of the volume
if [ -f "$FLUTTER_HOME/bin/flutter" ]; then
  CURRENT_VERSION=$("$FLUTTER_HOME/bin/flutter" --version --machine 2>/dev/null | jq -r '.frameworkVersion // empty' || true)
  echo "[flutter-sdk] Current Flutter version: ${CURRENT_VERSION:-unknown}"

  if [ "$CURRENT_VERSION" = "$TARGET_VERSION" ]; then
    echo "[flutter-sdk] Already at target version $TARGET_VERSION, nothing to do."
    echo "[flutter-sdk] Running precache to ensure all artifacts are present..."
    git config --global safe.directory "$FLUTTER_HOME"
    "$FLUTTER_HOME/bin/flutter" precache --linux --web --android
    echo "[flutter-sdk] Done."
    exit 0
  fi

  echo "[flutter-sdk] Version mismatch (have $CURRENT_VERSION, want $TARGET_VERSION). Removing old SDK..."
  rm -rf "$FLUTTER_HOME" && mkdir -p "$FLUTTER_HOME"
fi

# Clone Flutter at the target version
echo "[flutter-sdk] Cloning Flutter $TARGET_VERSION..."
git clone --depth 1 -b "$TARGET_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_HOME"
git config --global safe.directory "$FLUTTER_HOME"

# Warm caches so runners don't have to
echo "[flutter-sdk] Running flutter precache..."
"$FLUTTER_HOME/bin/flutter" --version
"$FLUTTER_HOME/bin/flutter" precache --linux --web --android

echo "[flutter-sdk] Flutter $TARGET_VERSION ready."
