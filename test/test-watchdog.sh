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

tk_test_summary
