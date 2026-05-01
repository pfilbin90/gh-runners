#!/usr/bin/env bash
# Upgrade host Flutter, then restart the Mac runners so they sync to the new
# version. The runners' bootstrap script reads the host's git ref on start, so
# a `restart` (which re-runs the entrypoint) is enough — no image rebuild.
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Upgrading host Flutter"
BEFORE=$(flutter --version 2>/dev/null | head -1 || echo "?")
flutter upgrade
AFTER=$(flutter --version 2>/dev/null | head -1 || echo "?")
echo "    before: $BEFORE"
echo "    after:  $AFTER"

if [ "$BEFORE" = "$AFTER" ]; then
  echo
  echo "==> Host Flutter is unchanged; skipping runner restart."
  exit 0
fi

echo
echo "==> Restarting Mac runners to pick up the new Flutter"
docker compose -f docker-compose.yml -f docker-compose.local.yml restart

echo
echo "==> Done. The first runner to start will sync /opt/flutter to the new host"
echo "    ref (downloads new Dart SDK + precache, ~2-5 min). Other runners block"
echo "    on the bootstrap lock and skip once it's complete."
echo
echo "    Follow progress with:"
echo "      docker compose -f docker-compose.yml -f docker-compose.local.yml logs -f"
