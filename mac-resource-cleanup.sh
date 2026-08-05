#!/usr/bin/env bash
set -euo pipefail

# Conservative host cleanup for native macOS runners. It only performs global
# cache cleanup after GitHub reports every managed Mac runner idle. Per-job
# checkout cleanup is handled by mac-ephemeral-runner.sh.

: "${GH_OWNER:?GH_OWNER is required}"
: "${RUNNER_NAMES:?RUNNER_NAMES is required (comma-separated)}"

RUNNER_HOME="${RUNNER_HOME:-$HOME}"
GH_HOST="${GH_HOST:-github.com}"
GH_BIN="${GH_BIN:-$(command -v gh || true)}"
RUNNER_DIRS="${RUNNER_DIRS:-}"
LOCK_DIR="${RUNNER_HOME}/.spinfreeze-runner-cleanup.lock"
GRADLE_MAX_GB="${GRADLE_MAX_GB:-5}"
DERIVED_DATA_MAX_GB="${DERIVED_DATA_MAX_GB:-10}"
LOG_MAX_MB="${LOG_MAX_MB:-25}"

PATH="${PATH:-/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin}"
export PATH RUNNER_HOME

if [[ -z "$GH_BIN" || ! -x "$GH_BIN" ]]; then
  echo "[mac-cleanup] gh CLI is required" >&2
  exit 1
fi

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "[mac-cleanup] another cleanup is already running"
  exit 0
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

runner_is_busy() {
  local runner_name="$1"
  "$GH_BIN" api "orgs/${GH_OWNER}/actions/runners" --paginate \
    --jq '.runners[] | select(.name == "'"$runner_name"'") | .busy' | grep -qx true
}

IFS=',' read -r -a managed_runners <<<"$RUNNER_NAMES"
for runner_name in "${managed_runners[@]}"; do
  if runner_is_busy "$runner_name"; then
    echo "[mac-cleanup] ${runner_name} is busy; skipping global cleanup"
    exit 0
  fi
done

dir_kb() {
  du -sk "$1" 2>/dev/null | awk 'NR { print $1+0; found=1 } END { if (!found) print 0 }'
}

gb_to_kb() {
  echo $(( $1 * 1024 * 1024 ))
}

remove_old_files() {
  local root="$1" days="$2"
  [[ -d "$root" ]] || return 0
  find "$root" -type f -mtime "+${days}" -print0 2>/dev/null |
    while IFS= read -r -d '' file; do
      # Do not remove a file still held open by a process that started after
      # the idle check. This is an extra guard against a race with scheduling.
      if ! lsof -t -- "$file" >/dev/null 2>&1; then
        rm -f -- "$file" 2>/dev/null || true
      fi
    done
}

prune_gradle() {
  local root="$RUNNER_HOME/.gradle" size limit
  size=$(dir_kb "$root")
  limit=$(gb_to_kb "$GRADLE_MAX_GB")
  if (( size >= limit )); then
    echo "[mac-cleanup] Gradle=${size}KB exceeds ${GRADLE_MAX_GB}GB; pruning disposable state"
    rm -rf "$root/caches" "$root/daemon" "$root/native" "$root/workers" 2>/dev/null || true
  fi
}

prune_derived_data() {
  local root="$RUNNER_HOME/Library/Developer/Xcode/DerivedData" size limit
  size=$(dir_kb "$root")
  limit=$(gb_to_kb "$DERIVED_DATA_MAX_GB")
  if (( size >= limit )); then
    echo "[mac-cleanup] DerivedData=${size}KB exceeds ${DERIVED_DATA_MAX_GB}GB; removing entries older than 14 days"
    find "$root" -mindepth 1 -maxdepth 1 -type d -mtime +14 -print0 2>/dev/null |
      while IFS= read -r -d '' entry; do
        if ! lsof +D "$entry" >/dev/null 2>&1; then
          rm -rf -- "$entry" 2>/dev/null || true
        fi
      done
  fi
}

rotate_logs() {
  local log_dir="$RUNNER_HOME/Library/Logs" max_kb=$((LOG_MAX_MB * 1024))
  [[ -d "$log_dir" ]] || return 0
  find "$log_dir" -type f -size "+${LOG_MAX_MB}M" -print0 2>/dev/null |
    while IFS= read -r -d '' file; do
      local temp="${file}.trim.$$"
      tail -c "$((max_kb * 1024))" "$file" >"$temp" 2>/dev/null && mv -- "$temp" "$file" || rm -f -- "$temp"
    done
}

if [[ -n "$RUNNER_DIRS" ]]; then
  IFS=',' read -r -a runner_dirs <<<"$RUNNER_DIRS"
  for runner_dir in "${runner_dirs[@]}"; do
    if [[ -d "$runner_dir/_work" ]]; then
      find "$runner_dir/_work" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null || true
    fi
    remove_old_files "$runner_dir/_diag" 14
  done
fi

prune_gradle
prune_derived_data
remove_old_files "$RUNNER_HOME/Library/Caches/CocoaPods" 30
remove_old_files "$RUNNER_HOME/.pub-cache" 30
rotate_logs
echo "[mac-cleanup] completed while all managed runners were idle"
