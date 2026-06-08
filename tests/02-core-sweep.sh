#!/usr/bin/env bash
# Pins a single-thread y-cruncher to each P-core in turn (preferred cores first;
# E-cores excluded), logging time-to-first-error per core to localize degradation.
# Env: RUN_DIR (required), SWEEP_MIN (per-core minutes, default 8)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"
VENDOR="$HERE/../vendor"
: "${RUN_DIR:?RUN_DIR required}"
SWEEP_MIN="${SWEEP_MIN:-8}"
LOG="$RUN_DIR/core-sweep.log"
YC="$(ls "$VENDOR"/y-cruncher*/y-cruncher 2>/dev/null | head -1)"
[ -x "$YC" ] || { echo "y-cruncher not found — run ./imcc setup" > "$LOG"; exit 2; }

mapfile -t ORDER < <(tk_detect_pcore_reps | tr ' ' '\n')
[ "${#ORDER[@]}" -gt 0 ] || { echo "could not enumerate P-cores (lscpu failed?)" > "$LOG"; exit 2; }

# y-cruncher appends ".cfg" to extensionless config paths and can't read /dev/fd,
# so the config must be a real .cfg file (not process substitution).
CFG="$RUN_DIR/core-sweep.cfg"
printf 'StressTest { Duration: %s, ThreadCount: 1, AllocateLocal: true }\n' "$((SWEEP_MIN*60))" > "$CFG"

overall=0
: > "$LOG"
for cpu in "${ORDER[@]}"; do
  tk_mark_progress "$RUN_DIR" "core-sweep (cpu $cpu)"
  echo "=== sweep cpu $cpu (${SWEEP_MIN}m) $(date '+%T') ===" | tee -a "$LOG"
  # Live watchdog per core: surfaces a checksum mismatch the instant it appears
  # and kills that core's run. rc 1 = error detected; 0/2 (clean or duration-cap
  # timeout with no error) = ok.
  tk_run_watched "$LOG" ycruncher -- \
    timeout "${SWEEP_MIN}m" taskset -c "$cpu" "$YC" config "$CFG"
  rc=$?
  if [ "$rc" = "1" ]; then
    echo "  >> CPU $cpu FAILED" | tee -a "$LOG"; overall=1
  else
    echo "  >> CPU $cpu ok" | tee -a "$LOG"
  fi
done
exit "$overall"
