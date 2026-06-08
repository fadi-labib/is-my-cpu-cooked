#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=assert.sh
. "$HERE/assert.sh"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"
FX="$HERE/fixtures"

# --- tk_failure_banner: contains the headline, the signal line, and the core ---
out="$(tk_failure_banner ycruncher 'Checksum Mismatch' 10 '0.14 s')"
assert_eq "$(printf '%s\n' "$out" | grep -c 'CPU FAILURE DETECTED')" "1" "banner has headline"
assert_eq "$(printf '%s\n' "$out" | grep -c 'Checksum Mismatch')" "1" "banner shows the signal line"
assert_eq "$(printf '%s\n' "$out" | grep -c 'logical CPU 10')" "1" "banner shows the core"
assert_eq "$(printf '%s\n' "$out" | grep -c 'elapsed: 0.14 s')" "1" "banner shows elapsed"
# core omitted -> no core line
out2="$(tk_failure_banner prime95 'FATAL ERROR' '' '')"
assert_eq "$(printf '%s\n' "$out2" | grep -c 'logical CPU')" "0" "no core line when core empty"

# --- tk_watch_stream: tees to log, detects first error, prints banner, rc 1 ---
tmplog="$(mktemp)"
out="$(tk_watch_stream "$tmplog" ycruncher < "$FX/ycruncher-fail-core.log")"; rc=$?
assert_rc "$rc" 1 "watch_stream returns 1 on error"
assert_eq "$(printf '%s\n' "$out" | grep -c 'CPU FAILURE DETECTED')" "1" "watch_stream printed banner"
assert_eq "$(printf '%s\n' "$out" | grep -c 'logical CPU 10')" "1" "watch_stream banner names core 10"
assert_eq "$(grep -c 'Checksum Mismatch' "$tmplog")" "1" "watch_stream tee'd lines to the log"
rm -f "$tmplog"

# clean stream -> rc 0, no banner
tmplog="$(mktemp)"
out="$(tk_watch_stream "$tmplog" ycruncher < "$FX/ycruncher-ok.log")"; rc=$?
assert_rc "$rc" 0 "watch_stream returns 0 on clean output"
assert_eq "$(printf '%s\n' "$out" | grep -c 'CPU FAILURE DETECTED')" "0" "no banner on clean output"
rm -f "$tmplog"

tk_test_summary
