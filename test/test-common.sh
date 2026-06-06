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

tk_test_summary
