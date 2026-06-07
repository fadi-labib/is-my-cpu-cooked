#!/usr/bin/env bash
# All-core then single-core stress-ng with result verification.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"
: "${RUN_DIR:?RUN_DIR required}"; DURATION_MIN="${DURATION_MIN:-30}"
LOG="$RUN_DIR/stress-ng.log"
command -v stress-ng >/dev/null || { echo "stress-ng missing — run setup.sh" > "$LOG"; exit 2; }
if [ -n "${TK_TARGET_CPU:-}" ]; then
  # Pinned A/B mode: FFT-class verify load confined to the target CPUs.
  # (fft, not matrixprod/all — steady-state methods pass on cores that fail
  # FFT-class loads; see y-cruncher FFTv4 vs matrixprod results.)
  NW="$(echo "$TK_TARGET_CPU" | awk -F, '{print NF}')"
  tk_mark_progress "$RUN_DIR" "stress-ng fft (cpu $TK_TARGET_CPU)"
  taskset -c "$TK_TARGET_CPU" \
    stress-ng --cpu "$NW" --cpu-method fft --verify --metrics --timeout "${DURATION_MIN}m" >> "$LOG" 2>&1; rc=$?
else
  half=$(( DURATION_MIN/2 )); [ "$half" -lt 1 ] && half=1
  tk_mark_progress "$RUN_DIR" "stress-ng all-core"
  stress-ng --cpu 0 --cpu-method all --verify --metrics --timeout "${half}m" >> "$LOG" 2>&1; rc1=$?
  tk_mark_progress "$RUN_DIR" "stress-ng single-core"
  stress-ng --cpu 2 --cpu-method all --verify --metrics --timeout "${half}m" >> "$LOG" 2>&1; rc2=$?
  rc=0; { [ "$rc1" -ne 0 ] || [ "$rc2" -ne 0 ]; } && rc=1
fi
tk_scan_log stress-ng "$LOG" >/dev/null; scan=$?
[ "$rc" -ne 0 ] && [ "$scan" -eq 0 ] && exit 2
exit "$scan"
