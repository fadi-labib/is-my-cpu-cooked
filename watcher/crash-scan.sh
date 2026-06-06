#!/usr/bin/env bash
# Scans the journal for kernel BUG/oops across boots; appends new hits to results/crashes.log.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"
RESULTS="$HERE/../results"; mkdir -p "$RESULTS"
OUT="$RESULTS/crashes.log"; STATE="$RESULTS/.crash-scan-state"
PAT="kernel BUG at|invalid opcode|general protection|Kernel panic|Oops"
UOUT="$RESULTS/userspace-traps.log"
hits="$(journalctl -k --no-pager -b all 2>/dev/null | grep -E "$PAT" || true)"
[ -z "$hits" ] && { echo "no kernel crash signatures found"; exit 0; }
# Split: traps: lines -> userspace-traps.log; everything else -> crashes.log
new_k=0; new_u=0
while IFS= read -r line; do
  if echo "$line" | grep -qF 'traps:'; then
    grep -qF "$line" "$UOUT" 2>/dev/null && continue
    echo "$line" >> "$UOUT"; new_u=$((new_u+1))
  else
    grep -qF "$line" "$OUT" 2>/dev/null && continue
    echo "$line" >> "$OUT"; new_k=$((new_k+1))
  fi
done <<< "$hits"
echo "$(date '+%F %T')" > "$STATE"
echo "recorded $new_k kernel-fault line(s), $new_u userspace-trap line(s)"
[ "$new_k" -gt 0 ] && tk_summary_append "$RESULTS" "$(date +%Y%m%d-%H%M%S)" "-" "real-use" "CRASHED (kernel BUG)" "-" "$new_k" "see crashes.log"
