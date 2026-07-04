#!/usr/bin/env bash
# Unit test for the curated RMA report (libexec/report-curated.sh), driven
# through `imcc report --curated` against a fixture results/ dir.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=assert.sh
. "$HERE/assert.sh"
ROOT="$HERE/.."
IMCC="$ROOT/imcc"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/20260101-000001" "$TMP/20260101-000002"

# suspect leg: y-cruncher checksum mismatch on the pinned core
cat > "$TMP/20260101-000001/core-target.log" <<'L'
core-target: pinning y-cruncher stress to logical CPU(s) 10,11
Running BKT: Passed
Exception Encountered: AlgorithmFailedException
Checksum Mismatch
Error(s) encountered on logical core 10.
Stress test failed with 1 error.
L
# control leg: clean pass
cat > "$TMP/20260101-000002/core-target.log" <<'L'
Running BKT: Passed
Running BBP: Passed
Running SFTv4: Passed
L
cat > "$TMP/runs.csv" <<'L'
timestamp,minutes,tests,verdict,max_pkg_c,errors,notes
20260101-000001,10,core-target,FAIL (errors),100,1,suspect cpus=10,11
20260101-000002,10,core-target,THERMAL,100,0,control cpus=8,9
L
cat > "$TMP/crashes.log" <<'L'
Jun 06 12:10:10 fadi-host kernel: kernel BUG at fs/inode.c:753!
L
: > "$TMP/userspace-traps.log"

IMCC_RESULTS="$TMP" "$IMCC" report --curated >/dev/null 2>&1; rc=$?
assert_rc "$rc" 0 "report --curated exits 0"

MD="$TMP/RMA-CLAIM.md"
HTML="$TMP/RMA-CLAIM.html"
[ -f "$MD" ]   && r=ok || r=missing; assert_eq "$r" ok "RMA-CLAIM.md created"
[ -f "$HTML" ] && r=ok || r=missing; assert_eq "$r" ok "RMA-CLAIM.html created"

# expected sections
for s in "Request" "Product identification" "Purchase" "System configuration during testing" "Testing performed" "Observed system errors" "Attachments"; do
  assert_eq "$(grep -c "^## $s" "$MD")" "1" "section present: $s"
done

# placeholders for the non-readable fields
[ "$(grep -c 'FILL IN' "$MD")" -ge 4 ] && r=ok || r=no
assert_eq "$r" ok "has [FILL IN] placeholders for non-readable fields"

# auto-derived A/B evidence made it in
[ "$(grep -c 'Checksum Mismatch' "$MD")" -ge 1 ] && r=ok || r=no
assert_eq "$r" ok "suspect excerpt embedded"
[ "$(grep -c 'control' "$MD")" -ge 1 ] && r=ok || r=no
assert_eq "$r" ok "control leg referenced"

# hostname stripped from crash lines (privacy)
assert_eq "$(grep -c 'fadi-host' "$MD")" "0" "hostname stripped from crash lines"

# HTML well-formed for the primitives used
assert_eq "$(grep -c '<table>' "$HTML")" "$(grep -c '</table>' "$HTML")" "tables balanced"
assert_eq "$(grep -c '<pre>' "$HTML")"   "$(grep -c '</pre>' "$HTML")"   "pre blocks balanced"
assert_eq "$(grep -c '</html>' "$HTML")" "1" "html document closed"

# guard against accidental no-results regression
IMCC_RESULTS="$TMP/empty" "$IMCC" report --curated >/dev/null 2>&1; rc=$?
assert_rc "$rc" 1 "missing results dir exits 1"

tk_test_summary
