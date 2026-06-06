#!/usr/bin/env bash
# Single-thread y-cruncher PINNED to the suspect (highest-boost) logical CPU.
# Lets that core boost solo to max turbo = the Vmin-shift condition.
# Env: RUN_DIR (required), DURATION_MIN (default 30), TK_TARGET_CPU (default: first preferred)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"
VENDOR="$HERE/../vendor"
: "${RUN_DIR:?RUN_DIR required}"
DURATION_MIN="${DURATION_MIN:-30}"
TARGET="${TK_TARGET_CPU:-$(tk_detect_preferred_cpus | awk '{print $1}')}"
LOG="$RUN_DIR/core-target.log"
[ -n "$TARGET" ] || { echo "could not detect a target CPU (lscpu failed?)" | tee -a "$LOG"; exit 2; }
YC="$(ls "$VENDOR"/y-cruncher*/y-cruncher 2>/dev/null | head -1)"

tk_mark_progress "$RUN_DIR" "core-target (cpu $TARGET)"
echo "core-target: pinning single-thread y-cruncher to logical CPU $TARGET for ${DURATION_MIN}m" | tee "$LOG"
[ -x "$YC" ] || { echo "y-cruncher not found — run setup.sh" | tee -a "$LOG"; exit 2; }

# y-cruncher stress test, 1 thread, pinned; timeout bounds duration.
timeout "${DURATION_MIN}m" taskset -c "$TARGET" \
  "$YC" config <(printf 'StressTest { Duration: %s, ThreadCount: 1, AllocateLocal: true }\n' "$((DURATION_MIN*60))") \
  >> "$LOG" 2>&1
rc=$?
# timeout's 124 = ran full duration with no crash = success for a stress test.
[ "$rc" = "124" ] && rc=0
tk_scan_log ycruncher "$LOG" >/dev/null; scan=$?
[ "$rc" -ne 0 ] && [ "$scan" -eq 0 ] && exit 2   # died abnormally, no error text
exit "$scan"
