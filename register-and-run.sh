#!/usr/bin/env bash
set -euo pipefail

: "${GH_OWNER:?}"
: "${GH_PAT:?}"
: "${GH_REPO:=}"  # Optional - leave empty for org-level registration
: "${RUNNER_LABELS:=self-hosted,Linux,X64}"
: "${RUNNER_NAME:=runner-$(hostname)-$$}"
: "${RUNNER_GROUP:=Default}"

# Determine if org-level or repo-level registration
if [ -z "$GH_REPO" ]; then
  API="https://api.github.com/orgs/${GH_OWNER}/actions/runners/registration-token"
  RUNNER_URL="https://github.com/${GH_OWNER}"
  echo "[runner] starting; org=${GH_OWNER} labels=${RUNNER_LABELS} group=${RUNNER_GROUP}"
else
  API="https://api.github.com/repos/${GH_OWNER}/${GH_REPO}/actions/runners/registration-token"
  RUNNER_URL="https://github.com/${GH_OWNER}/${GH_REPO}"
  echo "[runner] starting; repo=${GH_OWNER}/${GH_REPO} labels=${RUNNER_LABELS} group=${RUNNER_GROUP}"
fi

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

# --- Main loop: re-register and run after each ephemeral job completes ---
# Instead of exiting and relying on Docker’s restart policy (which causes
# full container lifecycle churn and makes com.docker.backend burn CPU),
# we loop inside the container. The ephemeral runner exits after one job,
# then we re-register with a fresh token and start again.
ITERATION=0

cleanup() {
  echo "[runner] received shutdown signal, exiting loop ..."
  exit 0
}
trap cleanup SIGTERM SIGINT

while true; do
  ITERATION=$((ITERATION + 1))
  echo "[runner] === iteration $ITERATION ==="

  # --- Get a fresh registration token ---
  echo "[runner] fetching registration token ..."
  HTTP=$(curl -fsS --max-time 30 -w "%{http_code}" -D /tmp/h -o /tmp/b -X POST \
    -H "Authorization: token ${GH_PAT}" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    -H "User-Agent: spinfreeze-runner" \
    "${API}" || true)

  if [ "$HTTP" != "201" ]; then
    echo "[runner] GitHub API http=$HTTP"
    echo "--- RESPONSE HEADERS ---"; cat /tmp/h || true
    echo "--- RESPONSE BODY ---"; cat /tmp/b || true
    echo "[runner] If http=404, ensure Actions are enabled for the repo (Settings > Actions)."
    echo "[runner] retrying in 30s ..."
    sleep 30
    continue
  fi
  REG_TOKEN=$(jq -r .token < /tmp/b)

  # --- Clean up stale configuration from previous ephemeral runs ---
  if [ -f ".runner" ]; then
    echo "[runner] cleaning up stale configuration files ..."
    rm -f .runner .credentials .credentials_rsaparams .env .path 2>/dev/null || true
  fi

  # --- Configure ephemeral runner ---
  if ! ./config.sh \
    --ephemeral \
    --unattended \
    --replace \
    --url "${RUNNER_URL}" \
    --token "${REG_TOKEN}" \
    --name "${RUNNER_NAME}" \
    --labels "${RUNNER_LABELS}" \
    --runnergroup "${RUNNER_GROUP}"; then
    echo "[runner] config.sh failed, retrying in 30s ..."
    sleep 30
    continue
  fi

  echo "[runner] listening for jobs ..."
  ./run.sh || true

  echo "[runner] run exited, re-registering in 5s ..."
  sleep 5
done