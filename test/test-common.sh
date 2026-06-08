#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=assert.sh
. "$HERE/assert.sh"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"

# --- sanity ---
assert_eq "$(tk_version)" "testkit-1.0" "tk_version returns version string"

# --- tk_preferred_cpus: highest-MAXMHZ logical CPUs from lscpu -e text ---
FX="$HERE/fixtures"
assert_eq "$(tk_preferred_cpus < "$FX/lscpu-e.txt")" "8 9 10 11" \
  "tk_preferred_cpus lists the 6.0GHz logical CPUs"

# --- tk_pcore_reps: one representative thread per P-core, fastest first, E-cores excluded ---
assert_eq "$(tk_pcore_reps < "$FX/lscpu-e.txt")" "8 10 0" "tk_pcore_reps: P-core reps fastest-first, E-core (16) excluded"
assert_eq "$(tk_pcore_reps < "$FX/lscpu-e-htoff.txt")" "2 3 0 1" "tk_pcore_reps: HT-off MAXMHZ fallback keeps P-tier, drops 4.4GHz E-cores"
assert_eq "$(tk_pcore_reps < "$FX/lscpu-e-nonhybrid.txt")" "0 2" "tk_pcore_reps: non-hybrid HT chip = all cores are P-cores"

# --- tk_parse_siblings: normalize a kernel thread_siblings_list to a comma pair ---
assert_eq "$(tk_parse_siblings '10-11')" "10,11" "parse_siblings expands a dash range"
assert_eq "$(tk_parse_siblings '10,11')" "10,11" "parse_siblings passes a comma list through"
assert_eq "$(tk_parse_siblings '24')"    "24"    "parse_siblings: single core (E-core, no HT)"
assert_eq "$(tk_parse_siblings '8-11')"  "8,9,10,11" "parse_siblings expands a 4-wide range"

# --- tk_max_temp ---
assert_eq "$(tk_max_temp "$FX/temps.log")" "96" "tk_max_temp finds peak package temp"

# --- tk_scan_log: 0=clean 1=errors ---
tk_scan_log ycruncher "$FX/ycruncher-ok.log" >/dev/null; assert_rc $? 0 "ycruncher ok log = clean"
tk_scan_log ycruncher "$FX/ycruncher-fail.log" >/dev/null; assert_rc $? 1 "ycruncher fail log = error"
tk_scan_log compile   "$FX/compile-fail.log"   >/dev/null; assert_rc $? 1 "compile ICE = error"
tk_scan_log prime95   "$FX/prime95-fail.log"   >/dev/null; assert_rc $? 1 "prime95 FATAL = error"
tk_scan_log stress-ng "$FX/stressng-fail.log"  >/dev/null; assert_rc $? 1 "stress-ng verify fail = error"

# --- overall verdict (errors win over thermal) ---
assert_eq "$(tk_overall_verdict 0 79 95)"  "PASS"          "no errors, cool = PASS"
assert_eq "$(tk_overall_verdict 2 79 95)"  "FAIL (errors)" "errors = FAIL"
assert_eq "$(tk_overall_verdict 0 97 95)"  "THERMAL"       "hot, no errors = THERMAL"
assert_eq "$(tk_overall_verdict 2 97 95)"  "FAIL (errors)" "errors beat thermal"

# --- summary append ---
TMP="$(mktemp -d)"
tk_summary_append "$TMP" "20260606-120000" "90" "core-target" "FAIL (errors)" "88" "3" "core5"
tk_summary_append "$TMP" "20260606-140000" "90" "all" "PASS" "79" "0" "-"
assert_eq "$(grep -c '^| 2026' "$TMP/SUMMARY.md")" "2" "SUMMARY.md has 2 data rows"
assert_eq "$(grep -c '^20260606' "$TMP/runs.csv")" "2" "runs.csv has 2 data rows"
assert_eq "$(head -1 "$TMP/runs.csv")" "timestamp,minutes,tests,verdict,max_pkg_c,errors,notes" "csv header correct"
rm -rf "$TMP"

# --- crash markers ---
TMP="$(mktemp -d)"
mkdir -p "$TMP/20260606-100000" "$TMP/20260606-110000"
printf 'started 2026-06-06 10:00:00\n' > "$TMP/20260606-100000/START"
printf 'core-target @ 2026-06-06 10:04:00\n' > "$TMP/20260606-100000/progress"
# second run completed cleanly:
printf 'started\n' > "$TMP/20260606-110000/START"
printf 'done\n'    > "$TMP/20260606-110000/FINISHED"
out="$(tk_scan_crashed "$TMP")"
assert_eq "$(echo "$out" | grep -c CRASHED)" "1" "tk_scan_crashed finds 1 incomplete run"
assert_eq "$(echo "$out" | grep -c core-target)" "1" "crash line names the in-progress test"
rm -rf "$TMP"

# --- tk_jedec_base ---
assert_eq "$(tk_jedec_base 'DDR5')" "5600" "jedec base DDR5"
assert_eq "$(tk_jedec_base 'DDR4')" "3200" "jedec base DDR4"
assert_eq "$(tk_jedec_base 'DDR3')" "2133" "jedec base DDR3"
assert_eq "$(tk_jedec_base 'LPDDR5')" "5600" "jedec base LPDDR5 (contains DDR5)"
assert_eq "$(tk_jedec_base 'unknown')" "0"    "jedec base unknown type"

# --- tk_xmp_state ---
assert_eq "$(tk_xmp_state 6000 5600)" "on"      "xmp on when above JEDEC"
assert_eq "$(tk_xmp_state 4800 5600)" "off"     "xmp off at JEDEC"
assert_eq "$(tk_xmp_state 5600 5600)" "off"     "xmp off at exactly JEDEC base"
assert_eq "$(tk_xmp_state 3600 3200)" "on"      "ddr4 xmp on"
assert_eq "$(tk_xmp_state 3200 3200)" "off"     "ddr4 xmp off at JEDEC"
assert_eq "$(tk_xmp_state '' 5600)"   "unknown" "xmp unknown when no data"
assert_eq "$(tk_xmp_state 0 5600)"    "unknown" "xmp unknown when 0"
assert_eq "$(tk_xmp_state Unknown 5600)" "unknown" "xmp unknown when 'Unknown'"
assert_eq "$(tk_xmp_state 6000 0)"    "unknown" "xmp unknown when base 0"

# --- tk_pl_state ---
assert_eq "$(tk_pl_state 253)"  "ok"        "pl 253W ok"
assert_eq "$(tk_pl_state 253)"  "ok"        "pl 253W ok (repeat)"
assert_eq "$(tk_pl_state 4095)" "unlimited" "pl 4095W unlimited"
assert_eq "$(tk_pl_state 1000)" "unlimited" "pl 1000W unlimited boundary"
assert_eq "$(tk_pl_state 999)"  "ok"        "pl 999W ok boundary"
assert_eq "$(tk_pl_state 0)"    "ok"        "pl 0W ok"

# --- tk_is_affected_intel ---
tk_is_affected_intel "Intel(R) Core(TM) i9-14900K"; assert_rc $? 0 "14900K is affected"
tk_is_affected_intel "Intel(R) Core(TM) i7-13700K"; assert_rc $? 0 "13700K is affected"
tk_is_affected_intel "Intel(R) Core(TM) i5-12600K"; assert_rc $? 1 "12600K (12th gen) not affected"
tk_is_affected_intel "AMD Ryzen 9 7950X";            assert_rc $? 1 "AMD not affected"
tk_is_affected_intel "Intel(R) Core(TM) Ultra 9 285K"; assert_rc $? 1 "Core Ultra not affected"

# --- tk_busy_cpus: per-CPU busy% from two /proc/stat snapshots ---
assert_eq "$(tk_busy_cpus "$FX/proc-stat-before.txt" "$FX/proc-stat-after.txt")" \
"cpu0 0
cpu10 100
cpu11 50" "tk_busy_cpus computes idle/full/half busy"

# --- tk_ab_interpret: A/B verdict semantics ---
assert_eq "$(tk_ab_interpret 'FAIL (errors)' 'THERMAL')" \
  "DEFECT ISOLATED: suspect core fails, control core clean under identical load" \
  "ab: suspect fail + control thermal-clean = isolated"
assert_eq "$(tk_ab_interpret 'CRASHED (reset)' 'PASS')" \
  "DEFECT ISOLATED: suspect core fails, control core clean under identical load" \
  "ab: suspect crash + control pass = isolated"
assert_eq "$(tk_ab_interpret 'FAIL (errors)' 'FAIL (errors)')" \
  "SYSTEMIC: both cores fail — suspect cooling/board/RAM or chip-wide issue, not a single core" \
  "ab: both fail = systemic"
assert_eq "$(tk_ab_interpret 'PASS' 'CRASHED (reset)')" \
  "UNEXPECTED: control failed while suspect passed — re-check assumptions before concluding" \
  "ab: control-only fail = unexpected"
assert_eq "$(tk_ab_interpret 'THERMAL' 'PASS')" \
  "NOT REPRODUCED: both cores clean this session — prior crash evidence stands; consider a longer run" \
  "ab: both clean = not reproduced"

# --- tk_sig_pattern: shared error regex per tool set ---
assert_eq "$(tk_sig_pattern prime95)" 'FATAL ERROR|[Rr]ounding|[Hh]ardware failure' "sig prime95"
assert_eq "$(tk_sig_pattern stress-ng)" 'fail:|verification failed' "sig stress-ng"
assert_eq "$(tk_sig_pattern ycruncher)" 'Exception|Error [Cc]ode|mismatch|[Cc]oefficient|unstable|Failed' "sig ycruncher"
assert_eq "$(tk_sig_pattern compile)" 'internal compiler error|[Ss]egmentation fault|signal 11|Error [0-9]' "sig compile"
assert_eq "$(tk_sig_pattern anything-else)" '[Ee]rror|FATAL|fail' "sig default fallback"

# --- tk_extract_core: pull the offending logical CPU from a tool error line ---
assert_eq "$(tk_extract_core 'Error(s) encountered on logical core 10.')" "10" "extract core 10"
assert_eq "$(tk_extract_core 'Error(s) encountered on logical core 11.')" "11" "extract core 11"
assert_eq "$(tk_extract_core 'FATAL ERROR: rounding was 0.5')" "" "no core in line -> empty"

tk_test_summary
