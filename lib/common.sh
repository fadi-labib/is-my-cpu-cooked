#!/usr/bin/env bash
# lib/common.sh — pure, testable helpers for the CPU testkit.
# Parsing functions take input as args/paths; they never call lscpu/sensors.

tk_version() { echo "testkit-1.0"; }
