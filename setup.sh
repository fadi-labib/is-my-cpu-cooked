#!/usr/bin/env bash
# Installs/fetches everything the testkit needs. Idempotent. Run once.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
VENDOR="$HERE/vendor"
mkdir -p "$VENDOR"

YCRUNCHER_VER="0.8.5.9545"
YCRUNCHER_URL="https://github.com/Mysticial/y-cruncher/releases/download/${YCRUNCHER_VER}/y-cruncher.v${YCRUNCHER_VER}.tar.xz"
MPRIME_VER="30.19"
MPRIME_URL="https://www.mersenne.org/download/software/v30/30.19/p95v3019b20.linux64.tar.gz"

# ── download integrity helpers ────────────────────────────────────────────────
#
# How to pin hashes:
#   Run setup.sh once without a checksums file; it will print the sha256 of each
#   downloaded archive.  Copy those lines verbatim into vendor/checksums.sha256:
#
#     <sha256hex>  <basename>
#
#   Example:
#     a1b2c3...  yc.tar.xz
#     d4e5f6...  mprime.tar.gz
#
#   On subsequent runs the downloads are verified against those pinned values and
#   the script aborts if they do not match.
#
CHECKSUMS="$VENDOR/checksums.sha256"

# verify_archive <file> <label>
#   (a) checks file is non-empty and looks like the expected archive type
#   (b) prints its sha256 so the user can record/compare it
#   (c) verifies against $CHECKSUMS if that file exists
verify_archive() {
  local f="$1" label="$2"
  local base; base="$(basename "$f")"

  # (a) non-empty guard
  if [ ! -s "$f" ]; then
    echo "ERROR: $label download is empty: $f" >&2
    exit 1
  fi

  # (a) archive-type guard — reject HTML error pages and other non-archives
  local ftype; ftype="$(file --brief "$f")"
  case "$ftype" in
    *HTML*|*html*|*ASCII\ text*|*UTF-8\ Unicode\ text*)
      echo "ERROR: $label download looks like an HTML error page, not an archive." >&2
      echo "       file type reported: $ftype" >&2
      echo "       Check the URL and try again." >&2
      exit 1
      ;;
    *XZ\ compressed*|*gzip\ compressed*|*tar\ archive*|*Zip\ archive*|*POSIX\ tar*)
      : # expected archive types — continue
      ;;
    *)
      # Warn but don't abort for unexpected-but-non-HTML types
      echo "WARNING: $label archive has unexpected type: $ftype" >&2
      ;;
  esac

  # (b) print sha256 so the user can record it
  local sum; sum="$(sha256sum "$f" | awk '{print $1}')"
  echo "  sha256($base) = $sum"

  # (c) verify against pinned checksums file if it exists
  if [ -f "$CHECKSUMS" ]; then
    local pinned; pinned="$(awk -v b="$base" '$2==b{print $1}' "$CHECKSUMS")"
    if [ -z "$pinned" ]; then
      echo "  (no pinned hash for $base in $CHECKSUMS — skipping pin check)"
    elif [ "$sum" != "$pinned" ]; then
      echo "ERROR: sha256 mismatch for $label ($base)!" >&2
      echo "  expected: $pinned" >&2
      echo "  got:      $sum" >&2
      echo "  Delete $f and re-run, or update $CHECKSUMS." >&2
      exit 1
    else
      echo "  checksum OK (matched $CHECKSUMS)"
    fi
  else
    echo "  (tip: copy the line above into $CHECKSUMS to pin this hash for future runs)"
  fi
}

echo "==> apt deps (stress-ng, build-essential, lm-sensors, util-linux, xz, curl)"
sudo apt update
sudo apt install -y stress-ng build-essential lm-sensors util-linux xz-utils curl

echo "==> y-cruncher"
if [ ! -x "$VENDOR"/y-cruncher*/y-cruncher ]; then
  curl -fL "$YCRUNCHER_URL" -o /tmp/yc.tar.xz
  verify_archive /tmp/yc.tar.xz "y-cruncher"
  tar -xf /tmp/yc.tar.xz -C "$VENDOR"
fi

echo "==> mprime (Prime95)"
if [ ! -x "$VENDOR/mprime/mprime" ]; then
  mkdir -p "$VENDOR/mprime"
  curl -fL "$MPRIME_URL" -o /tmp/mprime.tar.gz
  verify_archive /tmp/mprime.tar.gz "mprime"
  tar -xf /tmp/mprime.tar.gz -C "$VENDOR/mprime"
fi

echo "==> done. Tools in $VENDOR"
echo "NOTE: download URLs/versions are pinned; if a 404 occurs, update the *_VER/*_URL vars."
