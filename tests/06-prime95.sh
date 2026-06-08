#!/usr/bin/env bash
# mprime Small-FFT torture via expect-free stdin automation.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"; VENDOR="$HERE/../vendor"
: "${RUN_DIR:?RUN_DIR required}"; DURATION_MIN="${DURATION_MIN:-30}"
LOG="$RUN_DIR/prime95.log"; MP="$VENDOR/mprime/mprime"
[ -x "$MP" ] || { echo "mprime not found — run setup.sh" > "$LOG"; exit 2; }
# Optional pin: mprime does not rebind its own affinity, so taskset holds
# (verified by ab-evidence.sh's pin check). Worker count stays at the default;
# oversubscription on two logical CPUs is harmless for Small FFTs.
PIN=()
[ -n "${TK_TARGET_CPU:-}" ] && PIN=(taskset -c "$TK_TARGET_CPU")
tk_mark_progress "$RUN_DIR" "prime95 small-FFT${TK_TARGET_CPU:+ (cpu $TK_TARGET_CPU)}"
# Preconfigure torture: write prime.txt + local.txt for non-interactive Small FFTs.
cd "$VENDOR/mprime" || exit 2
cat > prime.txt <<'EOF'
TortureMem=8
TortureTime=3
EOF
# Menu input: 16 = Torture Test, 2 = Small FFTs, then run; timeout bounds it.
# Live watchdog surfaces a FATAL ERROR / rounding error the moment mprime prints
# it. timeout firing (mapped to rc 2 by tk_run_watched) is the normal duration
# cap here, so a backstop-kill with no error text reads as clean.
tk_run_watched "$LOG" prime95 -- \
  timeout "${DURATION_MIN}m" "${PIN[@]}" bash -c 'printf "16\n2\nN\n" | "'"$MP"'" -t'
rc=$?
[ "$rc" = "2" ] && rc=0   # duration-cap timeout with no error = clean
exit "$rc"
