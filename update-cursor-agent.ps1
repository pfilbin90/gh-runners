<#
.SYNOPSIS
    Installs / updates cursor-agent in the shared Docker volume used by GitHub
    Actions runners.

.DESCRIPTION
    Mirrors update-claude-code.ps1. Downloads the latest cursor-agent tarball
    (version pinned inside the official cursor.com/install script) and extracts
    it into the cursor-agent Docker volume at /opt/cursor-agent/dist, then
    symlinks the binary at /opt/cursor-agent/bin/cursor-agent so workflows can
    find it on PATH.

.NOTES
    Schedule via Task Scheduler:
    1. Open Task Scheduler
    2. Create Basic Task -> "Update Cursor Agent"
    3. Trigger: Daily, repeat every 6 hours
    4. Action: Start a program
       Program: powershell.exe
       Arguments: -ExecutionPolicy Bypass -File "C:\repos\gh-runners\update-cursor-agent.ps1"
    5. Finish

    Workflows must export CURSOR_API_KEY for cursor-agent to authenticate at
    runtime; this script only installs the binary.
#>

$ErrorActionPreference = "Stop"

$logFile = Join-Path $PSScriptRoot "cursor-agent-update.log"
$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

function Write-Log {
    param([string]$Message)
    $entry = "[$timestamp] $Message"
    Write-Host $entry
    Add-Content -Path $logFile -Value $entry
}

Write-Log "Starting cursor-agent update..."

$container = docker ps --filter "name=gh-runners-runner" --format "{{.Names}}" | Select-Object -First 1

if (-not $container) {
    Write-Log "ERROR: No running runner container found. Ensure runners are running."
    exit 1
}

Write-Log "Using container: $container"

# Bash payload runs inside the runner container. Base64-encoded to dodge
# PowerShell -> docker exec -> bash quoting layers.
$bashScript = @'
#!/usr/bin/env bash
set -euo pipefail

# Pull the official installer and extract the pinned version + download URL
# pattern from it. Cursor bakes the version into the script itself, so this
# is the canonical "latest" pointer.
INSTALL_SCRIPT=$(curl -fsSL https://cursor.com/install)
VERSION=$(printf '%s\n' "$INSTALL_SCRIPT" \
    | grep -oE 'lab/[0-9]{4}\.[0-9]{2}\.[0-9]{2}-[a-f0-9]+' \
    | head -n1 \
    | cut -d/ -f2)

if [ -z "$VERSION" ]; then
    echo "Failed to detect cursor-agent version from installer." >&2
    exit 1
fi

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
    linux|darwin) ;;
    *) echo "Unsupported OS: $OS" >&2; exit 1 ;;
esac

ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) ARCH=x64 ;;
    arm64|aarch64) ARCH=arm64 ;;
    *) echo "Unsupported arch: $ARCH" >&2; exit 1 ;;
esac

DOWNLOAD_URL="https://downloads.cursor.com/lab/${VERSION}/${OS}/${ARCH}/agent-cli-package.tar.gz"
echo "Installing cursor-agent ${VERSION} (${OS}/${ARCH})"
echo "URL: ${DOWNLOAD_URL}"

mkdir -p /opt/cursor-agent/bin
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

curl -fSL "$DOWNLOAD_URL" \
  | tar --strip-components=1 -xzf - -C "$TMPDIR"

# Atomic swap: stage in tmp, then mv into place. Avoids leaving a half-extracted
# tree at /opt/cursor-agent/dist if the download is interrupted mid-tar.
STAGE=/opt/cursor-agent/dist.new
rm -rf "$STAGE"
mv "$TMPDIR" "$STAGE"
trap - EXIT

rm -rf /opt/cursor-agent/dist
mv "$STAGE" /opt/cursor-agent/dist

ln -sf /opt/cursor-agent/dist/cursor-agent /opt/cursor-agent/bin/cursor-agent
ln -sf /opt/cursor-agent/dist/cursor-agent /opt/cursor-agent/bin/agent

# Verify
if [ ! -x /opt/cursor-agent/bin/cursor-agent ]; then
    echo "cursor-agent binary not executable after install." >&2
    exit 1
fi
/opt/cursor-agent/bin/cursor-agent --version || true
echo "cursor-agent ${VERSION} installed."
'@

try {
    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($bashScript))
    $output = docker exec $container bash -c "echo $encoded | base64 -d | bash" 2>&1
    Write-Log "Install output:`n$output"

    $version = docker exec $container bash -c '/opt/cursor-agent/bin/cursor-agent --version' 2>&1
    Write-Log "cursor-agent version: $version"

    Write-Log "cursor-agent update completed successfully."
} catch {
    Write-Log "ERROR: Failed to update cursor-agent: $_"
    exit 1
}
