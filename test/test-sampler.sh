#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/assert.sh"
. "$HERE/../lib/common.sh"

TMP="$(mktemp -d)"
tk_temp_sampler_start "$TMP" 1
sleep 2
tk_temp_sampler_stop
lines=$(wc -l < "$TMP/temps.log" 2>/dev/null || echo 0)
# at least one sample collected (or 0 gracefully if sensors absent)
if command -v sensors >/dev/null; then
  [ "$lines" -ge 1 ] && echo "  ok: sampler wrote $lines line(s)" || { echo "  FAIL: sampler wrote nothing"; }
else
  echo "  skip: sensors not installed"
fi
rm -rf "$TMP"
