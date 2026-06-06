#!/usr/bin/env bash
# Repeated kernel compile; segfault / internal compiler error = instability.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"; VENDOR="$HERE/../vendor"
: "${RUN_DIR:?RUN_DIR required}"; DURATION_MIN="${DURATION_MIN:-30}"
LOG="$RUN_DIR/compile.log"
KVER="6.12"; SRC="$VENDOR/linux-$KVER"
if [ ! -d "$SRC" ]; then
  echo "fetching kernel source (one-time)..." | tee "$LOG"
  curl -fL "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz" -o /tmp/k.tar.xz \
    && tar -xf /tmp/k.tar.xz -C "$VENDOR" || { echo "kernel src fetch failed" | tee -a "$LOG"; exit 2; }
fi
cd "$SRC" || exit 2
make defconfig >> "$LOG" 2>&1
end=$(( $(date +%s) + DURATION_MIN*60 )); pass=0
while [ "$(date +%s)" -lt "$end" ]; do
  pass=$((pass+1)); tk_mark_progress "$RUN_DIR" "compile pass $pass"
  echo "=== pass $pass $(date '+%T') ===" >> "$LOG"
  make -j"$(nproc)" clean >> "$LOG" 2>&1
  if ! make -j"$(nproc)" >> "$LOG" 2>&1; then echo "BUILD FAILED pass $pass" >> "$LOG"; break; fi
done
tk_scan_log compile "$LOG" >> "$LOG"; exit $?
