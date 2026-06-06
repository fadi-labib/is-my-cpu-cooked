#!/usr/bin/env bash
# Installs a user systemd service that runs crash-scan once per boot/login.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"; mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/testkit-crashscan.service" <<EOF
[Unit]
Description=CPU testkit crash scanner

[Service]
Type=oneshot
ExecStart=$HERE/crash-scan.sh

[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now testkit-crashscan.service
echo "installed + ran. Check: $HERE/../results/crashes.log"
