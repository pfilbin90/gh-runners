#!/usr/bin/env bash
set -euo pipefail

: "${GH_OWNER:?}"
: "${GH_REPO:?}"
: "${GH_PAT:?}"
: "${RUNNER_LABELS:=self-hosted,Windows,X64}"
: "${RUNNER_NAME:=spinfreeze-$(hostname)-$$}"
: "${RUNNER_GROUP:=Default}"

API="https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/actions/runners/registration-token"

echo "[runner] starting; repo=${GH_OWNER}/${GH_REPO} labels=${RUNNER_LABELS} group=${RUNNER_GROUP}"

# --- Get a fresh registration token ---
echo "[runner] fetching registration token ..."
HTTP=$(curl -fsS -w "%{http_code}" -D /tmp/h -o /tmp/b -X POST \
  -H "Authorization: token ${GH_PAT}" \
  -H "Accept: application/vnd.github+json" \
  -H "X-GitHub-Api-Version: 2022-11-28" \
  -H "User-Agent: spinfreeze-runner" \
  "${API}" || true)

if [ "$HTTP" != "201" ]; then
  echo "[runner] GitHub API http=$HTTP"
  echo "--- RESPONSE HEADERS ---"; cat /tmp/h || true
  echo "--- RESPONSE BODY ---"; cat /tmp/b || true
  echo "[runner] If http=404, ensure Actions are enabled for the repo (Settings → Actions)."
  exit 1
fi
REG_TOKEN=$(jq -r .token < /tmp/b)


# --- Locate config.sh (varies by image/tag) ---
CANDIDATES=(
  "/home/runner/actions-runner"
  "/actions-runner"
  "/home/runner"
  "/"
)
RUNNER_DIR=""
for d in "${CANDIDATES[@]}"; do
  if [ -f "$d/config.sh" ]; then
    RUNNER_DIR="$d"
    break
  fi
done
if [ -z "$RUNNER_DIR" ]; then
  # last resort: search shallowly (cheap)
  found=$(find / -maxdepth 3 -type f -name config.sh 2>/dev/null | head -n1 || true)
  if [ -n "$found" ]; then
    RUNNER_DIR="$(dirname "$found")"
  fi
fi

if [ -z "$RUNNER_DIR" ]; then
  echo "[runner] FATAL: could not locate config.sh in known paths."
  echo "[runner] Debug listing under /home/runner:"
  ls -lah /home/runner || true
  echo "[runner] Debug listing under /:"
  ls -lah / || true
  exit 1
fi

echo "[runner] using RUNNER_DIR=$RUNNER_DIR"
cd "$RUNNER_DIR"
export RUNNER_ALLOW_RUNASROOT=1

# --- Clean up stale configuration from previous ephemeral runs ---
# Ephemeral runners deregister from GitHub after completing a job, but
# local config files may persist if the container restarts without being
# fully recreated. The --replace flag only works if the runner is still
# registered with GitHub, so we must remove orphaned local config first.
if [ -f ".runner" ]; then
  echo "[runner] cleaning up stale configuration files ..."
  rm -f .runner .credentials .credentials_rsaparams .env .path 2>/dev/null || true
fi

# --- Configure ephemeral runner ---
./config.sh \
  --ephemeral \
  --unattended \
  --replace \
  --url "https://github.com/${GH_OWNER}/${GH_REPO}" \
  --token "${REG_TOKEN}" \
  --name "${RUNNER_NAME}" \
  --labels "${RUNNER_LABELS}" \
  --runnergroup "${RUNNER_GROUP}"

echo "[runner] starting run loop ..."
exec ./run.sh