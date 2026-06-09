#!/usr/bin/env bash
# Pins a single-thread y-cruncher to each P-core in turn (preferred cores first;
# E-cores excluded), logging time-to-first-error per core to localize degradation.
# Env: RUN_DIR (required), DURATION_MIN (total sweep budget, default 30),
#      SWEEP_MIN (explicit per-core minutes; overrides the budget split)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"
VENDOR="$HERE/../vendor"
: "${RUN_DIR:?RUN_DIR required}"
DURATION_MIN="${DURATION_MIN:-30}"
LOG="$RUN_DIR/core-sweep.log"
YC="$(ls "$VENDOR"/y-cruncher*/y-cruncher 2>/dev/null | head -1)"
[ -x "$YC" ] || { echo "y-cruncher not found - run ./imcc setup" > "$LOG"; exit 2; }

mapfile -t ORDER < <(tk_detect_pcore_reps | tr ' ' '\n')
[ "${#ORDER[@]}" -gt 0 ] || { echo "could not enumerate P-cores (lscpu failed?)" > "$LOG"; exit 2; }

# Per-core sweep time. Default: spread DURATION_MIN across the P-cores so the
# whole sweep takes ~DURATION_MIN (consistent with every other test phase),
# at least 1 min/core. The defect reproduces in <1s, so a few minutes per core
# is ample. SWEEP_MIN overrides with an explicit per-core duration.
if [ -n "${SWEEP_MIN:-}" ]; then
  per_core="$SWEEP_MIN"
else
  per_core=$(( DURATION_MIN / ${#ORDER[@]} ))
  [ "$per_core" -lt 1 ] && per_core=1
fi

# y-cruncher appends ".cfg" to extensionless config paths and can't read /dev/fd,
# so the config must be a real .cfg file (not process substitution).
CFG="$RUN_DIR/core-sweep.cfg"
printf 'StressTest { Duration: %s, ThreadCount: 1, AllocateLocal: true }\n' "$((per_core*60))" > "$CFG"

overall=0
: > "$LOG"
for cpu in "${ORDER[@]}"; do
  tk_mark_progress "$RUN_DIR" "core-sweep (cpu $cpu)"
  echo "=== sweep cpu $cpu (${per_core}m) $(date '+%T') ===" | tee -a "$LOG"
  # Live watchdog per core: surfaces a checksum mismatch the instant it appears
  # and kills that core's run. rc 1 = error detected; 0/2 (clean or duration-cap
  # timeout with no error) = ok.
  tk_run_watched "$LOG" ycruncher -- \
    timeout "${per_core}m" taskset -c "$cpu" "$YC" config "$CFG"
  rc=$?
  if [ "$rc" = "1" ]; then
    echo "  >> CPU $cpu FAILED" | tee -a "$LOG"; overall=1
  else
    echo "  >> CPU $cpu ok" | tee -a "$LOG"
  fi
done
exit "$overall"
