# Synology NAS Setup Guide

This guide explains how to run the GitHub Actions runners on a Synology NAS using existing shared folders.

## Prerequisites

- Synology NAS with Docker/Container Manager installed
- SSH access to your Synology NAS
- GitHub Personal Access Token (PAT) with `repo` and `workflow` scopes
- Pre-built image pushed to GitHub Container Registry (GHCR)

## Initial Setup

### 1. Create Shared Folders

Create two shared folders via DSM File Station:
- `gh-runner`
- `gh-runner2`

These will be automatically mounted at `/volume1/gh-runner` and `/volume1/gh-runner2`

### 2. Create Directory Structure

SSH into your Synology and create the cache directories:

```bash
ssh admin@your-nas-ip

# Create cache subdirectories for runner 1
sudo mkdir -p /volume1/gh-runner/{work,pub-cache,npm-cache,pnpm-store,flutter-cache}

# Create cache subdirectories for runner 2
sudo mkdir -p /volume1/gh-runner2/{work,pub-cache,npm-cache,pnpm-store,flutter-cache}

# Set proper permissions (runner uses UID 1001)
sudo chown -R 1001:1001 /volume1/gh-runner /volume1/gh-runner2
```

### 3. Upload Registration Script

Upload `register-and-run.sh` to both shared folders:

**Option A: Using SCP from your local machine**
```bash
scp register-and-run.sh admin@your-nas-ip:/volume1/gh-runner/
scp register-and-run.sh admin@your-nas-ip:/volume1/gh-runner2/
```

**Option B: Using Synology File Station**
1. Open File Station in DSM
2. Navigate to `gh-runner` folder
3. Upload `register-and-run.sh`
4. Repeat for `gh-runner2` folder

### 4. Set Script Permissions

SSH into Synology and make the scripts executable:

```bash
chmod +x /volume1/gh-runner/register-and-run.sh
chmod +x /volume1/gh-runner2/register-and-run.sh
```

### 5. Pull the Docker Image

Login to GHCR (if the image is private):

```bash
echo YOUR_GITHUB_PAT | docker login ghcr.io -u your-github-username --password-stdin
```

Pull the image:

```bash
docker pull ghcr.io/your-github-username/actions-runner-flutter:latest
```

### 6. Create Runner Containers

**Runner 1:**
```bash
docker run -d \
  --name gh-runner-1 \
  --restart always \
  -e GH_OWNER=your-github-username \
  -e GH_REPO=your-repo-name \
  -e GH_PAT=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  -e RUNNER_GROUP=Default \
  -e RUNNER_LABELS=self-hosted,Linux,X64 \
  -e RUNNER_NAME=synology-runner-1 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /volume1/gh-runner/register-and-run.sh:/home/runner/register-and-run.sh:ro \
  -v /volume1/gh-runner/work:/_work \
  -v /volume1/gh-runner/pub-cache:/home/runner/.pub-cache \
  -v /volume1/gh-runner/npm-cache:/home/runner/.npm \
  -v /volume1/gh-runner/pnpm-store:/home/runner/.local/share/pnpm \
  -v /volume1/gh-runner/flutter-cache:/home/runner/.cache/flutter \
  --entrypoint /bin/bash \
  ghcr.io/your-github-username/actions-runner-flutter:latest \
  -lc /home/runner/register-and-run.sh
```

**Runner 2:**
```bash
docker run -d \
  --name gh-runner-2 \
  --restart always \
  -e GH_OWNER=your-github-username \
  -e GH_REPO=your-repo-name \
  -e GH_PAT=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx \
  -e RUNNER_GROUP=Default \
  -e RUNNER_LABELS=self-hosted,Linux,X64 \
  -e RUNNER_NAME=synology-runner-2 \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v /volume1/gh-runner2/register-and-run.sh:/home/runner/register-and-run.sh:ro \
  -v /volume1/gh-runner2/work:/_work \
  -v /volume1/gh-runner2/pub-cache:/home/runner/.pub-cache \
  -v /volume1/gh-runner2/npm-cache:/home/runner/.npm \
  -v /volume1/gh-runner2/pnpm-store:/home/runner/.local/share/pnpm \
  -v /volume1/gh-runner2/flutter-cache:/home/runner/.cache/flutter \
  --entrypoint /bin/bash \
  ghcr.io/your-github-username/actions-runner-flutter:latest \
  -lc /home/runner/register-and-run.sh
```

### 7. Verify Runners

Check container status:
```bash
docker ps -a --filter name=gh-runner
```

Check logs:
```bash
docker logs gh-runner-1
docker logs gh-runner-2
```

Verify in GitHub:
- Go to your repository → Settings → Actions → Runners
- Both runners should appear as "Idle" (green)

## Updating to a New Image

When a new image is pushed to GHCR (either via the monthly rebuild workflow or manual build), follow these steps to update your Synology runners:

### Option 1: Using the Update Script (Recommended)

1. Download `update-synology-runners.sh` to your Synology (e.g., to `/volume1/docker/`)
2. Edit the configuration variables at the top of the script
3. Run it:

```bash
cd /volume1/docker
bash update-synology-runners.sh
```

### Option 2: Manual Update

1. **Pull the latest image:**
   ```bash
   docker pull ghcr.io/your-github-username/actions-runner-flutter:latest
   ```

2. **Stop and remove existing containers:**
   ```bash
   docker stop gh-runner-1 gh-runner-2
   docker rm gh-runner-1 gh-runner-2
   ```

3. **Recreate containers with the new image:**
   Run the same docker commands from step 6 of Initial Setup above.

4. **Verify the update:**
   ```bash
   docker ps -a --filter name=gh-runner
   docker logs --tail 20 gh-runner-1
   docker logs --tail 20 gh-runner-2
   ```

## Notes

- **KVM/Hardware Acceleration**: The Synology NAS likely doesn't support `/dev/kvm`, so it's omitted from the commands. Android emulator tests will run in software mode (slower but functional).

- **Persistent Caches**: All package caches (pub, npm, pnpm, Flutter) persist across container restarts in the shared folders, eliminating download time in workflows.

- **Ephemeral Runners**: Runners auto-deregister after each job (see `--ephemeral` flag in `register-and-run.sh`). This is intentional for security and ensures clean state for each job.

- **Docker-in-Docker**: The `/var/run/docker.sock` mount allows workflows to use Docker commands (building images, running containers, etc.).

## Troubleshooting

### Container exits immediately
Check logs: `docker logs gh-runner-1`
Common causes:
- Invalid GitHub PAT
- Repository doesn't have Actions enabled
- Network connectivity issues

### Permission denied on register-and-run.sh
Ensure the script is executable:
```bash
chmod +x /volume1/gh-runner/register-and-run.sh
chmod +x /volume1/gh-runner2/register-and-run.sh
```

### Runners not appearing in GitHub
- Verify environment variables are correct
- Check that Actions are enabled in repository settings
- Ensure PAT has `repo` and `workflow` scopes

### Cannot access shared folders
Shared folders are typically at `/volume1/<folder-name>`. If you have issues, find the actual path:
```bash
find /volume1 -name "register-and-run.sh" 2>/dev/null
```
