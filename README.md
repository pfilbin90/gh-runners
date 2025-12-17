# Self-Hosted GitHub Actions Runners

Docker-based self-hosted GitHub Actions runners pre-loaded with Flutter, Android SDK, Node.js, Chrome, and CI tools. Designed to eliminate SDK download times in workflows.

## What's Included

| Tool | Version | Notes |
|------|---------|-------|
| Flutter | Latest stable | Auto-fetched at build time |
| Android SDK | API 33, 34 | Pre-created AVD "test_avd" (Pixel 4) |
| Java | 8, 21 | Both available; 21 is default |
| Node.js | 22.x | With pnpm 9.x |
| Chrome + ChromeDriver | Latest stable | Auto-matched versions |
| Supabase CLI | Latest | |
| Docker CLI | Latest | For Docker-in-Docker support |

---

## Prerequisites

1. **Docker** installed and running
2. **GitHub Personal Access Token (PAT)** with `repo` and `workflow` scopes
   - Create at: https://github.com/settings/tokens
3. **GitHub Container Registry access** (for pushing/pulling images)
   - PAT also needs `write:packages` scope for pushing

---

## Quick Start

### 1. Build the Image

```powershell
.\build-and-push.ps1 <your-github-username>
```

This will:
- Build the Docker image with all tools
- Optionally push to GitHub Container Registry (GHCR)

The image will be tagged as `ghcr.io/<your-github-username>/actions-runner-flutter:latest`

### 2. Configure Environment

Create a `.env` file in the project root:

```env
GH_OWNER=your-github-username
GH_REPO=your-repo-name
GH_PAT=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
RUNNER_NAME_PREFIX=my-runner
RUNNER_GROUP=Default
RUNNER_LABELS=self-hosted,Linux,X64
```

### 3. Start Runners

```powershell
docker compose up -d
```

This starts 4 parallel runners. Check status:

```powershell
docker compose ps
docker compose logs -f
```

---

## Deployment: Local Desktop (Windows)

### Initial Setup

1. Clone this repo
2. Build and push the image:
   ```powershell
   .\build-and-push.ps1 <your-github-username>
   ```
3. Create `.env` file (see above)
4. Start runners:
   ```powershell
   docker compose up -d
   ```

### Auto-Start on Boot

Run the setup script to create a Windows Task Scheduler task:

```powershell
.\setup-startup.ps1
```

Or manually start with:

```powershell
.\start-runners.ps1
```

### Daily Operations

```powershell
# Start runners
docker compose up -d

# Stop runners
docker compose down

# View logs
docker compose logs -f

# Check status
docker compose ps
```

### Updating to a New Image

When you want to rebuild with the latest Flutter/tools:

```powershell
# Rebuild and push
.\build-and-push.ps1 <your-github-username>

# Update running containers
.\update-runners.ps1

# Or manually:
docker compose pull
docker compose down
docker compose up -d
```

---

## Deployment: Synology NAS

See [SYNOLOGY.md](SYNOLOGY.md) for detailed instructions.

### Quick Summary

1. **Create shared folders** via DSM: `gh-runner`, `gh-runner2`

2. **SSH in and create directories:**
   ```bash
   sudo mkdir -p /volume1/gh-runner/{work,pub-cache,npm-cache,pnpm-store,flutter-cache}
   sudo mkdir -p /volume1/gh-runner2/{work,pub-cache,npm-cache,pnpm-store,flutter-cache}
   sudo chown -R 1001:1001 /volume1/gh-runner /volume1/gh-runner2
   ```

3. **Upload `register-and-run.sh`** to both folders and make executable:
   ```bash
   chmod +x /volume1/gh-runner/register-and-run.sh
   chmod +x /volume1/gh-runner2/register-and-run.sh
   ```

4. **Pull the image:**
   ```bash
   echo $GH_PAT | docker login ghcr.io -u <your-github-username> --password-stdin
   docker pull ghcr.io/<your-github-username>/actions-runner-flutter:latest
   ```

5. **Create containers** (see SYNOLOGY.md for full commands)

### Updating Synology Runners

1. Edit `update-synology-runners.sh` with your credentials
2. Upload to Synology
3. Run:
   ```bash
   bash update-synology-runners.sh
   ```

---

## Rebuilding the Image

Rebuild whenever you want to pick up:
- New Flutter stable release
- Chrome/ChromeDriver updates
- Android SDK updates
- Security patches

```powershell
# On Windows
.\build-and-push.ps1 <your-github-username>

# Then update local runners
.\update-runners.ps1

# And update Synology runners (via SSH)
bash update-synology-runners.sh
```

The Dockerfile automatically fetches the **latest stable Flutter version** at build time - no manual version bumping needed.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  GitHub Repository                                          │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Actions Workflow                                    │   │
│  │  runs-on: [self-hosted, Linux, X64]                 │   │
│  └─────────────────────────────────────────────────────┘   │
└──────────────────────────┬──────────────────────────────────┘
                           │
         ┌─────────────────┴─────────────────┐
         ▼                                   ▼
┌─────────────────────┐           ┌─────────────────────┐
│  Windows Desktop    │           │  Synology NAS       │
│  (docker-compose)   │           │  (docker run)       │
│                     │           │                     │
│  runner-1           │           │  gh-runner-1        │
│  runner-2           │           │  gh-runner-2        │
│  runner-3           │           │                     │
│  runner-4           │           │                     │
└─────────────────────┘           └─────────────────────┘
```

### Key Features

- **Ephemeral runners**: Auto-deregister after each job for clean state
- **Persistent caches**: pub, npm, pnpm, Flutter caches survive restarts
- **Docker-in-Docker**: Host Docker socket mounted for container workflows
- **KVM acceleration**: Hardware-accelerated Android emulator (desktop only)

---

## Troubleshooting

### Runners not appearing in GitHub
- Verify PAT has `repo` and `workflow` scopes
- Check Actions are enabled: Repo → Settings → Actions → General
- Check logs: `docker compose logs` or `docker logs gh-runner-1`

### Container exits immediately
```powershell
docker compose logs
# or
docker logs gh-runner-1
```
Common causes:
- Invalid/expired GitHub PAT
- Repository doesn't exist or Actions disabled
- Network connectivity issues

### Permission denied on Synology
```bash
chmod +x /volume1/gh-runner/register-and-run.sh
sudo chown -R 1001:1001 /volume1/gh-runner
```

### Image won't push to GHCR
```powershell
# Login first (will prompt for password - use your PAT)
docker login ghcr.io -u <your-github-username>
```
Ensure PAT has `write:packages` scope.

---

## Slack Notifications for Updates

A GitHub Actions workflow checks daily for new versions of Flutter and the actions-runner base image, and sends you a Slack notification when updates are available.

### Setup

1. **Create a Slack Webhook:**
   - Go to https://api.slack.com/apps → Create New App → From scratch
   - Enable "Incoming Webhooks" → Add New Webhook to Workspace
   - Copy the webhook URL

2. **Add GitHub Secrets:**
   - Go to your repo → Settings → Secrets and variables → Actions
   - Add secret: `SLACK_WEBHOOK_URL` = your webhook URL
   - (Optional) Add secret: `GH_PAT_VARS` = a PAT with `repo` scope for version tracking

3. **Enable the workflow:**
   - The workflow runs daily at 9 AM UTC
   - You can also trigger it manually from Actions → Check for Updates → Run workflow

### What it checks

- **Flutter**: Queries Flutter's releases API for the latest stable version
- **actions-runner**: Checks GHCR for new image versions

When updates are detected, you'll get a Slack message like:

> 🔄 **GitHub Actions Runner Image Updates Available**
> • Flutter: 3.24.0 → 3.25.0
> 
> Rebuild your runner image to get the latest versions:
> ```./build-and-push.ps1```

---

## Runner Offline Monitoring & Slack Alerts

Get notified via Slack whenever your GitHub Actions runners go offline. The monitoring script checks runner status periodically and sends alerts when runners transition from online to offline.

### Setup

1. **Ensure you have a Slack Webhook URL:**
   - If you already set up `SLACK_WEBHOOK_URL` for update notifications, you can reuse it
   - Otherwise, create one at https://api.slack.com/apps → Create New App → From scratch
   - Enable "Incoming Webhooks" → Add New Webhook to Workspace
   - Copy the webhook URL

2. **Add to your `.env` file:**
   ```env
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/YOUR/WEBHOOK/URL
   ```
   (The script will also read `GH_OWNER`, `GH_REPO`, and `GH_PAT` from `.env`)

3. **Set up automated monitoring:**
   ```powershell
   .\setup-monitor.ps1 -IntervalMinutes 5
   ```
   This creates a Windows Task Scheduler task that checks runner status every 5 minutes (adjustable).

### Manual Monitoring

You can also run the monitor manually:
```powershell
.\monitor-runners.ps1
```

Or with a custom Slack webhook:
```powershell
.\monitor-runners.ps1 -SlackWebhookUrl "https://hooks.slack.com/services/YOUR/WEBHOOK/URL"
```

### How It Works

- The script queries the GitHub API to get current runner status
- It compares current status with the previous check (stored in `.runner-state.json`)
- When a runner transitions from `online` to `offline`, a Slack alert is sent
- The alert includes runner name, OS, architecture, and labels
- State is persisted between runs to detect transitions

### Slack Alert Example

When a runner goes offline, you'll receive a Slack message like:

> ⚠️ **GitHub Actions Runner Offline**
> 
> The following runner(s) have gone *offline*:
> 
> • *my-runner-1* (OS: Linux, Arch: X64, Labels: self-hosted, Linux, X64)
> 
> **Repository:** your-username/your-repo  
> **Time:** 2024-01-15 14:30:00 UTC
> 
> [View Runners] button

### Managing the Scheduled Task

- **View task:** Open Task Scheduler → Task Scheduler Library → `GitHubActionsRunnerMonitor`
- **Remove task:**
  ```powershell
  Unregister-ScheduledTask -TaskName "GitHubActionsRunnerMonitor" -Confirm:$false
  ```
- **Modify interval:** Re-run `setup-monitor.ps1` with a different `-IntervalMinutes` value

### Troubleshooting

- **No alerts received:** Check that `SLACK_WEBHOOK_URL` is set correctly in `.env`
- **Script fails:** Ensure `GH_PAT` has `repo` scope and Actions are enabled for the repository
- **State file issues:** Delete `.runner-state.json` to reset state tracking

---

## Files Reference

| File | Purpose |
|------|---------|
| `Dockerfile.runner` | Runner image definition |
| `docker-compose.yml` | Multi-runner orchestration (desktop) |
| `register-and-run.sh` | Container entrypoint script |
| `build-and-push.ps1` | Build and push image to GHCR |
| `start-runners.ps1` | Start runners (for Task Scheduler) |
| `update-runners.ps1` | Pull latest image and restart |
| `update-synology-runners.sh` | Update script for Synology |
| `monitor-runners.ps1` | Monitor runner status and send Slack alerts |
| `setup-monitor.ps1` | Set up scheduled monitoring task |
| `.github/workflows/check-updates.yml` | Daily update checker with Slack notifications |
| `SYNOLOGY.md` | Detailed Synology setup guide |

