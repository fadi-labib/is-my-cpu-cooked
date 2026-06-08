#!/usr/bin/env bash
# $1 = marker path that must NOT be written if the watchdog kills us promptly.
echo "Running stress test..."
echo "ERROR: Coefficient mismatch detected. Hardware is unstable."
sleep 30
echo "survived" > "$1"
