#!/usr/bin/env bash
# lib/common.sh — pure, testable helpers for the CPU testkit.
# Parsing functions take input as args/paths; they never call lscpu/sensors.

tk_version() { echo "testkit-1.0"; }

# Read `lscpu -e=CPU,CORE,MAXMHZ` text on stdin; echo ONE logical CPU per physical
# core (the lowest-numbered thread of each core), ordered by MAXMHZ descending then
# CPU ascending. This yields every physical core's representative thread, highest-
# boosting (preferred) cores first — works on any Intel topology.
tk_pcore_threads() {
  awk '
    NR>1 && $3 ~ /^[0-9.]+$/ {
      core=$2; cpu=$1; mhz=$3+0
      if (!(core in seen) || cpu < rep[core]) { rep[core]=cpu; rmhz[core]=mhz; seen[core]=1 }
    }
    END { for (c in rep) printf "%d %d\n", rmhz[c], rep[c] }
  ' | sort -k1,1nr -k2,2n | awk '{print $2}' | tr "\n" " " | sed "s/ $//"
}
# Impure wrapper used by scripts:
tk_detect_pcore_threads() { lscpu -e=CPU,CORE,MAXMHZ 2>/dev/null | tk_pcore_threads; }

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

# tk_sig_pattern <tool-set> -> echoes the error-detection regex for a tool.
# Single source of truth shared by tk_scan_log (post-run) and tk_watch_stream (live).
# NOTE: no bare '[Ee]rror' for ycruncher — its settings echo ("Stop on Error: Enabled")
# would false-positive every run. Real failures print "Failed" / "Exception".
tk_sig_pattern() {
  case "$1" in
    stress-ng)  echo 'fail:|verification failed|verify' ;;
    ycruncher)  echo 'logical core|Error [Cc]ode|mismatch|[Cc]oefficient|unstable| Failed' ;;
    compile)    echo 'internal compiler error|[Ss]egmentation fault|signal 11|Error [0-9]' ;;
    prime95)    echo 'FATAL ERROR|[Rr]ounding|[Hh]ardware failure' ;;
    *)          echo '[Ee]rror|FATAL|fail' ;;
  esac
}

# tk_extract_core <line> -> echoes the logical-CPU number named in a tool error
# line ("...logical core N..."), or empty string if the line names no core. Pure.
tk_extract_core() {
  printf '%s\n' "$1" | sed -nE 's/.*logical core ([0-9]+).*/\1/p' | head -1
}

# tk_failure_banner <tool-set> <signal-line> <core> [elapsed] -> prints a loud,
# bordered failure banner. ASCII box (portable across terminals/CI). Red only
# when stdout is a TTY, so captured/piped output stays plain for tests.
tk_failure_banner() {
  local set="$1" line="$2" core="$3" elapsed="${4:-}" c="" r=""
  if [ -t 1 ]; then c=$'\033[1;31m'; r=$'\033[0m'; fi
  printf '%s' "$c"
  echo "+================================================+"
  echo "|  X  CPU FAILURE DETECTED                        |"
  echo "+================================================+"
  printf '%s' "$r"
  echo "  tool:    $set"
  echo "  signal:  $line"
  [ -n "$core" ]    && echo "  core:    logical CPU $core"
  [ -n "$elapsed" ] && echo "  elapsed: $elapsed"
  return 0
}

# tk_watch_stream <logfile> <tool-set> : reads lines on stdin, appends each to
# <logfile> AND echoes it (live passthrough), and on the FIRST line matching the
# tool's signature prints a failure banner and returns 1. Returns 0 if the stream
# ends with no match. Pure w.r.t. process control (no killing) — the caller owns
# that. Testable by piping a canned log in.
tk_watch_stream() {
  local log="$1" set="$2" pat line core
  pat="$(tk_sig_pattern "$set")"
  while IFS= read -r line || [ -n "$line" ]; do
    printf '%s\n' "$line" >> "$log"
    printf '%s\n' "$line"
    if printf '%s\n' "$line" | grep -qE "$pat"; then
      core="$(tk_extract_core "$line")"
      tk_failure_banner "$set" "$line" "$core"
      return 1
    fi
  done
  return 0
}

tk_scan_log() {
  local tool="$1" log="$2" pat
  [ -f "$log" ] || { echo "MISSING LOG: $log"; return 1; }
  pat="$(tk_sig_pattern "$tool")"
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

TK_VOLTS_PID=""
# tk_volts_sampler_start <run_dir> <interval> — logs per-core MHz (and voltage if available)
tk_volts_sampler_start() {
  local dir="$1" iv="${2:-5}"
  ( while true; do
      echo "== $(date '+%T') ==" >> "$dir/volts.log"
      grep -E "^cpu MHz" /proc/cpuinfo | nl >> "$dir/volts.log"
      sensors 2>/dev/null | grep -iE "vcore|vid|in0" >> "$dir/volts.log"
      sleep "$iv"
    done ) &
  TK_VOLTS_PID=$!
}
tk_volts_sampler_stop() { [ -n "$TK_VOLTS_PID" ] && kill "$TK_VOLTS_PID" 2>/dev/null; TK_VOLTS_PID=""; }

# tk_busy_cpus <stat_before> <stat_after> -> "cpuN <busy%>" per logical CPU.
# busy% = share of jiffies not spent in idle/iowait between the two /proc/stat
# snapshots. Pure (takes the snapshots as files).
tk_busy_cpus() {
  awk '
    /^cpu[0-9]+ / {
      cpu=$1; tot=0
      for(i=2;i<=NF;i++) tot+=$i
      idle=$5+$6
      if (FNR==NR) { tot0[cpu]=tot; idle0[cpu]=idle }
      else {
        dt=tot-tot0[cpu]; di=idle-idle0[cpu]
        pct = dt>0 ? int(100*(dt-di)/dt) : 0
        print cpu, pct
      }
    }
  ' "$1" "$2"
}

# tk_ab_interpret <suspect_verdict> <control_verdict> -> one-line conclusion.
# Verdicts are runs.csv field 4; only the first word matters. THERMAL counts
# as computationally clean: it means zero errors, package merely hit the
# thermal threshold (both legs do that on an undersized cooler).
tk_ab_interpret() {
  local s="${1%% *}" c="${2%% *}" sbad=0 cbad=0
  case "$s" in FAIL|CRASHED) sbad=1;; esac
  case "$c" in FAIL|CRASHED) cbad=1;; esac
  if   [ "$sbad" -eq 1 ] && [ "$cbad" -eq 0 ]; then
    echo "DEFECT ISOLATED: suspect core fails, control core clean under identical load"
  elif [ "$sbad" -eq 1 ] && [ "$cbad" -eq 1 ]; then
    echo "SYSTEMIC: both cores fail — suspect cooling/board/RAM or chip-wide issue, not a single core"
  elif [ "$sbad" -eq 0 ] && [ "$cbad" -eq 1 ]; then
    echo "UNEXPECTED: control failed while suspect passed — re-check assumptions before concluding"
  else
    echo "NOT REPRODUCED: both cores clean this session — prior crash evidence stands; consider a longer run"
  fi
}

# tk_cpu_model -> the CPU model-name string.
tk_cpu_model() { grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^[[:space:]]*//'; }
# tk_is_affected_intel <model-name-string> -> rc 0 if it is a 13th/14th-gen Intel Core
# i5/i7/i9 (the Raptor Lake / Raptor Lake Refresh chips affected by the Vmin-shift
# degradation), else rc 1. Pure (takes the string as $1).
tk_is_affected_intel() {
  printf '%s\n' "$1" | grep -qE 'Core.*i[579]-1[34][0-9]{3}'
}

# tk_jedec_base <type-string> -> JEDEC max base speed (MT/s) for a DDR generation; 0 if unknown.
tk_jedec_base() {
  case "$1" in
    *DDR5*) echo 5600 ;;
    *DDR4*) echo 3200 ;;
    *DDR3*) echo 2133 ;;
    *) echo 0 ;;
  esac
}

# tk_xmp_state <configured_mts> <jedec_base>
# -> "on" if running above JEDEC base (XMP/EXPO active),
#    "off" if at/below base,
#    "unknown" if configured is empty/0/Unknown or base is 0.
tk_xmp_state() {
  local cfg="${1:-}" base="${2:-0}"
  { [ -z "$cfg" ] || [ "$cfg" = "0" ] || [ "$cfg" = "Unknown" ]; } && { echo unknown; return; }
  [ "${base:-0}" -gt 0 ] || { echo unknown; return; }
  if [ "$cfg" -gt "$base" ]; then echo on; else echo off; fi
}

# tk_pl_state <pl2_watts>
# -> "unlimited" if the short-term power limit looks like an auto-OC / MCE
#    removal of limits (>=1000 W, incl. the 4095 W sentinel), else "ok".
tk_pl_state() {
  local pl2="${1:-0}"
  [ "${pl2:-0}" -ge 1000 ] 2>/dev/null && { echo unlimited; return; }
  echo ok
}

# tk_color <verdict> -> prints verdict, ANSI-colored when stdout is a terminal.
# Green=PASS, Yellow=THERMAL, Red=everything else (FAIL, CRASHED, ...).
tk_color() {
  [ -t 1 ] || { printf '%s' "$1"; return; }
  case "$1" in
    PASS)    printf '\033[32m%s\033[0m' "$1";;
    THERMAL) printf '\033[33m%s\033[0m' "$1";;
    *)       printf '\033[31m%s\033[0m' "$1";;
  esac
}
