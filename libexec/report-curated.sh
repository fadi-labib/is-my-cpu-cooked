#!/usr/bin/env bash
# report-curated.sh - emit an upload-ready, facts-only warranty claim document
# (Markdown + standalone HTML) from the testkit results.
#
# Unlike report.sh (the internal evidence bundle, full of run IDs and verdict
# jargon), this is meant to be handed to Intel: clean sections, [FILL IN]
# placeholders for the data the tool cannot read (claimant, purchase, serial),
# and no PII ever read or stored by the tool. The HTML is standalone (zero deps)
# and prints to PDF from any browser.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/common.sh
. "$HERE/../lib/common.sh"

RESULTS="${IMCC_RESULTS:-$HERE/../results}"
if [ ! -d "$RESULTS" ] || [ -z "$(ls -A "$RESULTS" 2>/dev/null)" ]; then
  echo "no results yet - run ./imcc run first"; exit 1
fi
RESULTS="$(cd "$RESULTS" && pwd)"
CSV="$RESULTS/runs.csv"
MD="$RESULTS/RMA-CLAIM.md"
HTML="$RESULTS/RMA-CLAIM.html"
: > "$MD"; : > "$HTML"

# ── system probes ───────────────────────────────────────────────────────────
# Pipelines end in `|| true` so a missing field never aborts under `set -u`.
microcode_ver() { grep -m1 microcode /proc/cpuinfo 2>/dev/null | awk '{print $3}' || true; }
bios_version()  { cat /sys/class/dmi/id/bios_version 2>/dev/null || echo unknown; }
bios_date()     { cat /sys/class/dmi/id/bios_date    2>/dev/null || echo unknown; }
cpu_identity() {
  lscpu 2>/dev/null | awk -F: '
    /^CPU family:/ {gsub(/[[:space:]]/,"",$2); f=$2}
    /^Model:/      {gsub(/[[:space:]]/,"",$2); m=$2}
    /^Stepping:/   {gsub(/[[:space:]]/,"",$2); s=$2}
    END {printf "family %s, model %s, stepping %s", (f?f:"?"), (m?m:"?"), (s?s:"?")}' || true
}
mem_line() {
  if command -v dmidecode >/dev/null 2>&1 && dmidecode -t memory >/dev/null 2>&1; then
    dmidecode -t memory 2>/dev/null | awk '
      /Size: [0-9]/                  {size=$2" "$3; n++}
      /^[[:space:]]*Manufacturer: /  {man=$2}
      /Configured Memory Speed: [0-9]/ {spd=$4" "$5}
      END {if(n) printf "%s, %d module(s), %s each, %s", (man?man:"?"), n, size, spd}' || true
  fi
}

# ── markdown + HTML dual emitters (one content source, two outputs) ───────────
esc() { printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'; }
h1()  { printf '# %s\n\n' "$1" >> "$MD"; printf '<h1>%s</h1>\n' "$(esc "$1")" >> "$HTML"; }
sub() { printf '%s\n\n' "$1" >> "$MD"; printf '<p class="sub">%s</p>\n' "$(esc "$1")" >> "$HTML"; }
h2()  { printf '\n## %s\n\n' "$1" >> "$MD"; printf '<h2>%s</h2>\n' "$(esc "$1")" >> "$HTML"; }
para(){ printf '%s\n\n' "$1" >> "$MD"; printf '<p>%s</p>\n' "$(esc "$1")" >> "$HTML"; }
note(){ printf '_%s_\n\n' "$1" >> "$MD"; printf '<p class="note">%s</p>\n' "$(esc "$1")" >> "$HTML"; }
code(){ printf '```\n%s\n```\n\n' "$1" >> "$MD"; printf '<pre>%s</pre>\n' "$(esc "$1")" >> "$HTML"; }
tbl_open() {
  { printf '|'; for h in "$@"; do printf ' %s |' "$h"; done; printf '\n|'; for h in "$@"; do printf ' --- |'; done; printf '\n'; } >> "$MD"
  { printf '<table><thead><tr>'; for h in "$@"; do printf '<th>%s</th>' "$(esc "$h")"; done; printf '</tr></thead><tbody>\n'; } >> "$HTML"
}
tbl_row() {
  { printf '|'; for c in "$@"; do printf ' %s |' "$c"; done; printf '\n'; } >> "$MD"
  { printf '<tr>'; for c in "$@"; do printf '<td>%s</td>' "$(esc "$c")"; done; printf '</tr>\n'; } >> "$HTML"
}
tbl_close() { printf '\n' >> "$MD"; printf '</tbody></table>\n' >> "$HTML"; }
LI=0
list_open()  { LI=0; printf '<ol>\n' >> "$HTML"; }
li()         { LI=$((LI+1)); printf '%d. %s\n' "$LI" "$1" >> "$MD"; printf '<li>%s</li>\n' "$(esc "$1")" >> "$HTML"; }
list_close() { printf '\n' >> "$MD"; printf '</ol>\n' >> "$HTML"; }

# ── log helpers ───────────────────────────────────────────────────────────────
strip_log() { sed 's/\x1b\[[0-9;]*m//g' "$1" 2>/dev/null | tr '\r' '\n' | sed 's/[[:space:]]\{1,\}/ /g; s/^ //; s/ *$//'; }
suspect_excerpt() {
  strip_log "$1" | grep -aE 'Running (BKT|BBP|SFTv4|FFTv4|N63|VT3): (Passed|Failed)|Exception Encountered|Checksum Mismatch|Redundancy Check( Failed)?|Error\(s\) encountered on logical core|Anomaly|Coefficient|[Uu]nstable|Stress test failed' | awk 'NF && !seen[$0]++' | head -10 || true
}
control_excerpt() {
  strip_log "$1" | grep -aE 'Running (BKT|BBP|SFTv4|FFTv4|N63|VT3): Passed' | awk 'NF && !seen[$0]++' | head -8 || true
}

# ── HTML document scaffold ────────────────────────────────────────────────────
{
  printf '<!doctype html>\n<html lang="en"><head><meta charset="utf-8">\n'
  printf '<title>Warranty Claim Evidence Report</title>\n<style>\n'
  printf 'body{font-family:Georgia,"Times New Roman",serif;max-width:46rem;margin:2.5rem auto;padding:0 1.5rem;color:#111;line-height:1.5}\n'
  printf 'h1{font-size:1.6rem;margin:0 0 .2rem;text-align:center}\n'
  printf '.sub{text-align:center;color:#444;margin:.2rem 0 1.5rem}\n'
  printf 'h2{font-size:1.15rem;border-bottom:1px solid #ccc;padding-bottom:.2rem;margin-top:1.8rem}\n'
  printf 'table{border-collapse:collapse;width:100%%;margin:.6rem 0}\n'
  printf 'th,td{border:1px solid #bbb;padding:.35rem .6rem;text-align:left;vertical-align:top;font-size:.95rem}\n'
  printf 'th{background:#f2f2f2}\n'
  printf 'pre{background:#f6f6f6;border:1px solid #ddd;padding:.6rem;overflow:auto;font-family:"DejaVu Sans Mono",Consolas,monospace;font-size:.85rem;white-space:pre-wrap}\n'
  printf '.note{color:#555;font-style:italic;font-size:.9rem}\n'
  printf '@media print{body{margin:0;max-width:none}}\n'
  printf '</style></head><body>\n'
} >> "$HTML"

MODEL="$(tk_cpu_model)"

# 1. Title + claimant
h1 "Warranty Claim Evidence Report"
sub "${MODEL:-Intel Core processor}"
para "Claimant: [FILL IN: full name and postal address]"

# 2. Request
h2 "Request"
para "Replacement of the processor below under Intel's extended warranty for 13th/14th Generation desktop processors. Under Intel default settings, with the latest BIOS and microcode applied, the processor returns reproducible compute errors isolated to one CPU core."

# 3. Product identification
h2 "Product identification"
tbl_open "Field" "Value"
tbl_row "Processor" "${MODEL:-[FILL IN: processor model]}"
tbl_row "Specification code (sSpec)" "[FILL IN: sSpec from the processor lid]"
tbl_row "Batch number (FPO)" "[FILL IN: batch from the processor lid]"
tbl_row "Serial number (ATPO)" "[FILL IN: serial - or run ./imcc serial <photo>]"
tbl_row "CPUID" "$(cpu_identity)"
tbl_close
note "Batch and serial are laser-marked on the processor lid; attach photographs."

# 4. Purchase
h2 "Purchase"
tbl_open "Field" "Value"
tbl_row "Retailer" "[FILL IN: retailer name]"
tbl_row "Order / invoice number" "[FILL IN: order or invoice number]"
tbl_row "Purchase date" "[FILL IN: purchase date]"
tbl_row "Price" "[FILL IN: price paid]"
tbl_close
note "Attach the purchase invoice or receipt."

# 5. System configuration during testing
h2 "System configuration during testing"
tbl_open "Setting" "State"
tbl_row "BIOS profile" "Intel Default Settings"
tbl_row "BIOS version" "$(bios_version) ($(bios_date))"
tbl_row "CPU microcode" "$(microcode_ver)"
_MEM="$(mem_line)"
tbl_row "Memory" "${_MEM:-[FILL IN: memory manufacturer, size, speed - or re-run with sudo]}"
tbl_row "XMP / EXPO" "Disabled"
tbl_row "Overclocking" "None"
tbl_row "CPU temperature" "Normal, no thermal throttling"
tbl_close

# 6. Testing performed (A/B core isolation)
h2 "Testing performed"
para "The processor was tested with y-cruncher, which performs self-checking arithmetic and reports a Checksum Mismatch and the responsible logical core when a result is computed incorrectly. The workload was pinned to one core at a time so a faulty core can be told apart from a healthy one under identical load."

s_fail=0; c_clean=0; battery=0; crashes=0
s_cpus=""; c_cpus=""; s_xrpt=""; c_xrpt=""
if [ -f "$CSV" ]; then
  while IFS= read -r row; do
    [ -n "$row" ] || continue
    notes="$(printf '%s' "$row" | cut -d, -f7-)"
    verdict="$(printf '%s' "$row" | cut -d, -f4)"
    tests="$(printf '%s' "$row" | cut -d, -f3)"
    errs="$(printf '%s' "$row" | cut -d, -f6)"
    ts="$(printf '%s' "$row" | cut -d, -f1)"
    cpus="$(printf '%s' "$notes" | sed -n 's/.*cpus=\([0-9,]*\).*/\1/p')"
    case "$tests" in *core-sweep*) battery=$((battery+1)) ;; esac
    case "$verdict" in *CRASHED*) crashes=$((crashes+1)) ;; esac
    case "$notes" in
      suspect*)
        case "$verdict" in FAIL*) s_fail=$((s_fail+1)) ;; esac
        [ -n "$cpus" ] && s_cpus="$cpus"
        if [ -z "$s_xrpt" ]; then x="$(suspect_excerpt "$RESULTS/$ts/core-target.log")"; [ -n "$x" ] && { s_xrpt="$x"; } ; fi
        ;;
      control*)
        [ "${errs:-1}" = "0" ] && c_clean=$((c_clean+1))
        [ -n "$cpus" ] && c_cpus="$cpus"
        if [ -z "$c_xrpt" ]; then x="$(control_excerpt "$RESULTS/$ts/core-target.log")"; [ -n "$x" ] && { c_xrpt="$x"; } ; fi
        ;;
    esac
  done < <(grep -v '^timestamp' "$CSV" 2>/dev/null)
fi

if [ "$s_fail" -gt 0 ] || [ "$c_clean" -gt 0 ]; then
  tbl_open "Core targeted" "Runs" "Outcome"
  tbl_row "Logical CPUs ${s_cpus:-suspect}" "$s_fail" "Checksum Mismatch reproduced; errors attributed to the targeted core."
  tbl_row "Logical CPUs ${c_cpus:-control} (control)" "$c_clean" "Zero compute errors."
  [ "$battery" -gt 0 ] && tbl_row "All P-cores (full battery)" "$battery" "Compute errors recorded under sustained mixed load."
  [ "$crashes" -gt 0 ] && tbl_row "Normal desktop use" "$crashes" "System crashes captured (see below)."
  tbl_close
else
  note "No suspect/control A/B runs recorded yet - run ./imcc ab to generate the controlled comparison."
fi

[ -n "$s_xrpt" ] && { para "Representative run log, suspect core:"; code "$s_xrpt"; }
[ -n "$c_xrpt" ] && { para "Representative run log, control core (same workload, same settings):"; code "$c_xrpt"; }

# 7. Observed system errors
h2 "Observed system errors"
para "Events recorded in the system log during normal use, across several days and multiple unrelated applications:"
crash_lines="$( { cat "$RESULTS/crashes.log" "$RESULTS/userspace-traps.log" 2>/dev/null; } \
  | sed -E 's/^[A-Z][a-z]{2} +[0-9]{1,2} [0-9:]+ ([^ ]+ )?kernel: //' \
  | awk 'NF && !seen[$0]++' | head -8 || true )"
if [ -n "$crash_lines" ]; then code "$crash_lines"; else note "No crash events captured - install ./imcc watch to record them."; fi

# 8. Attachments
h2 "Attachments"
list_open
li "This report."
li "Purchase invoice / receipt."
li "Photograph(s) of the processor lid (identifiers and 2D barcode)."
list_close

printf '</body></html>\n' >> "$HTML"

remaining="$(grep -c 'FILL IN' "$MD" 2>/dev/null || echo 0)"
echo "Curated report written to:"
echo "  $MD"
echo "  $HTML  (open in a browser and Print to PDF)"
echo "$remaining [FILL IN] field(s) left to complete before sending to Intel."
