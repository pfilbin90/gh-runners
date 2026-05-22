#!/usr/bin/env bash
#
# Installs / updates cursor-agent in the shared Docker volume used by GitHub
# Actions runners on macOS / Linux hosts. Mirrors update-cursor-agent.ps1.
#
# Picks a running runner container, downloads the cursor-agent tarball
# (version pinned inside the official cursor.com/install script), extracts
# it into the `cursor-agent` Docker volume at /opt/cursor-agent/dist, and
# symlinks /opt/cursor-agent/bin/{cursor-agent,agent} so workflows find it
# on PATH (the runner image's PATH includes /opt/cursor-agent/bin).
#
# Schedule via launchd or cron, e.g. every 6 hours:
#   0 */6 * * * /Users/pete/repos/gh-runners/update-cursor-agent.sh \
#     >> /Users/pete/repos/gh-runners/cursor-agent-update.log 2>&1
#
# Workflows must export CURSOR_API_KEY for cursor-agent to authenticate at
# runtime; this script only installs the binary.

set -euo pipefail

LOG_FILE="$(cd "$(dirname "$0")" && pwd)/cursor-agent-update.log"

log() {
  local ts
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '[%s] %s\n' "$ts" "$*" | tee -a "$LOG_FILE"
}

log "Starting cursor-agent update..."

CONTAINER=$(docker ps --filter "name=gh-runners-runner" --format "{{.Names}}" | head -n 1)
if [ -z "$CONTAINER" ]; then
  log "ERROR: No running runner container found. Ensure runners are running."
  exit 1
fi
log "Using container: $CONTAINER"

# Bash payload runs inside the runner container. Detects OS/arch and pulls
# the matching tarball from Cursor's downloads.cursor.com. This is the
# byte-for-byte equivalent of the payload in update-cursor-agent.ps1.
read -r -d '' BASH_PAYLOAD <<'PAYLOAD' || true
#!/usr/bin/env bash
set -euo pipefail

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

# Atomic swap: stage in tmp, then mv into place. Avoids leaving a
# half-extracted tree at /opt/cursor-agent/dist if the download is
# interrupted mid-tar.
STAGE=/opt/cursor-agent/dist.new
rm -rf "$STAGE"
mv "$TMPDIR" "$STAGE"
trap - EXIT

rm -rf /opt/cursor-agent/dist
mv "$STAGE" /opt/cursor-agent/dist

ln -sf /opt/cursor-agent/dist/cursor-agent /opt/cursor-agent/bin/cursor-agent
ln -sf /opt/cursor-agent/dist/cursor-agent /opt/cursor-agent/bin/agent

# The Cursor tarball ships /opt/cursor-agent/dist with mode 700, but workflow
# steps run as the `runner` user (not root) and need to traverse it to follow
# the symlinks above. Open up read+traverse for everyone.
chmod 0755 /opt/cursor-agent /opt/cursor-agent/bin /opt/cursor-agent/dist
chmod -R a+rX /opt/cursor-agent/dist

if [ ! -x /opt/cursor-agent/bin/cursor-agent ]; then
    echo "cursor-agent binary not executable after install." >&2
    exit 1
fi
/opt/cursor-agent/bin/cursor-agent --version || true
echo "cursor-agent ${VERSION} installed."
PAYLOAD

# Base64-encode to dodge shell -> docker exec -> bash quoting layers.
ENCODED=$(printf '%s' "$BASH_PAYLOAD" | base64 | tr -d '\n')

if ! OUTPUT=$(docker exec "$CONTAINER" bash -c "echo $ENCODED | base64 -d | bash" 2>&1); then
  log "ERROR: Install payload failed:"
  log "$OUTPUT"
  exit 1
fi
log "Install output:"
log "$OUTPUT"

VERSION_OUT=$(docker exec "$CONTAINER" bash -c '/opt/cursor-agent/bin/cursor-agent --version' 2>&1 || true)
log "cursor-agent version: $VERSION_OUT"
log "cursor-agent update completed successfully."
