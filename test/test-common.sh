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

tk_test_summary
