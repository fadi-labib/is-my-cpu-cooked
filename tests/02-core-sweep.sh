#!/usr/bin/env bash
# Pins a single-thread y-cruncher to each P-core in turn (preferred cores first),
# logging time-to-first-error per core to localize degradation.
# Env: RUN_DIR (required), SWEEP_MIN (per-core minutes, default 8)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"
VENDOR="$HERE/../vendor"
: "${RUN_DIR:?RUN_DIR required}"
SWEEP_MIN="${SWEEP_MIN:-8}"
LOG="$RUN_DIR/core-sweep.log"
YC="$(ls "$VENDOR"/y-cruncher*/y-cruncher 2>/dev/null | head -1)"
[ -x "$YC" ] || { echo "y-cruncher not found — run setup.sh" > "$LOG"; exit 2; }

# P-cores = one logical thread per physical core, MAXMHZ >= 5700. Preferred first.
mapfile -t PREF < <(tk_detect_preferred_cpus | tr ' ' '\n')
# all P-core first-threads (even logical indices 0..15 on this 14900K)
PCORES=(0 2 4 6 8 10 12 14)
ORDER=("${PREF[@]}")
for c in "${PCORES[@]}"; do [[ " ${PREF[*]} " == *" $c "* ]] || ORDER+=("$c"); done

overall=0
: > "$LOG"
for cpu in "${ORDER[@]}"; do
  tk_mark_progress "$RUN_DIR" "core-sweep (cpu $cpu)"
  echo "=== sweep cpu $cpu (${SWEEP_MIN}m) $(date '+%T') ===" | tee -a "$LOG"
  timeout "${SWEEP_MIN}m" taskset -c "$cpu" \
    "$YC" config <(printf 'StressTest { Duration: %s, ThreadCount: 1, AllocateLocal: true }\n' "$((SWEEP_MIN*60))") \
    >> "$LOG" 2>&1
  rc=$?; [ "$rc" = "124" ] && rc=0
  if ! tk_scan_log ycruncher "$LOG" >/dev/null || [ "$rc" -ne 0 ]; then
    echo "  >> CPU $cpu FAILED" | tee -a "$LOG"; overall=1
  else
    echo "  >> CPU $cpu ok" | tee -a "$LOG"
  fi
done
exit "$overall"
