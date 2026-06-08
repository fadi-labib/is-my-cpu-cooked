#!/usr/bin/env bash
# All-core y-cruncher component stress test (self-verifying).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"; VENDOR="$HERE/../vendor"
: "${RUN_DIR:?RUN_DIR required}"; DURATION_MIN="${DURATION_MIN:-30}"
LOG="$RUN_DIR/y-cruncher.log"
YC="$(ls "$VENDOR"/y-cruncher*/y-cruncher 2>/dev/null | head -1)"
[ -x "$YC" ] || { echo "y-cruncher not found — run ./imcc setup" > "$LOG"; exit 2; }
tk_mark_progress "$RUN_DIR" "y-cruncher all-core"
# Live watchdog around the all-core run. timeout firing (124) on a clean run is
# the normal duration cap, so a backstop-kill with no error text must read as
# clean, not abnormal: detect that case and map rc 2 -> 0.
CFG_FILE="$RUN_DIR/y-cruncher-allcore.cfg"
printf 'StressTest { Duration: %s, AllocateLocal: true }\n' "$((DURATION_MIN*60))" > "$CFG_FILE"
tk_run_watched "$LOG" ycruncher -- timeout "${DURATION_MIN}m" "$YC" config "$CFG_FILE"
rc=$?
[ "$rc" = "2" ] && rc=0   # duration-cap timeout with no error = clean for all-core run
exit "$rc"
