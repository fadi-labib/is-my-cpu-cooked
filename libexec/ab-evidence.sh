#!/usr/bin/env bash
# ab-evidence.sh — A/B evidence-collection protocol for one suspect core.
#
# 1. Verifies the kit is actually set up: tools present, crash watcher timer
#    active, target CPUs online, preflight baseline clean, system idle.
# 2. Runs the multi-tool FFT-class suite on the suspect CPUs, then the same
#    suite on the control CPUs, via run-all.sh (rows land in runs.csv as usual).
#    Verifies mid-leg that the load actually stayed on the target CPUs.
# 3. Scans for kernel crash signatures captured during the runs, regenerates
#    the RMA report, and prints the A/B conclusion.
#
# Usage: ./ab-evidence.sh [--check] [--minutes N]
#   --check      setup verification only; do not start any stress test
#   --minutes N  duration per tool per leg (default 20; 3 tools x 2 legs = 6N min)
# Env overrides: TK_SUSPECT (default 10,11), TK_CONTROL (default 8,9),
#                TK_TESTS (default core-target,stress-ng,prime95)
#
# Deliberately sudo-free: if target CPUs are offline (chcpu -d mitigation),
# it refuses and prints the exact command to bring them back.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"
RESULTS="$HERE/../results"

SUSPECT="${TK_SUSPECT:-10,11}"
CONTROL="${TK_CONTROL:-8,9}"
TESTS="${TK_TESTS:-core-target,stress-ng,prime95}"
MINUTES=20
CHECK_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --check)   CHECK_ONLY=1; shift;;
    --minutes) MINUTES="$2"; shift 2;;
    *) echo "unknown arg: $1 (usage: ./imcc ab [--check] [--minutes N])"; exit 1;;
  esac
done

say()  { printf '%s\n' "$*"; }
ok()   { printf '[OK]   %s\n' "$*"; }
bad()  { printf '[FAIL] %s\n' "$*"; SETUP_BAD=1; }
warn() { printf '[WARN] %s\n' "$*"; }

# ── 1. setup verification ─────────────────────────────────────────────────────
SETUP_BAD=0
say "====== setup verification ======"

command -v stress-ng >/dev/null 2>&1 \
  && ok "stress-ng installed" || bad "stress-ng missing — run ./imcc setup"
YC="$(ls "$HERE"/../vendor/y-cruncher*/y-cruncher 2>/dev/null | head -1)"
[ -n "$YC" ] && [ -x "$YC" ] \
  && ok "y-cruncher present" || bad "y-cruncher missing — run ./imcc setup"
[ -x "$HERE/../vendor/mprime/mprime" ] \
  && ok "mprime present" || bad "mprime missing — run ./imcc setup"

if systemctl --user is-active --quiet testkit-crashscan.timer 2>/dev/null; then
  ok "crash watcher timer active (scans every 10 min)"
else
  bad "crash watcher timer NOT active — run ./watcher/install-watcher.sh"
fi

# Every target CPU must be online (a leftover 'chcpu -d' kills pinned tests).
offline=""
for c in $(echo "$SUSPECT,$CONTROL" | tr ',' ' '); do
  f="/sys/devices/system/cpu/cpu$c/online"
  [ -f "$f" ] && [ "$(cat "$f")" != "1" ] && offline="$offline $c"
done
offline="${offline# }"
if [ -n "$offline" ]; then
  bad "CPUs $offline offline — run: sudo chcpu -e $(echo "$offline" | tr ' ' ',')   (re-disable after testing)"
else
  ok "target CPUs online (suspect $SUSPECT, control $CONTROL)"
fi

PF_OUT="$(mktemp)"
if "$HERE/preflight.sh" > "$PF_OUT" 2>&1; then
  ok "preflight baseline OK"
else
  bad "preflight reports hard confounders:"
  sed 's/^/         /' "$PF_OUT" | tail -5
fi
rm -f "$PF_OUT"

# Background-load check: a busy system muddies the suspect/control comparison.
S0="$(mktemp)"; S1="$(mktemp)"
cat /proc/stat > "$S0"; sleep 5; cat /proc/stat > "$S1"
busy_now="$(tk_busy_cpus "$S0" "$S1" | awk '$2>50{n++} END{print n+0}')"
rm -f "$S0" "$S1"
if [ "$busy_now" -gt 2 ]; then
  warn "$busy_now CPUs >50% busy right now — close heavy apps for a clean comparison"
else
  ok "system mostly idle ($busy_now CPUs busy)"
fi

if [ "$SETUP_BAD" -ne 0 ]; then
  say ""
  say "setup verification FAILED — fix the [FAIL] items above and re-run."
  exit 1
fi
if [ "$CHECK_ONLY" -eq 1 ]; then
  say ""
  say "setup OK — run without --check to start (~$((MINUTES*6)) min total)."
  exit 0
fi

# Baseline crash-log size, to diff after the runs.
KLOG="$RESULTS/crashes.log"
K0="$(wc -l < "$KLOG" 2>/dev/null || echo 0)"

# ── 2. test legs ──────────────────────────────────────────────────────────────
# Abort guard: mark any unfinished run dir on interrupt so the next crash-scan
# doesn't record a user abort as a hardware crash.
abort_guard() {
  local d
  for d in "$RESULTS"/*/; do
    if [ -f "$d/START" ] && [ ! -f "$d/FINISHED" ]; then
      echo "aborted $(date '+%F %T') — ab-evidence interrupted, not a crash" > "$d/FINISHED"
    fi
  done
}
trap 'abort_guard; exit 130' INT TERM

LEG_VERDICT=""
run_leg() { # <cpus> <label>
  local cpus="$1" label="$2" s0 s1 snap pin
  say ""
  say "====== $label leg: CPUs $cpus — ${MINUTES}m x {$TESTS} ======"
  # Pin spot-check: snapshot per-CPU load 3 min into the leg (10s window).
  s0="$(mktemp)"; s1="$(mktemp)"
  ( sleep 180; cat /proc/stat > "$s0"; sleep 10; cat /proc/stat > "$s1" ) &
  snap=$!
  TK_TARGET_CPU="$cpus" TK_NOTES="$label cpus=$cpus" \
    "$HERE/run-all.sh" --tests "$TESTS" --minutes "$MINUTES"
  if [ -s "$s1" ]; then
    pin="$(tk_busy_cpus "$s0" "$s1" | awk -v t="$cpus" '
      BEGIN { n=split(t,a,","); for(i=1;i<=n;i++) want["cpu"a[i]]=1 }
      { if ( want[$1] && $2<50) miss=miss" "$1
        if (!want[$1] && $2>80) esc=esc" "$1 }
      END { if (miss) printf "MISS%s;", miss; if (esc) printf "ESC%s;", esc }')"
    case "$pin" in
      *MISS*) warn "pin check: target CPUs were NOT loaded 3 min into the $label leg ($pin) — result suspect";;
    esac
    case "$pin" in
      *ESC*)  warn "pin check: load outside target CPUs during $label leg ($pin) — background noise or affinity escape";;
    esac
    [ -z "$pin" ] && ok "pin check: load confined to CPUs $cpus"
  else
    kill "$snap" 2>/dev/null
  fi
  rm -f "$s0" "$s1"
  LEG_VERDICT="$(tail -1 "$RESULTS/runs.csv" | awk -F, '{print $4}')"
  say "$label leg verdict: $LEG_VERDICT"
}

run_leg "$SUSPECT" suspect
SV="$LEG_VERDICT"
run_leg "$CONTROL" control
CV="$LEG_VERDICT"
trap - INT TERM

# ── 3. crash check + report ───────────────────────────────────────────────────
say ""
say "====== crash-log check ======"
"$HERE/../watcher/crash-scan.sh"
K1="$(wc -l < "$KLOG" 2>/dev/null || echo 0)"
if [ "$K1" -gt "$K0" ]; then
  warn "NEW kernel crash signatures captured during the runs:"
  tail -n "$((K1-K0))" "$KLOG"
else
  ok "no new kernel crash signatures during the runs"
fi

"$HERE/report.sh"

say ""
say "====== A/B result ======"
say "suspect ($SUSPECT): $SV"
say "control ($CONTROL): $CV"
say "conclusion: $(tk_ab_interpret "$SV" "$CV")"
say "full evidence: $RESULTS/RMA-REPORT.md"
