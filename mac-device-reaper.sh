#!/bin/bash
# device-reaper: shut down iOS simulators and Android emulators nothing is using.
#
# A device counts as "in use" while some process names it (flutter run -d <id>,
# xcodebuild, simctl io record, maestro --device, adb -s <id>, ...), or while a
# device-wide runner is active (maestro test, flutter drive/integration_test,
# xcodebuild test, a GitHub Actions job). Physical devices are never touched.
#
# Modes:
#   device-reaper                 reap devices idle for IDLE_MIN (launchd, every 5 min)
#   device-reaper nightly         reap every device not in use right now (launchd, 3am)
#   device-reaper session-start   Claude Code SessionStart hook: snapshot booted devices
#   device-reaper session-end     Claude Code SessionEnd hook: shut down what this session booted
#   device-reaper status          print what would happen, change nothing
#
# Pause everything for 12h:  touch ~/.keep-sims   (delete it to resume sooner)

set -u
export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin:$HOME/Library/Android/sdk/platform-tools"

IDLE_MIN="${DEVICE_REAPER_IDLE_MIN:-20}"
PRESSURE_IDLE_MIN="${DEVICE_REAPER_PRESSURE_IDLE_MIN:-5}"
KEEP_FILE="$HOME/.keep-sims"
KEEP_HOURS=12
STATE="$HOME/Library/Application Support/device-reaper"
LOG="$HOME/Library/Logs/device-reaper.log"
# CI's shared emulator AVD; never ours to stop.
PROTECTED_AVDS="test_avd"

mkdir -p "$STATE/last_used" "$STATE/sessions" "$(dirname "$LOG")"
MODE="${1:-reap}"
NOW=$(date +%s)
DRY=0
[[ "$MODE" == "status" ]] && DRY=1

log() {
  if [[ $DRY -eq 1 ]]; then echo "$*"; else echo "$(date '+%F %T') [$MODE] $*" >>"$LOG"; fi
}

# One process snapshot per run, minus processes that mention a device without
# using it: the simulator's own processes, Claude.app's orientation `log stream`
# watcher (holds every sim it ever saw for hours), the emulator itself, and us.
PROCS=$(ps -axww -o command= | grep -v -E \
  'CoreSimulator/Devices/|launchd_sim|simctl spawn [^ ]+ log stream|qemu-system|device-reaper' || true)

busy_all_ios() { grep -q -E 'maestro(\.cli\.AppKt)? test|flutter_tools\.snapshot (drive|test .*integration_test)|xcodebuild .*test' <<<"$PROCS"; }
busy_all_android() { grep -q -E 'maestro(\.cli\.AppKt)? test|flutter_tools\.snapshot (drive|test .*integration_test)|connectedAndroidTest' <<<"$PROCS"; }
ci_job_running() { pgrep -qf 'Runner.Worker' ; }

# $1 = id, $2 = optional name. Name matching is loose on purpose: a false
# "in use" only delays a shutdown.
named_in_use() {
  grep -q -F -- "$1" <<<"$PROCS" && return 0
  [[ -n "${2:-}" ]] && grep -q -F -- "-d $2" <<<"$PROCS" && return 0
  return 1
}

paused() {
  [[ -f "$KEEP_FILE" ]] || return 1
  local age=$(( NOW - $(stat -f %m "$KEEP_FILE") ))
  if (( age < KEEP_HOURS * 3600 )); then return 0; fi
  rm -f "$KEEP_FILE"; log "~/.keep-sims older than ${KEEP_HOURS}h, removed"
  return 1
}

# Lines of "ios|<udid>|<name>" and "android|<serial>|<avd>".
list_devices() {
  xcrun simctl list devices booted 2>/dev/null | sed -n -E \
    's/^ +(.+) \(([0-9A-F-]{36})\) \(Booted\).*/ios|\2|\1/p'
  adb devices 2>/dev/null | awk '$1 ~ /^emulator-[0-9]+$/ && $2 == "device" {print $1}' |
    while read -r serial; do
      avd=$(adb -s "$serial" emu avd name 2>/dev/null | head -1 | tr -d '\r')
      echo "android|$serial|$avd"
    done
}

in_use() { # kind id name
  if [[ "$1" == ios ]]; then busy_all_ios && return 0
  else busy_all_android && return 0; fi
  named_in_use "$2" "$3"
}

shutdown_device() { # kind id name reason
  if [[ $DRY -eq 1 ]]; then echo "WOULD SHUT DOWN $1 $3 ($2): $4"; return; fi
  if [[ "$1" == ios ]]; then
    xcrun simctl shutdown "$2" >/dev/null 2>&1
  else
    adb -s "$2" emu kill >/dev/null 2>&1
  fi
  rm -f "$STATE/last_used/$2"
  log "shut down $1 $3 ($2): $4"
}

reap() { # idle threshold in minutes
  local threshold=$1 kind id name last idle
  while IFS='|' read -r kind id name; do
    [[ -z "$id" ]] && continue
    if [[ "$kind" == android ]] && grep -qw -- "$name" <<<"$PROTECTED_AVDS"; then continue; fi
    if in_use "$kind" "$id" "$name"; then
      [[ $DRY -eq 1 ]] && echo "in use: $kind $name ($id)"
      [[ $DRY -eq 0 ]] && echo "$NOW" >"$STATE/last_used/$id"
      continue
    fi
    if [[ ! -f "$STATE/last_used/$id" ]]; then
      # First sighting: start its idle clock now rather than killing on sight.
      [[ $DRY -eq 0 ]] && echo "$NOW" >"$STATE/last_used/$id"
      last=$NOW
    else
      last=$(cat "$STATE/last_used/$id")
    fi
    idle=$(( (NOW - last) / 60 ))
    if (( idle >= threshold )); then
      shutdown_device "$kind" "$id" "$name" "idle ${idle}m (threshold ${threshold}m)"
    elif [[ $DRY -eq 1 ]]; then
      echo "idle ${idle}m of ${threshold}m: $kind $name ($id)"
    fi
  done < <(list_devices)
  # Forget devices that are no longer booted.
  local f live
  live=$(list_devices | cut -d'|' -f2)
  for f in "$STATE/last_used"/*; do
    [[ -e "$f" ]] || continue
    grep -qx -- "$(basename "$f")" <<<"$live" || rm -f "$f"
  done
}

session_id() { sed -n -E 's/.*"session_id" *: *"([^"]+)".*/\1/p' | head -1; }

case "$MODE" in
  reap|status)
    if paused; then log "paused by ~/.keep-sims"; exit 0; fi
    if ci_job_running; then log "GitHub Actions job running, skipping"; exit 0; fi
    level=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 1)
    if (( level >= 2 )); then
      log "memory pressure level $level, idle threshold ${PRESSURE_IDLE_MIN}m"
      reap "$PRESSURE_IDLE_MIN"
    else
      reap "$IDLE_MIN"
    fi
    ;;
  nightly)
    if paused; then log "paused by ~/.keep-sims"; exit 0; fi
    if ci_job_running; then log "GitHub Actions job running, skipping"; exit 0; fi
    reap 0
    ;;
  session-start)
    sid=$(session_id); [[ -z "$sid" ]] && exit 0
    list_devices | cut -d'|' -f2 >"$STATE/sessions/$sid"
    find "$STATE/sessions" -type f -mtime +7 -delete 2>/dev/null
    ;;
  session-end)
    sid=$(session_id); [[ -z "$sid" ]] && exit 0
    before="$STATE/sessions/$sid"
    [[ -f "$before" ]] || exit 0
    # SessionEnd hooks get ~1.5s; do the slow part detached.
    (
      sleep 2 # let this session's own flutter/maestro children exit first
      PROCS=$(ps -axww -o command= | grep -v -E \
        'CoreSimulator/Devices/|launchd_sim|simctl spawn [^ ]+ log stream|qemu-system|device-reaper' || true)
      while IFS='|' read -r kind id name; do
        grep -qx -- "$id" "$before" && continue
        if [[ "$kind" == android ]] && grep -qw -- "$name" <<<"$PROTECTED_AVDS"; then continue; fi
        in_use "$kind" "$id" "$name" && continue
        shutdown_device "$kind" "$id" "$name" "booted by ended Claude session $sid"
      done < <(list_devices)
      rm -f "$before"
    ) </dev/null >/dev/null 2>&1 &
    disown
    ;;
  *)
    echo "usage: device-reaper [reap|nightly|status|session-start|session-end]" >&2; exit 2 ;;
esac

# Keep the log small.
if [[ -f "$LOG" ]] && (( $(wc -l <"$LOG") > 2000 )); then
  tail -1000 "$LOG" >"$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
exit 0
