#!/usr/bin/env bash
# Installs a user systemd service + timer that runs crash-scan at login and
# every 10 minutes thereafter, so crash signatures are captured close to fault
# time (post-reboot journal timestamps can be skewed by RTC drift during a hard
# freeze — live capture is what dated the Jun 6 crash correctly).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
UNIT_DIR="$HOME/.config/systemd/user"; mkdir -p "$UNIT_DIR"
cat > "$UNIT_DIR/testkit-crashscan.service" <<EOF
[Unit]
Description=CPU testkit crash scanner

[Service]
Type=oneshot
ExecStart=$HERE/crash-scan.sh
EOF
cat > "$UNIT_DIR/testkit-crashscan.timer" <<EOF
[Unit]
Description=Run CPU testkit crash scanner periodically

[Timer]
OnStartupSec=2min
OnUnitActiveSec=10min

[Install]
WantedBy=timers.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now testkit-crashscan.timer
systemctl --user start testkit-crashscan.service
echo "installed: timer scans every 10 min. Check: $HERE/../results/crashes.log"
