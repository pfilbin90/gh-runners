#!/usr/bin/env bash
set -euo pipefail

# Install two org-scoped, one-job-at-a-time native Mac runners and a periodic
# idle-only cleanup agent. Existing repository-scoped runner services with the
# same directories are removed before the new registrations are started.

: "${GH_OWNER:?GH_OWNER is required}"
: "${GH_REPO:?GH_REPO is required for removing the old repository runner}"
: "${RUNNER_HOME:?RUNNER_HOME is required}"
: "${RUNNER_SCRIPTS_DIR:?RUNNER_SCRIPTS_DIR is required}"
: "${SHARED_RUNNER_DIR:?SHARED_RUNNER_DIR is required}"
: "${PRODUCTION_RUNNER_DIR:?PRODUCTION_RUNNER_DIR is required}"

GH_HOST="${GH_HOST:-github.com}"
LAUNCH_AGENTS_DIR="$RUNNER_HOME/Library/LaunchAgents"
LOG_ROOT="$RUNNER_HOME/Library/Logs"
SHARED_LABEL="${SHARED_LABEL:-spinfreeze-macos-shared}"
PRODUCTION_LABEL="${PRODUCTION_LABEL:-spinfreeze-macos-production}"
MAC_LABELS="${MAC_LABELS:-self-hosted,macOS,ARM64,spinfreeze,ios,xcode-26,flutter}"

SHARED_LABEL_NAME="actions.runner.SpinFreezeApp-spinfreeze_app.spinfreeze-mac-1"
PRODUCTION_LABEL_NAME="actions.runner.SpinFreezeApp-spinfreeze_app.spinfreeze-mac-2"
CLEANUP_LABEL_NAME="spinfreeze.native-resource-cleanup"

mkdir -p "$LAUNCH_AGENTS_DIR" "$LOG_ROOT/$SHARED_LABEL_NAME" "$LOG_ROOT/$PRODUCTION_LABEL_NAME" "$LOG_ROOT/$CLEANUP_LABEL_NAME"

stop_agent() {
  local label="$1" plist="$LAUNCH_AGENTS_DIR/${label}.plist"
  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
}

stop_agent "$SHARED_LABEL_NAME"
stop_agent "$PRODUCTION_LABEL_NAME"

# Current runners were repository-scoped. Remove those registrations while the
# old persistent listeners are stopped; the new loop registers at org scope.
repo_remove_token="$(gh api --method POST "repos/${GH_OWNER}/${GH_REPO}/actions/runners/remove-token" --jq .token)"
for runner_dir in "$SHARED_RUNNER_DIR" "$PRODUCTION_RUNNER_DIR"; do
  if [[ -f "$runner_dir/.runner" ]]; then
    (cd "$runner_dir" && ./config.sh remove --unattended --token "$repo_remove_token") || true
  fi
done

write_runner_plist() {
  local plist="$1" label="$2" name="$3" dir="$4" group="$5" extra_label="$6" log_dir="$7"
  cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key><string>${label}</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>${RUNNER_SCRIPTS_DIR}/mac-ephemeral-runner.sh</string>
    </array>
    <key>WorkingDirectory</key><string>${dir}</string>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key><true/>
    <key>ThrottleInterval</key><integer>30</integer>
    <key>ProcessType</key><string>Background</string>
    <key>LowPriorityIO</key><true/>
    <key>StandardOutPath</key><string>${log_dir}/stdout.log</string>
    <key>StandardErrorPath</key><string>${log_dir}/stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
      <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
      <key>GH_OWNER</key><string>${GH_OWNER}</string>
      <key>RUNNER_NAME</key><string>${name}</string>
      <key>RUNNER_GROUP</key><string>${group}</string>
      <key>RUNNER_DIR</key><string>${dir}</string>
      <key>RUNNER_HOME</key><string>${RUNNER_HOME}</string>
      <key>RUNNER_LABELS</key><string>${MAC_LABELS},${extra_label}</string>
    </dict>
  </dict>
</plist>
EOF
}

write_runner_plist "$LAUNCH_AGENTS_DIR/${SHARED_LABEL_NAME}.plist" "$SHARED_LABEL_NAME" \
  spinfreeze-mac-1 "$SHARED_RUNNER_DIR" spinfreeze-macos-shared "$SHARED_LABEL" "$LOG_ROOT/$SHARED_LABEL_NAME"
write_runner_plist "$LAUNCH_AGENTS_DIR/${PRODUCTION_LABEL_NAME}.plist" "$PRODUCTION_LABEL_NAME" \
  spinfreeze-mac-2 "$PRODUCTION_RUNNER_DIR" spinfreeze-macos-production "$PRODUCTION_LABEL" "$LOG_ROOT/$PRODUCTION_LABEL_NAME"

cat >"$LAUNCH_AGENTS_DIR/${CLEANUP_LABEL_NAME}.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key><string>${CLEANUP_LABEL_NAME}</string>
    <key>ProgramArguments</key>
    <array>
      <string>/bin/bash</string>
      <string>${RUNNER_SCRIPTS_DIR}/mac-resource-cleanup.sh</string>
    </array>
    <key>StartInterval</key><integer>21600</integer>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>${LOG_ROOT}/${CLEANUP_LABEL_NAME}/stdout.log</string>
    <key>StandardErrorPath</key><string>${LOG_ROOT}/${CLEANUP_LABEL_NAME}/stderr.log</string>
    <key>EnvironmentVariables</key>
    <dict>
      <key>PATH</key><string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
      <key>GH_OWNER</key><string>${GH_OWNER}</string>
      <key>RUNNER_NAMES</key><string>spinfreeze-mac-1,spinfreeze-mac-2</string>
      <key>RUNNER_DIRS</key><string>${SHARED_RUNNER_DIR},${PRODUCTION_RUNNER_DIR}</string>
      <key>RUNNER_HOME</key><string>${RUNNER_HOME}</string>
    </dict>
  </dict>
</plist>
EOF

for label in "$SHARED_LABEL_NAME" "$PRODUCTION_LABEL_NAME" "$CLEANUP_LABEL_NAME"; do
  launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENTS_DIR/${label}.plist"
done

echo "Installed org-scoped ephemeral Mac runners and idle-only cleanup agent."
