#!/usr/bin/env bash
# serial.sh - Decode the Intel processor serial (ATPO) from the 2D Data Matrix
# laser-marked on the CPU lid (IHS). The serial is not software-readable, so an
# Intel RMA form has to be filled from the physical chip; this reads it from a
# photo instead of by eye.
set -euo pipefail

usage() {
  cat <<EOF
imcc serial - read the CPU serial (ATPO) from a photo of the processor lid

usage: ./imcc serial <photo> [photo2 ...]

  Decodes the 2D Data Matrix laser-etched on the CPU heat spreader (IHS).
  Use a clear, well-lit, straight-on photo (wipe thermal paste off the code
  first). Pass several photos/angles; the first that decodes wins.

  The batch/FPO is the plain alphanumeric etched next to the matrix - read
  that one by eye.

Needs: dmtxread (libdmtx) and convert (ImageMagick).
  Debian/Ubuntu:  sudo apt-get install -y dmtx-utils imagemagick
EOF
}

[ $# -ge 1 ] || { usage; exit 2; }
case "${1:-}" in -h|--help|help) usage; exit 0 ;; esac

miss=""
command -v dmtxread >/dev/null 2>&1 || miss="$miss dmtxread(dmtx-utils)"
command -v convert  >/dev/null 2>&1 || miss="$miss convert(imagemagick)"
if [ -n "$miss" ]; then
  echo "missing tools:$miss" >&2
  echo "install: sudo apt-get install -y dmtx-utils imagemagick" >&2
  exit 3
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Try to decode one image: first as-is, then through grayscale/threshold and an
# upscale, across all four rotations (Data Matrix carries its own orientation
# finder, but rotating helps marginal captures). Timeouts cap runtime per try.
decode_one() {
  local img="$1" out rot variant
  out="$(dmtxread -m 3000 -N1 "$img" 2>/dev/null || true)"
  [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  for rot in 0 90 180 270; do
    variant="$TMP/v.png"
    convert "$img" -rotate "$rot" -colorspace Gray -auto-level -threshold 55% \
      "$variant" 2>/dev/null || continue
    out="$(dmtxread -m 4000 -N1 "$variant" 2>/dev/null || true)"
    [ -n "$out" ] && { printf '%s' "$out"; return 0; }
    convert "$img" -rotate "$rot" -colorspace Gray -resize 300% -auto-level \
      -threshold 55% "$variant" 2>/dev/null || continue
    out="$(dmtxread -m 4000 -N1 "$variant" 2>/dev/null || true)"
    [ -n "$out" ] && { printf '%s' "$out"; return 0; }
  done
  return 1
}

rc=1
serial=""
for img in "$@"; do
  [ -f "$img" ] || { echo "skip (not a file): $img" >&2; continue; }
  echo "scanning: $img" >&2
  if serial="$(decode_one "$img")"; then
    echo ""
    echo "Serial (ATPO), decoded from 2D Data Matrix: $serial"
    echo "(Read the batch/FPO - the plain alphanumeric next to the matrix - by eye.)"
    rc=0
    break
  fi
done

if [ "$rc" -ne 0 ]; then
  echo "" >&2
  echo "No Data Matrix decoded. Try a sharper, straight-on, well-lit photo with the" >&2
  echo "thermal paste wiped off the code, or read the serial from the retail-box label." >&2
fi
exit "$rc"
