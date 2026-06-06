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

# --- tk_max_temp ---
assert_eq "$(tk_max_temp "$FX/temps.log")" "96" "tk_max_temp finds peak package temp"

# --- tk_scan_log: 0=clean 1=errors ---
tk_scan_log ycruncher "$FX/ycruncher-ok.log" >/dev/null; assert_rc $? 0 "ycruncher ok log = clean"
tk_scan_log ycruncher "$FX/ycruncher-fail.log" >/dev/null; assert_rc $? 1 "ycruncher fail log = error"
tk_scan_log compile   "$FX/compile-fail.log"   >/dev/null; assert_rc $? 1 "compile ICE = error"
tk_scan_log prime95   "$FX/prime95-fail.log"   >/dev/null; assert_rc $? 1 "prime95 FATAL = error"
tk_scan_log stress-ng "$FX/stressng-fail.log"  >/dev/null; assert_rc $? 1 "stress-ng verify fail = error"

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

tk_test_summary
