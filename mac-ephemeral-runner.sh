#!/usr/bin/env bash
set -euo pipefail

# Run one native macOS Actions job per registration, then re-register with a
# fresh token. The listener itself is never reused across jobs.

: "${GH_OWNER:?GH_OWNER is required}"
: "${RUNNER_NAME:?RUNNER_NAME is required}"
: "${RUNNER_GROUP:?RUNNER_GROUP is required}"
: "${RUNNER_DIR:?RUNNER_DIR is required}"
: "${RUNNER_LABELS:?RUNNER_LABELS is required}"

RUNNER_HOME="${RUNNER_HOME:-$HOME}"
GH_REPO="${GH_REPO:-}"
GH_HOST="${GH_HOST:-github.com}"
PATH="${PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin}"
export PATH RUNNER_HOME

if [[ -n "$GH_REPO" ]]; then
  RUNNER_URL="https://${GH_HOST}/${GH_OWNER}/${GH_REPO}"
  REGISTRATION_ENDPOINT="https://api.${GH_HOST}/repos/${GH_OWNER}/${GH_REPO}/actions/runners/registration-token"
else
  RUNNER_URL="https://${GH_HOST}/${GH_OWNER}"
  REGISTRATION_ENDPOINT="https://api.${GH_HOST}/orgs/${GH_OWNER}/actions/runners/registration-token"
fi

GH_BIN="${GH_BIN:-$(command -v gh || true)}"
if [[ -z "$GH_BIN" || ! -x "$GH_BIN" ]]; then
  echo "[mac-runner] FATAL: gh CLI is required to read the host keychain token" >&2
  exit 1
fi

cd "$RUNNER_DIR"

shutdown_requested=0
child_pid=""

shutdown() {
  shutdown_requested=1
  if [[ -n "$child_pid" ]]; then
    kill -TERM "$child_pid" 2>/dev/null || true
  fi
}
trap shutdown SIGTERM SIGINT

cleanup_runner_state() {
  # _work contains the checkout, tool caches created by actions, and temp
  # files. It is disposable and is bounded after every completed job.
  if [[ -d "$RUNNER_DIR/_work" ]]; then
    find "$RUNNER_DIR/_work" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
  fi

  # Keep only a bounded diagnostic history. The active listener has already
  # exited when this function runs.
  if [[ -d "$RUNNER_DIR/_diag" ]]; then
    find "$RUNNER_DIR/_diag" -type f -mtime +14 -delete 2>/dev/null || true
  fi
}

registration_token() {
  local token response
  token="$($GH_BIN auth token --hostname "$GH_HOST")"
  [[ -n "$token" ]] || { echo "[mac-runner] no GitHub token available" >&2; return 1; }
  response="$(curl -fsS --max-time 30 \
    -H "Authorization: Bearer ${token}" \
    -H 'Accept: application/vnd.github+json' \
    -H 'X-GitHub-Api-Version: 2022-11-28' \
    -H 'User-Agent: spinfreeze-native-runner' \
    -X POST "$REGISTRATION_ENDPOINT")"
  jq -er .token <<<"$response"
}

echo "[mac-runner] org=${GH_OWNER} repo=${GH_REPO:-<organization>} name=${RUNNER_NAME} group=${RUNNER_GROUP}"
echo "[mac-runner] runner_dir=${RUNNER_DIR} labels=${RUNNER_LABELS}"

iteration=0
while (( shutdown_requested == 0 )); do
  iteration=$((iteration + 1))
  echo "[mac-runner] iteration=${iteration}: fetching registration token"

  if ! reg_token="$(registration_token)"; then
    echo "[mac-runner] token request failed; retrying in 30s" >&2
    sleep 30
    continue
  fi

  # The previous ephemeral listener leaves local metadata behind after a
  # normal job exit. It must not be reused for the next registration.
  rm -f .runner .credentials .credentials_rsaparams .env .path 2>/dev/null || true

  if ! ./config.sh \
    --ephemeral \
    --unattended \
    --replace \
    --url "$RUNNER_URL" \
    --token "$reg_token" \
    --name "$RUNNER_NAME" \
    --labels "$RUNNER_LABELS" \
    --runnergroup "$RUNNER_GROUP"; then
    echo "[mac-runner] config.sh failed; retrying in 30s" >&2
    sleep 30
    continue
  fi

  echo "[mac-runner] waiting for one ephemeral job"
  set +e
  ./run.sh &
  child_pid=$!
  wait "$child_pid"
  run_status=$?
  child_pid=""
  set -e

  cleanup_runner_state
  echo "[mac-runner] listener exited status=${run_status}; disposable state cleaned"

  if (( shutdown_requested == 1 )); then
    break
  fi
  sleep 5
done

cleanup_runner_state
echo "[mac-runner] stopped"
