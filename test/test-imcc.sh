#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=assert.sh
. "$HERE/assert.sh"
ROOT="$HERE/.."
IMCC="$ROOT/imcc"

# help and bare invocation both print usage and exit 0
out="$("$IMCC" help)"; rc=$?
assert_rc "$rc" 0 "imcc help exits 0"
assert_eq "$(printf '%s\n' "$out" | grep -c 'usage: ./imcc')" "1" "help prints usage"
out="$("$IMCC")"; rc=$?
assert_rc "$rc" 0 "bare imcc exits 0"
assert_eq "$(printf '%s\n' "$out" | grep -c 'usage: ./imcc')" "1" "bare imcc prints usage"

# unknown command -> non-zero exit, names the bad command
out="$("$IMCC" bogus 2>&1)"; rc=$?
assert_rc "$rc" 2 "unknown command exits 2"
assert_eq "$(printf '%s\n' "$out" | grep -c "unknown command 'bogus'")" "1" "unknown command is named"

# warranty -> exit 0, shows the Intel support URL
out="$("$IMCC" warranty)"; rc=$?
assert_rc "$rc" 0 "warranty exits 0"
assert_eq "$(printf '%s\n' "$out" | grep -c 'intel.com')" "1" "warranty shows Intel support URL"

# rma is a hidden alias for warranty
out="$("$IMCC" rma)"; rc=$?
assert_rc "$rc" 0 "rma alias exits 0"
assert_eq "$(printf '%s\n' "$out" | grep -c 'intel.com')" "1" "rma alias shows Intel support URL"

# serial with no photo -> usage + exit 2 (before any dependency check)
out="$("$IMCC" serial 2>&1)"; rc=$?
assert_rc "$rc" 2 "serial with no arg exits 2"
assert_eq "$(printf '%s\n' "$out" | grep -c 'usage: ./imcc serial')" "1" "serial prints its usage"
# serial --help -> exit 0
out="$("$IMCC" serial --help 2>&1)"; rc=$?
assert_rc "$rc" 0 "serial --help exits 0"

# version -> prints tk_version
out="$("$IMCC" version)"; rc=$?
assert_rc "$rc" 0 "version exits 0"
assert_eq "$out" "testkit-1.0" "version prints tk_version"

# dispatch-table integrity: every delegating target exists and is executable
for t in setup.sh preflight.sh run-all.sh ab-evidence.sh serial.sh report.sh report-curated.sh; do
  if [ -x "$ROOT/libexec/$t" ]; then r=ok; else r=missing; fi
  assert_eq "$r" "ok" "libexec/$t exists and is executable"
done
if [ -x "$ROOT/watcher/install-watcher.sh" ]; then r=ok; else r=missing; fi
assert_eq "$r" "ok" "watcher/install-watcher.sh exists and is executable"

tk_test_summary
