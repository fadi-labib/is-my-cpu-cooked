#!/usr/bin/env bash
# y-cruncher stress PINNED to the suspect (highest-boost) logical CPU(s).
# Lets that core boost solo to max turbo = the Vmin-shift condition.
# Env: RUN_DIR (required), DURATION_MIN (default 30), TK_TARGET_CPU (default: first preferred)
#      TK_TARGET_CPU accepts a comma list ("10,11") to cover both SMT siblings of a core.
# NOTE: y-cruncher rebinds its own thread affinity, so taskset (and user cgroups
# without cpuset delegation) cannot confine it. We pass the core list through its
# config-file API (LogicalCores) instead, which it honors exactly.
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
echo "core-target: pinning y-cruncher stress to logical CPU(s) $TARGET for ${DURATION_MIN}m" | tee "$LOG"
[ -x "$YC" ] || { echo "y-cruncher not found — run setup.sh" | tee -a "$LOG"; exit 2; }

# y-cruncher appends ".cfg" when the extension is missing, so process
# substitution (/dev/fd/N) breaks — it must be a real file ending in .cfg.
CFG="$RUN_DIR/core-target.cfg"
cat > "$CFG" <<EOF
{
    Action : "StressTest"
    StressTest : {
        AllocateLocally : "true"
        LogicalCores : [$(echo "$TARGET" | tr ',' ' ')]
        TotalMemory : 1073741824
        SecondsPerTest : 120
        SecondsTotal : $((DURATION_MIN*60))
        StopOnError : "true"
        Tests : ["BKT" "BBP" "SFT" "FFT" "N63" "VT3"]
    }
}
EOF

# pause:0 = exit without waiting for ENTER. Duration is enforced by SecondsTotal;
# the outer timeout is only a watchdog (+5 min grace) in case y-cruncher hangs.
timeout "$((DURATION_MIN+5))m" "$YC" pause:0 config "$CFG" >> "$LOG" 2>&1
rc=$?
[ "$rc" = "124" ] && { echo "WATCHDOG: y-cruncher ran past SecondsTotal and was killed" | tee -a "$LOG"; rc=2; }
tk_scan_log ycruncher "$LOG" >/dev/null; scan=$?
[ "$rc" -ne 0 ] && [ "$scan" -eq 0 ] && exit 2   # died abnormally, no error text
exit "$scan"
