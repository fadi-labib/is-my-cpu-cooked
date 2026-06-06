#!/usr/bin/env bash
# lib/common.sh — pure, testable helpers for the CPU testkit.
# Parsing functions take input as args/paths; they never call lscpu/sensors.

tk_version() { echo "testkit-1.0"; }

# Read `lscpu -e=CPU,CORE,MAXMHZ` text on stdin; echo the logical CPU numbers
# whose MAXMHZ equals the global max (the preferred / fastest-boosting cores).
tk_preferred_cpus() {
  awk '
    NR>1 && $3 ~ /^[0-9.]+$/ { cpu[NR]=$1; mhz[NR]=$3+0; if ($3+0>max) max=$3+0 }
    END { for (i in mhz) if (mhz[i]==max) print cpu[i] }
  ' | sort -n | tr "\n" " " | sed "s/ $//"
}

# Convenience wrapper used by scripts (impure — calls lscpu).
tk_detect_preferred_cpus() { lscpu -e=CPU,CORE,MAXMHZ 2>/dev/null | tk_preferred_cpus; }

# tk_scan_log <tool> <logfile> -> echoes matched FAIL lines; rc 0=clean, 1=errors found.
# tk_overall_verdict <errcount> <maxpkg> <thermal_threshold>
tk_overall_verdict() {
  local errs="$1" pkg="$2" thr="$3"
  if [ "${errs:-0}" -gt 0 ]; then echo "FAIL (errors)"; return; fi
  if [ "${pkg:-0}" -ge "${thr:-95}" ]; then echo "THERMAL"; return; fi
  echo "PASS"
}

# tk_summary_append <dir> <ts> <minutes> <tests> <verdict> <maxpkg> <errcount> <notes>
tk_summary_append() {
  local dir="$1" ts="$2" min="$3" tests="$4" verdict="$5" pkg="$6" errs="$7" notes="$8"
  local md="$dir/SUMMARY.md" csv="$dir/runs.csv"
  if [ ! -f "$md" ]; then
    {
      echo "# CPU Testkit — Run Summary"
      echo
      echo "| timestamp | min | tests | verdict | max pkg °C | errors | notes |"
      echo "|-----------|-----|-------|---------|-----------|--------|-------|"
    } > "$md"
  fi
  echo "| $ts | $min | $tests | $verdict | $pkg | $errs | $notes |" >> "$md"
  if [ ! -f "$csv" ]; then
    echo "timestamp,minutes,tests,verdict,max_pkg_c,errors,notes" > "$csv"
  fi
  echo "$ts,$min,$tests,$verdict,$pkg,$errs,$notes" >> "$csv"
}

# Markers — each fsync'd so they survive a hard reset.
tk_mark_start()    { echo "started $(date '+%F %T')" > "$1/START"; sync "$1/START" 2>/dev/null || sync; }
tk_mark_progress() { echo "$2 @ $(date '+%F %T')" > "$1/progress"; sync "$1/progress" 2>/dev/null || sync; }
tk_mark_finished() { echo "finished $(date '+%F %T')" > "$1/FINISHED"; sync "$1/FINISHED" 2>/dev/null || sync; }

# tk_scan_crashed <results_dir> -> one "CRASHED ..." line per run dir with START and no FINISHED.
tk_scan_crashed() {
  local results="$1" d prog
  for d in "$results"/*/; do
    [ -f "$d/START" ] || continue
    [ -f "$d/FINISHED" ] && continue
    prog="$(cat "$d/progress" 2>/dev/null || echo 'unknown test')"
    echo "CRASHED (reset) — run $(basename "$d") died during: $prog"
  done
}

# tk_max_temp <temps.log> -> integer max "Package id 0" temperature (Celsius), or 0.
tk_max_temp() {
  local log="$1"
  [ -f "$log" ] || { echo 0; return; }
  grep "Package id 0" "$log" \
    | sed -E 's/^[^+]*\+([0-9]+)\.[0-9]+°C.*/\1/' \
    | sort -rn | head -1 | grep -E '^[0-9]+$' || echo 0
}

tk_scan_log() {
  local tool="$1" log="$2" pat
  [ -f "$log" ] || { echo "MISSING LOG: $log"; return 1; }
  case "$tool" in
    stress-ng)  pat='fail:|verification failed|verify' ;;
    ycruncher)  pat='[Ee]rror|mismatch|[Cc]oefficient|unstable' ;;
    compile)    pat='internal compiler error|[Ss]egmentation fault|signal 11|Error [0-9]' ;;
    prime95)    pat='FATAL ERROR|[Rr]ounding|[Hh]ardware failure' ;;
    *)          pat='[Ee]rror|FATAL|fail' ;;
  esac
  if grep -nE "$pat" "$log"; then return 1; fi
  return 0
}

TK_SAMPLER_PID=""
# tk_temp_sampler_start <run_dir> <interval_seconds>
tk_temp_sampler_start() {
  local dir="$1" iv="${2:-5}"
  ( while true; do
      sensors 2>/dev/null | grep -E "Package id 0|^Core " >> "$dir/temps.log"
      sleep "$iv"
    done ) &
  TK_SAMPLER_PID=$!
}
tk_temp_sampler_stop() {
  [ -n "$TK_SAMPLER_PID" ] && kill "$TK_SAMPLER_PID" 2>/dev/null
  TK_SAMPLER_PID=""
}
