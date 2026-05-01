# Host-Synced Flutter SDK on Mac ARM64 Runners

**Date:** 2026-05-01
**Scope:** Mac ARM64 (`docker-compose.local.yml` + `Dockerfile.runner.arm64`) only. Linux/Windows production setup is untouched.

## Problem

The Mac ARM64 runner image bakes Flutter into the image at build time (`Dockerfile.runner.arm64` lines 72-88: `git clone` + `flutter precache`). When Flutter releases a new major or minor version, the user must rebuild the entire image — Java, Android SDK, Node, Bun, Supabase CLI, and everything else gets reinstalled even though only Flutter changed. Local rebuilds take a long time and waste effort.

## Goal

Move the Flutter SDK out of the image into a Docker volume that auto-syncs to the version of Flutter installed on the host Mac. After `flutter upgrade` on the host, a single `docker compose ... restart` brings the runners current — no image rebuild.

## Constraint: why we can't bind-mount host Flutter directly

The host runs macOS ARM64; the runner containers run Linux ARM64. The Flutter SDK directory contains platform-specific binaries — most notably `bin/cache/dart-sdk/bin/dart` (a Mach-O macOS binary on the host) and various artifacts under `bin/cache/`. Mounting the host SDK directly into Linux containers would crash on first invocation.

**Solution:** sync the *git ref*, not the bytes. The host SDK is bind-mounted read-only purely for version detection. The container has its own Linux ARM64 SDK in a Docker volume, kept at the same git ref as the host.

## Architecture

Three changes:

### 1. `Dockerfile.runner.arm64` — strip Flutter

Remove lines 72-88 (the `ARG FLUTTER_CACHE_BUST`, the Flutter section header, and the `RUN` block that clones Flutter and runs `precache` / `doctor`). Keep:

- `ENV FLUTTER_HOME=/opt/flutter`
- `ENV PATH=/opt/claude-code/bin:$FLUTTER_HOME/bin:$FLUTTER_HOME/bin/cache/dart-sdk/bin:$PATH`

The image ships with `flutter` on PATH but no SDK content. Bootstrap populates `/opt/flutter` at container start.

### 2. New file: `mac-bootstrap-flutter.sh`

Lives at the repo root, mounted into containers via the local override. Idempotent: a no-op (~1s) when host and container are already in sync.

```bash
#!/usr/bin/env bash
set -euo pipefail

# Skip silently if not in Mac mode (no host Flutter bind-mount).
# This keeps the script safe to run unconditionally from the entrypoint.
[ -d /host-flutter/.git ] || exit 0

mkdir -p /opt/flutter

# Single-flight: 4 containers may start simultaneously and share the volume.
# Run the rest of the script under a flock; concurrent starts serialize and the
# losers see "in sync" once the winner finishes.
exec 9>/opt/flutter/.bootstrap.lock
flock 9

HOST_REF=$(git -C /host-flutter rev-parse HEAD)
CUR_REF=$(git -C /opt/flutter rev-parse HEAD 2>/dev/null || true)

if [ "$HOST_REF" = "$CUR_REF" ] && [ -x /opt/flutter/bin/flutter ]; then
  echo "[flutter-bootstrap] in sync at $HOST_REF, skipping"
  exit 0
fi

echo "[flutter-bootstrap] syncing /opt/flutter to host ref $HOST_REF"

# We can't `git clone` into /opt/flutter because we already created
# .bootstrap.lock in it (clone refuses non-empty targets). `git init` + a
# manual remote works fine in a non-empty dir; fetch-by-SHA brings the ref in.
if [ ! -d /opt/flutter/.git ]; then
  ( cd /opt/flutter && git init -q && git remote add origin https://github.com/flutter/flutter.git )
fi

git config --global --add safe.directory /opt/flutter
cd /opt/flutter

# Try a shallow fetch of the exact ref first; fall back to a full fetch if
# the ref isn't reachable that way (e.g., very recent commit or custom branch).
if ! git fetch --depth 50 origin "$HOST_REF" 2>/dev/null; then
  echo "[flutter-bootstrap] shallow fetch failed; falling back to full fetch"
  git fetch origin
  git fetch --tags
fi

if ! git checkout --detach "$HOST_REF" 2>/dev/null; then
  echo "[flutter-bootstrap] WARNING: could not check out $HOST_REF; leaving volume at $CUR_REF"
  exit 0
fi

flutter --version
flutter precache --linux --web --android
flutter doctor --android-licenses >/dev/null 2>&1 || true
flutter doctor || true

echo "[flutter-bootstrap] done"
```

### 3. `docker-compose.local.yml` — wire it up

Add to each runner (or via a shared anchor):

- **Bind-mount** host Flutter, read-only, configurable via env var with a Homebrew default:
  `${HOST_FLUTTER_PATH:-/opt/homebrew/share/flutter}:/host-flutter:ro`
- **Mount** the bootstrap script: `./mac-bootstrap-flutter.sh:/home/runner/mac-bootstrap-flutter.sh:ro`
- **Named volume** for the container's Linux Flutter SDK: `flutter-sdk:/opt/flutter`
- **Override entrypoint** to run bootstrap before register-and-run:
  `entrypoint: ["/bin/bash","-lc","/home/runner/mac-bootstrap-flutter.sh && /home/runner/register-and-run.sh"]`
- **Declare** the new `flutter-sdk` volume in the override's `volumes:` section.

`register-and-run.sh` is **not** modified — Linux production behavior is unchanged.

## Workflow

```bash
# When you want to update Flutter:
flutter upgrade
docker compose -f docker-compose.yml -f docker-compose.local.yml restart

# Or, if you want to also rebuild the image for unrelated Dockerfile changes:
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d --build
```

The first restart after a Flutter upgrade takes 2-5 minutes (new Dart SDK + artifact downloads); subsequent job runs are instant.

## Trade-offs

- ✅ No image rebuild for Flutter version changes
- ✅ Image shrinks ~2 GB (Flutter SDK gone)
- ✅ Host is single source of truth for Flutter version
- ✅ Linux production setup unchanged
- ⚠️ First-ever container start downloads Flutter into the volume (~2-5 min, one-time)
- ⚠️ `docker compose restart` required after `flutter upgrade` (not pure auto, but a single command)
- ⚠️ Container start adds ~1s for the no-op git ref check when in sync

## Edge cases

| Case | Behavior |
|------|----------|
| Host ref not reachable on upstream remote | Bootstrap logs a warning and leaves the volume at its current ref. Runner stays usable. |
| First-ever start with no host Flutter mounted | `[ -d /host-flutter/.git ] || exit 0` exits cleanly. Subsequent `flutter` calls fail loudly — clear misconfig signal. |
| Four containers start simultaneously | `flock` on `/opt/flutter/.bootstrap.lock` serializes; only one container does the git work, the rest wait and then see "in sync". |
| User wants a non-Homebrew Flutter path | Set `HOST_FLUTTER_PATH=/path/to/flutter` in `.env` before `up -d`. |
| Docker Desktop file sharing rejects `/opt/homebrew` | One-time prereq: add `/opt/homebrew` (or parent of `HOST_FLUTTER_PATH`) under Docker Desktop → Settings → Resources → File sharing. Without this, `up -d` fails with "mounts denied". |
| `flutter precache` fails | Surface the error (no `|| true`); a partial Flutter install is worse than a loud failure. `flutter doctor --android-licenses` keeps `|| true` since it's nice-to-have. |

## Files

| File | Change |
|------|--------|
| `Dockerfile.runner.arm64` | Remove Flutter install block (lines 72-88). Keep `FLUTTER_HOME` and PATH. |
| `mac-bootstrap-flutter.sh` | **New.** Idempotent host-version sync, with `flock`. |
| `docker-compose.local.yml` | Add bind-mount, script mount, named volume, override entrypoint, declare volume. |
| `CLAUDE.md` | Update "macOS ARM64 (Local Development)" section: document the new `flutter upgrade && restart` workflow and the `HOST_FLUTTER_PATH` env var. |

## Out of scope

- Linux/Windows production runners (still use baked-in Flutter)
- Volume-mounting Android SDK, Node, etc. (one knob at a time; Flutter is the one that changes most often)
- Auto-restarting containers when host Flutter changes (would need a watcher; manual `restart` is simpler and safer)
