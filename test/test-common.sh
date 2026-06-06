#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=assert.sh
. "$HERE/assert.sh"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"

# --- sanity ---
assert_eq "$(tk_version)" "testkit-1.0" "tk_version returns version string"

tk_test_summary
