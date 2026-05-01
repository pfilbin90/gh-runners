#!/usr/bin/env bash
# Syncs /opt/flutter (Linux ARM64 SDK in a Docker volume) to the same git ref
# as the host Mac's Flutter install (bind-mounted read-only at /host-flutter).
# Invoked from the entrypoint on Mac via docker-compose.local.yml. On Linux
# production runners /host-flutter is not mounted and this script is a no-op.
set -euo pipefail

# Skip silently when /host-flutter isn't bind-mounted (Linux mode, or first-ever
# start with a misconfigured env). The runner will surface a loud failure later
# if /opt/flutter is empty when a workflow tries to use flutter.
[ -d /host-flutter/.git ] || exit 0

mkdir -p /opt/flutter

# Single-flight: 4 containers may start simultaneously and share the volume.
# Concurrent starts serialize on this lock; whoever loses the race sees
# "in sync" once the winner finishes and exits fast.
exec 9>/opt/flutter/.bootstrap.lock
flock 9

git config --global --add safe.directory /host-flutter
git config --global --add safe.directory /opt/flutter

HOST_REF=$(git -C /host-flutter rev-parse HEAD)
HOST_CHANNEL=$(git -C /host-flutter rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
CUR_REF=$(git -C /opt/flutter rev-parse HEAD 2>/dev/null || true)
CUR_BRANCH=$(git -C /opt/flutter rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Restores the volume's HEAD to the host's channel branch (e.g. `stable`).
# Required because plain `git checkout --detach <sha>` below leaves Flutter
# in detached-HEAD state, which makes `flutter --version` report
# `channel [user-branch] • unknown source` and breaks `pub get` against any
# pubspec with a Flutter SDK constraint (pub falls back to `0.0.0-unknown`).
restore_channel() {
  if [[ ! "$HOST_CHANNEL" =~ ^(stable|beta|dev|master|main)$ ]]; then
    echo "[flutter-bootstrap] WARNING: host channel '$HOST_CHANNEL' is not a known release channel; skipping channel pin"
    return
  fi
  git -C /opt/flutter branch -f "$HOST_CHANNEL" HEAD
  git -C /opt/flutter checkout "$HOST_CHANNEL"
}

if [ "$HOST_REF" = "$CUR_REF" ] && [ -x /opt/flutter/bin/flutter ]; then
  if [ "$CUR_BRANCH" = "$HOST_CHANNEL" ] || [ "$CUR_BRANCH" = "HEAD" ]; then
    # Volume's SHA matches host but HEAD is detached (CUR_BRANCH=HEAD).
    # Common after upgrading from the pre-channel-pin version of this script —
    # restore the channel branch in place without re-fetching.
    if [ "$CUR_BRANCH" = "HEAD" ]; then
      echo "[flutter-bootstrap] in sync at $HOST_REF but detached; restoring channel"
      restore_channel
    else
      echo "[flutter-bootstrap] in sync at $HOST_REF on $CUR_BRANCH, skipping"
    fi
    exit 0
  fi
fi

echo "[flutter-bootstrap] syncing /opt/flutter to host ref $HOST_REF"

# We can't `git clone` into /opt/flutter because we already created
# .bootstrap.lock in it (clone refuses non-empty targets). `git init` + a
# manual remote works fine in a non-empty dir; fetch-by-SHA brings the ref in.
if [ ! -d /opt/flutter/.git ]; then
  ( cd /opt/flutter && git init -q && git remote add origin https://github.com/flutter/flutter.git )
fi

cd /opt/flutter

# Try a shallow fetch of the exact ref first; fall back to a full fetch if the
# ref isn't reachable that way (e.g., very recent commit or custom branch).
if ! git fetch --depth 50 origin "$HOST_REF" 2>/dev/null; then
  echo "[flutter-bootstrap] shallow fetch failed; falling back to full fetch"
  git fetch origin
  git fetch --tags
fi

if ! git checkout --detach "$HOST_REF" 2>/dev/null; then
  echo "[flutter-bootstrap] WARNING: could not check out $HOST_REF; leaving volume at ${CUR_REF:-empty}"
  exit 0
fi

restore_channel

flutter --version
flutter precache --linux --web --android
flutter doctor --android-licenses >/dev/null 2>&1 || true
flutter doctor || true

echo "[flutter-bootstrap] done"
