#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -x ./cliphistory ]]; then
  echo "Binary not found, building first..."
  ./build.sh
fi

LABEL="com.user.cliphistory.native"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG_DIR="$HOME/.local/share/cliphistory"
BIN_PATH="$(pwd)/cliphistory"

mkdir -p "$LOG_DIR"
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BIN_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/native.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/native.err</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

echo "Installed and started LaunchAgent: $LABEL"
echo "Logs: $LOG_DIR/native.log and $LOG_DIR/native.err"
