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
[ -x "$YC" ] || { echo "y-cruncher not found - run ./imcc setup" | tee -a "$LOG"; exit 2; }

# y-cruncher appends ".cfg" when the extension is missing, so process
# substitution (/dev/fd/N) breaks - it must be a real file ending in .cfg.
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

# Live watchdog: tk_run_watched streams y-cruncher's output, surfaces the first
# error in-terminal and kills it on the spot (no 5-min ENTER-prompt idle). The
# outer timeout stays as a true backstop for a no-output hang. SecondsTotal still
# bounds a clean run. Returns 0=clean, 1=error detected, 2=abnormal/backstop.
tk_run_watched "$LOG" ycruncher -- \
  timeout "$((DURATION_MIN+5))m" "$YC" pause:0 config "$CFG"
exit $?
