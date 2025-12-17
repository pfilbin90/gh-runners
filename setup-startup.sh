#!/bin/bash
# Setup script to configure GitHub Actions runners to start on macOS startup
# This creates a launchd plist to run start-runners.sh on login

set -e

# Check if running as root (not needed for launchd user agents, but good to check)
if [ "$EUID" -eq 0 ]; then
    echo "Warning: This script should be run as a regular user, not root." >&2
    echo "Launch agents run in user context." >&2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_SCRIPT="$SCRIPT_DIR/start-runners.sh"

# Make sure start-runners.sh is executable
chmod +x "$START_SCRIPT"

# Launch agent name and path
AGENT_NAME="com.github.actions-runners.startup"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT_PLIST="$AGENT_DIR/$AGENT_NAME.plist"

# Create LaunchAgents directory if it doesn't exist
mkdir -p "$AGENT_DIR"

# Remove existing plist if it exists
if [ -f "$AGENT_PLIST" ]; then
    echo "Removing existing launch agent..."
    launchctl unload "$AGENT_PLIST" 2>/dev/null || true
    rm -f "$AGENT_PLIST"
fi

# Create the plist file
echo "Creating launch agent: $AGENT_NAME"
cat > "$AGENT_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$AGENT_NAME</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$START_SCRIPT</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/github-actions-runners.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/github-actions-runners.error.log</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>
    <key>ThrottleInterval</key>
    <integer>60</integer>
</dict>
</plist>
EOF

# Load the launch agent
echo "Loading launch agent..."
launchctl load "$AGENT_PLIST"

echo ''
echo 'Launch agent created successfully!'
echo ''
echo 'The agent will:'
echo '  - Start when you log in'
echo '  - Wait for Docker to be ready'
echo '  - Start all runner containers'
echo ''
echo 'To test the agent manually, run:'
echo "  launchctl start $AGENT_NAME"
echo ''
echo 'To stop the agent:'
echo "  launchctl stop $AGENT_NAME"
echo ''
echo 'To unload the agent:'
echo "  launchctl unload $AGENT_PLIST"
echo ''
echo 'To view logs:'
echo "  tail -f $HOME/Library/Logs/github-actions-runners.log"
echo "  tail -f $HOME/Library/Logs/github-actions-runners.error.log"
echo ''
echo 'To view/edit the plist:'
echo "  open $AGENT_PLIST"

