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
