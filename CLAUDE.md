# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Self-hosted GitHub Actions runners for Flutter CI/CD, packaged as Docker containers with all dependencies pre-installed. The runner image is designed to eliminate SDK download times in workflows.

## Architecture

- **Dockerfile.runner**: Custom runner image extending `ghcr.io/actions/actions-runner` with Flutter, Android SDK (including pre-created AVD), Node.js, Chrome, and build tools
- **docker-compose.yml**: Runs 4 parallel ephemeral runners with shared caches for pub, npm, pnpm, and Flutter
- **register-and-run.sh**: Entrypoint script that fetches GitHub registration token and configures ephemeral runner
- **.github/workflows/rebuild-image.yml**: Monthly automated image rebuild with Slack notifications

## Common Commands

```powershell
# Start runners
docker compose up -d

# Stop runners
docker compose down

# Update to latest image
.\update-runners.ps1
# or manually:
docker compose pull && docker compose down && docker compose up -d

# View runner logs
docker compose logs -f

# Build image locally (instead of pulling from GHCR)
.\build-and-push.ps1 <github-username>
```

## Environment Configuration

Copy `.env.example` to `.env` and set:
- `GH_OWNER`: GitHub username or org
- `GH_REPO`: Repository to register runners with
- `GH_PAT`: Personal Access Token (needs `repo`, `workflow` scopes)
- `RUNNER_NAME_PREFIX`: Prefix for runner names (creates 4 runners: prefix-1 through prefix-4)
- `RUNNER_LABELS`: Runner labels for workflow targeting

## Pre-installed Tools in Runner Image

| Tool | Version | Notes |
|------|---------|-------|
| Flutter | 3.35.7 | `$FLUTTER_HOME=/opt/flutter` |
| Android SDK | 33, 34 | Pre-created AVD named "test_avd" (Pixel 4, API 33) |
| Java | 8, 21 | Both versions available; 21 is default |
| Node.js | 22.x | With pnpm 9.x |
| Chrome + ChromeDriver | Latest stable | |
| Supabase CLI | Latest | |

## Key Implementation Details

- Runners are **ephemeral** (`--ephemeral` flag) - they auto-deregister after one job
- Docker socket is mounted from host for Docker-in-Docker support
- `/dev/kvm` is mounted for hardware-accelerated Android emulator
- Volumes persist package caches across container restarts

## Synology NAS Deployment

For running these runners on a Synology NAS, see **[SYNOLOGY.md](SYNOLOGY.md)** for complete setup and update instructions.

Key differences from standard deployment:
- Uses shared folders (`/volume1/gh-runner`, `/volume1/gh-runner2`) instead of Docker volumes
- Requires manual script upload and permission setup
- Uses `update-synology-runners.sh` instead of PowerShell update script
- KVM hardware acceleration not available (software emulation only)

## Updating Flutter Version

1. Edit `FLUTTER_VERSION` in `Dockerfile.runner`
2. Push to trigger rebuild workflow, or run `.\build-and-push.ps1`
3. Run `.\update-runners.ps1` on host machine (or `update-synology-runners.sh` on Synology)
