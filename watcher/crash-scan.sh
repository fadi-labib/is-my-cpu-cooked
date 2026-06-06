#!/usr/bin/env bash
# Scans the journal for kernel BUG/oops across boots; appends new hits to results/crashes.log.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"
RESULTS="$HERE/../results"; mkdir -p "$RESULTS"
OUT="$RESULTS/crashes.log"; STATE="$RESULTS/.crash-scan-state"
PAT="kernel BUG at|invalid opcode|general protection|Kernel panic|Oops"
last="$(cat "$STATE" 2>/dev/null || echo '')"
hits="$(journalctl -k --no-pager -b all 2>/dev/null | grep -E "$PAT" || true)"
[ -z "$hits" ] && { echo "no kernel crash signatures found"; exit 0; }
# Append only lines not already recorded.
new=0
while IFS= read -r line; do
  grep -qF "$line" "$OUT" 2>/dev/null && continue
  echo "$line" >> "$OUT"; new=$((new+1))
done <<< "$hits"
echo "$(date '+%F %T')" > "$STATE"
echo "recorded $new new crash line(s) -> $OUT"
[ "$new" -gt 0 ] && tk_summary_append "$RESULTS" "$(date +%Y%m%d-%H%M%S)" "-" "real-use" "CRASHED (kernel BUG)" "-" "$new" "see crashes.log"
