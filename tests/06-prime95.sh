#!/usr/bin/env bash
# mprime Small-FFT torture via expect-free stdin automation.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"; VENDOR="$HERE/../vendor"
: "${RUN_DIR:?RUN_DIR required}"; DURATION_MIN="${DURATION_MIN:-30}"
LOG="$RUN_DIR/prime95.log"; MP="$VENDOR/mprime/mprime"
[ -x "$MP" ] || { echo "mprime not found — run setup.sh" > "$LOG"; exit 2; }
tk_mark_progress "$RUN_DIR" "prime95 small-FFT"
# Preconfigure torture: write prime.txt + local.txt for non-interactive Small FFTs.
cd "$VENDOR/mprime" || exit 2
cat > prime.txt <<'EOF'
TortureMem=8
TortureTime=3
EOF
# Menu input: 16 = Torture Test, 2 = Small FFTs, then run; timeout bounds it.
timeout "${DURATION_MIN}m" bash -c 'printf "16\n2\nN\n" | "'"$MP"'" -t' >> "$LOG" 2>&1
rc=$?; [ "$rc" = "124" ] && rc=0
tk_scan_log prime95 "$LOG" >/dev/null; scan=$?
[ "$rc" -ne 0 ] && [ "$scan" -eq 0 ] && exit 2
exit "$scan"
