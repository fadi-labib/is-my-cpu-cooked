#!/usr/bin/env bash
# All-core then single-core stress-ng with result verification.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"
: "${RUN_DIR:?RUN_DIR required}"; DURATION_MIN="${DURATION_MIN:-30}"
LOG="$RUN_DIR/stress-ng.log"
command -v stress-ng >/dev/null || { echo "stress-ng missing — run ./imcc setup" > "$LOG"; exit 2; }
if [ -n "${TK_TARGET_CPU:-}" ]; then
  # Pinned A/B mode: FFT-class verify load confined to the target CPUs.
  # (fft, not matrixprod/all — steady-state methods pass on cores that fail
  # FFT-class loads; see y-cruncher FFTv4 vs matrixprod results.)
  NW="$(echo "$TK_TARGET_CPU" | awk -F, '{print NF}')"
  tk_mark_progress "$RUN_DIR" "stress-ng fft (cpu $TK_TARGET_CPU)"
  tk_run_watched "$LOG" stress-ng -- taskset -c "$TK_TARGET_CPU" \
    stress-ng --cpu "$NW" --cpu-method fft --verify --metrics --timeout "${DURATION_MIN}m"
  exit $?
else
  half=$(( DURATION_MIN/2 )); [ "$half" -lt 1 ] && half=1
  tk_mark_progress "$RUN_DIR" "stress-ng all-core"
  tk_run_watched "$LOG" stress-ng -- \
    stress-ng --cpu 0 --cpu-method all --verify --metrics --timeout "${half}m"; r1=$?
  [ "$r1" = "1" ] && exit 1   # error surfaced live on the all-core leg
  tk_mark_progress "$RUN_DIR" "stress-ng single-core"
  tk_run_watched "$LOG" stress-ng -- \
    stress-ng --cpu 2 --cpu-method all --verify --metrics --timeout "${half}m"; r2=$?
  [ "$r2" = "1" ] && exit 1
  { [ "$r1" = "2" ] || [ "$r2" = "2" ]; } && exit 2
  exit 0
fi
