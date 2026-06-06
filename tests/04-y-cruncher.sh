#!/usr/bin/env bash
# All-core y-cruncher component stress test (self-verifying).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"; VENDOR="$HERE/../vendor"
: "${RUN_DIR:?RUN_DIR required}"; DURATION_MIN="${DURATION_MIN:-30}"
LOG="$RUN_DIR/y-cruncher.log"
YC="$(ls "$VENDOR"/y-cruncher*/y-cruncher 2>/dev/null | head -1)"
[ -x "$YC" ] || { echo "y-cruncher not found — run setup.sh" > "$LOG"; exit 2; }
tk_mark_progress "$RUN_DIR" "y-cruncher all-core"
timeout "${DURATION_MIN}m" "$YC" config \
  <(printf 'StressTest { Duration: %s, AllocateLocal: true }\n' "$((DURATION_MIN*60))") >> "$LOG" 2>&1
rc=$?; [ "$rc" = "124" ] && rc=0
tk_scan_log ycruncher "$LOG" >> "$LOG"; scan=$?
[ "$rc" -ne 0 ] && [ "$scan" -eq 0 ] && exit 2
exit "$scan"
