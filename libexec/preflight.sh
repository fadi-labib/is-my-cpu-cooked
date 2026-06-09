#!/usr/bin/env bash
# preflight.sh - verify BIOS baseline before trusting stress results.
# Checks: CPU model, microcode version, RAPL power limits, RAM XMP/EXPO state,
# and CPU frequency governor.
# Usage: ./imcc check            (skips RAM/XMP check without root)
#        sudo ./imcc check       (full check including dmidecode for XMP)
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"

# --- label helpers: print coloured marker when stdout is a TTY, plain text otherwise ---
pf_pass()  { [ -t 1 ] && printf '\033[32m[PASS]\033[0m ' || printf '[PASS] '; }
pf_warn()  { [ -t 1 ] && printf '\033[33m[WARN]\033[0m ' || printf '[WARN] '; }
pf_info()  { printf '[INFO] '; }

HARD_CONFOUNDERS=""   # accumulate labels; non-empty -> exit 1
SOFT_WARNINGS=""

pf_add_hard() { HARD_CONFOUNDERS="${HARD_CONFOUNDERS:+$HARD_CONFOUNDERS, }$1"; }
pf_add_warn()  { SOFT_WARNINGS="${SOFT_WARNINGS:+$SOFT_WARNINGS, }$1"; }

echo "====== preflight baseline check ======"
echo

# --- CPU model & affected-Intel status ---
MODEL="$(tk_cpu_model)"
echo "CPU:       $MODEL"
if tk_is_affected_intel "$MODEL"; then
  echo "           -> 13th/14th-gen Raptor Lake - in scope for Vmin-shift testing"
else
  echo "           -> not a 13th/14th-gen Intel Core i5/i7/i9 (kit still usable, results advisory)"
fi
echo

# --- Microcode ---
MICROCODE="$(grep -m1 microcode /proc/cpuinfo | awk '{print $3}')"
printf "Microcode: %s  " "${MICROCODE:-n/a}"
THRESHOLD="0x12b"
# Numeric hex compare; guard against non-hex strings
if [ -n "${MICROCODE:-}" ] && printf '%s' "$MICROCODE" | grep -qE '^0x[0-9a-fA-F]+$'; then
  MC_INT=$(( MICROCODE ))
  THR_INT=$(( THRESHOLD ))
  if [ "$MC_INT" -lt "$THR_INT" ]; then
    pf_warn; echo "microcode older than 0x12B degradation mitigation - update BIOS"
    pf_add_warn "microcode-old"
  else
    pf_pass; echo "microcode >= 0x12B"
  fi
else
  pf_info; echo "microcode value not parseable as hex - check manually"
fi
echo

# --- Power limits via RAPL ---
PL1_FILE="/sys/class/powercap/intel-rapl:0/constraint_0_power_limit_uw"
PL2_FILE="/sys/class/powercap/intel-rapl:0/constraint_1_power_limit_uw"
if [ -r "$PL1_FILE" ] && [ -r "$PL2_FILE" ]; then
  PL1_UW="$(cat "$PL1_FILE" 2>/dev/null || echo 0)"
  PL2_UW="$(cat "$PL2_FILE" 2>/dev/null || echo 0)"
  PL1=$(( PL1_UW / 1000000 ))
  PL2=$(( PL2_UW / 1000000 ))
  PL_STATE="$(tk_pl_state "$PL2")"
  printf "Power limits: PL1=%dW PL2=%dW  " "$PL1" "$PL2"
  if [ "$PL_STATE" = "unlimited" ]; then
    pf_warn; echo "power limits removed - disable ASUS MultiCore Enhancement / set Intel Default"
    pf_add_hard "PL-unlimited"
  else
    pf_pass; echo "within expected range"
  fi
else
  pf_info; echo "Power limits: n/a (intel-rapl not available)"
fi
echo

# --- RAM / XMP via dmidecode ---
if dmidecode -t memory > /dev/null 2>&1; then
  # Parse first populated (non-"No Module Installed") DIMM
  DMI_OUT="$(dmidecode -t memory 2>/dev/null)"
  # Extract block for first slot that has a real module
  MEM_BLOCK="$(printf '%s\n' "$DMI_OUT" | awk '
    /^Memory Device$/ { in_block=1; block="" }
    in_block { block = block "\n" $0 }
    in_block && /No Module Installed/ { in_block=0; block="" }
    in_block && /^$/ && block ~ /Configured Memory Speed:/ {
      if (found==0) { print block; found=1 }
      in_block=0
    }
    END { if (found==0 && block != "") print block }
  ')"

  if [ -n "$MEM_BLOCK" ]; then
    RAM_TYPE="$(printf '%s\n' "$MEM_BLOCK" | grep -m1 '^\s*Type:' | awk '{print $NF}')"
    # Extract the numeric part of "Configured Memory Speed: XXXX MT/s" (or "Unknown")
    RAM_CFG_STR="$(printf '%s\n' "$MEM_BLOCK" | grep -m1 'Configured Memory Speed:' | \
      sed -E 's/.*Configured Memory Speed:[[:space:]]*//' | awk '{print $1}')"
    # $RAM_CFG_STR is now the numeric speed or "Unknown"

    JEDEC_BASE="$(tk_jedec_base "${RAM_TYPE:-unknown}")"
    XMP_STATE="$(tk_xmp_state "$RAM_CFG_STR" "$JEDEC_BASE")"

    printf "RAM/XMP:   %s running %s MT/s (JEDEC base %s MT/s) -> XMP/EXPO %s  " \
      "${RAM_TYPE:-unknown}" "${RAM_CFG_STR:-?}" "$JEDEC_BASE" "$XMP_STATE"
    case "$XMP_STATE" in
      on)
        pf_warn; echo "XMP/EXPO enabled - disable to test at stock"
        pf_add_hard "XMP-on"
        ;;
      off)
        pf_pass; echo "running at JEDEC base speed"
        ;;
      unknown)
        pf_info; echo "could not determine XMP state"
        ;;
    esac
  else
    pf_info; echo "RAM/XMP:   dmidecode ran but no populated DIMM slot found"
  fi
else
  pf_info; echo "RAM/XMP:   needs root - re-run as: sudo ./imcc check"
fi
echo

# --- CPU frequency governor ---
GOV_FILE="/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor"
if [ -r "$GOV_FILE" ]; then
  GOV="$(cat "$GOV_FILE" 2>/dev/null)"
  printf "Governor:  %s  " "$GOV"
  if [ "$GOV" = "performance" ] || [ "$GOV" = "powersave" ]; then
    pf_pass; echo ""
  else
    pf_info; echo "(non-standard governor; 'performance' or 'powersave' are typical)"
  fi
else
  pf_info; echo "Governor:  n/a"
fi
echo

# --- Overall verdict ---
echo "--------------------------------------"
if [ -n "$HARD_CONFOUNDERS" ]; then
  if [ -t 1 ]; then
    printf '\033[31mCONFOUNDERS PRESENT\033[0m'
  else
    printf 'CONFOUNDERS PRESENT'
  fi
  echo " - a FAIL may not be the CPU."
  echo "Fix: $HARD_CONFOUNDERS"
  [ -n "$SOFT_WARNINGS" ] && echo "Also review: $SOFT_WARNINGS"
  exit 1
else
  if [ -t 1 ]; then
    printf '\033[32mBASELINE OK\033[0m'
  else
    printf 'BASELINE OK'
  fi
  echo " - a FAIL can be trusted as the CPU."
  [ -n "$SOFT_WARNINGS" ] && echo "Advisory: $SOFT_WARNINGS"
  exit 0
fi
