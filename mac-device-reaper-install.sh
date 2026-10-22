#!/usr/bin/env bash
set -euo pipefail

# Install the device reaper on a dev Mac: links mac-device-reaper.sh into
# ~/.local/bin/device-reaper and loads two launch agents (every 5 min, and a
# 3am sweep). The Claude Code SessionStart/SessionEnd hooks that call
# `device-reaper session-start|session-end` live in ~/.claude/settings.json.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN="$HOME/.local/bin/device-reaper"
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
LOG_DIR="$HOME/Library/Logs"

mkdir -p "$(dirname "$BIN")" "$LAUNCH_AGENTS_DIR" "$LOG_DIR"
ln -sf "$SCRIPT_DIR/mac-device-reaper.sh" "$BIN"

write_agent() {
  local label="$1" mode="$2" schedule="$3"
  local plist="$LAUNCH_AGENTS_DIR/${label}.plist"
  launchctl bootout "gui/$(id -u)" "$plist" >/dev/null 2>&1 || true
  cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
  <dict>
    <key>Label</key><string>${label}</string>
    <key>ProgramArguments</key>
    <array><string>${BIN}</string><string>${mode}</string></array>
    ${schedule}
    <key>StandardErrorPath</key><string>${LOG_DIR}/device-reaper.err.log</string>
  </dict>
</plist>
PLIST
  launchctl bootstrap "gui/$(id -u)" "$plist"
}

write_agent com.pete.device-reaper reap \
  '<key>StartInterval</key><integer>300</integer>
    <key>RunAtLoad</key><true/>'
write_agent com.pete.device-reaper.nightly nightly \
  '<key>StartCalendarInterval</key><dict><key>Hour</key><integer>3</integer><key>Minute</key><integer>0</integer></dict>'

echo "Installed device-reaper. Dry run: device-reaper status"
