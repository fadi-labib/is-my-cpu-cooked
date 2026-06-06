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

echo "==> apt deps (stress-ng, build-essential, lm-sensors, util-linux, xz, curl)"
sudo apt update
sudo apt install -y stress-ng build-essential lm-sensors util-linux xz-utils curl

echo "==> y-cruncher"
if [ ! -x "$VENDOR"/y-cruncher*/y-cruncher ]; then
  curl -fL "$YCRUNCHER_URL" -o /tmp/yc.tar.xz
  tar -xf /tmp/yc.tar.xz -C "$VENDOR"
fi

echo "==> mprime (Prime95)"
if [ ! -x "$VENDOR/mprime/mprime" ]; then
  mkdir -p "$VENDOR/mprime"
  curl -fL "$MPRIME_URL" -o /tmp/mprime.tar.gz
  tar -xf /tmp/mprime.tar.gz -C "$VENDOR/mprime"
fi

echo "==> done. Tools in $VENDOR"
echo "NOTE: download URLs/versions are pinned; if a 404 occurs, update the *_VER/*_URL vars."
