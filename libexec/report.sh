#!/usr/bin/env bash
# report.sh — Bundles testkit results into a single Markdown file suitable for
# attaching to an Intel support / RMA ticket.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../lib/common.sh"
RESULTS="$HERE/../results"

# ── guard: no results yet ──────────────────────────────────────────────────────
if [ ! -d "$RESULTS" ] || [ -z "$(ls -A "$RESULTS" 2>/dev/null)" ]; then
  echo "no results yet — run ./imcc run first"
  exit 1
fi

# Find run dirs (dirs with a timestamp name, not the flat files)
mapfile -t RUN_DIRS < <(find "$RESULTS" -mindepth 1 -maxdepth 1 -type d | sort)
if [ "${#RUN_DIRS[@]}" -eq 0 ]; then
  echo "no results yet — run ./imcc run first"
  exit 1
fi

# ── most-recent run dir → sysinfo ─────────────────────────────────────────────
LATEST="${RUN_DIRS[-1]}"
SYSINFO_FILE="$LATEST/sysinfo.txt"
SYSINFO=""
if [ -f "$SYSINFO_FILE" ]; then
  SYSINFO="$(cat "$SYSINFO_FILE")"
fi

OUT="$RESULTS/RMA-REPORT.md"
REPORT_DATE="$(date '+%F %T')"

# ── helpers ───────────────────────────────────────────────────────────────────
microcode_ver() { grep -m1 microcode /proc/cpuinfo | awk '{print $3}'; }
bios_version()  { cat /sys/class/dmi/id/bios_version 2>/dev/null || echo "unknown"; }
bios_date()     { cat /sys/class/dmi/id/bios_date    2>/dev/null || echo "unknown"; }

# ── CSV → Markdown table ──────────────────────────────────────────────────────
csv_to_md_table() {
  local csv="$1"
  [ -f "$csv" ] || { echo "none"; return; }
  awk -F, '
    NR==1 {
      n=split($0,h,",")
      printf "|"
      for(i=1;i<=n;i++) printf " %s |", h[i]
      printf "\n|"
      for(i=1;i<=n;i++) printf " --- |"
      printf "\n"
      next
    }
    {
      n=split($0,f,",")
      printf "|"
      for(i=1;i<=n;i++) printf " %s |", f[i]
      printf "\n"
    }
  ' "$csv"
}

# ── verdict tally ─────────────────────────────────────────────────────────────
verdict_tally() {
  local csv="$1"
  [ -f "$csv" ] || { echo "no runs.csv found"; return; }
  local pass fail crashed thermal
  pass=$(    grep -v '^timestamp' "$csv" | awk -F, '$4=="PASS"' | wc -l)
  fail=$(    grep -v '^timestamp' "$csv" | awk -F, '$4 ~ /^FAIL/'  | wc -l)
  crashed=$( grep -v '^timestamp' "$csv" | awk -F, '$4 ~ /CRASHED/' | wc -l)
  thermal=$( grep -v '^timestamp' "$csv" | awk -F, '$4=="THERMAL"' | wc -l)
  echo "| Verdict | Count |"
  echo "| --- | --- |"
  echo "| PASS | $pass |"
  echo "| FAIL (errors) | $fail |"
  echo "| CRASHED | $crashed |"
  echo "| THERMAL | $thermal |"
}

# ── per-core attribution (which logical core produced errors) ────────────────
# y-cruncher names the failing core ("Error(s) encountered on logical core N");
# paired with the pinned target this shows fail/pass isolation between cores.
core_attribution() {
  local d log strip target fail reason verdict any=0
  for d in "${RUN_DIRS[@]}"; do
    log="$d/core-target.log"
    [ -f "$log" ] || continue
    if [ "$any" -eq 0 ]; then
      echo "| run | target CPU(s) | verdict | error attribution |"
      echo "| --- | --- | --- | --- |"
      any=1
    fi
    strip="$(sed 's/\x1b\[[0-9;]*m//g' "$log")"
    target="$(printf '%s\n' "$strip" | sed -n 's/.*logical CPU[s() ]*\([0-9,]*\) for .*/\1/p' | head -1)"
    fail="$(printf '%s\n' "$strip" | grep -m1 -oE 'Error\(s\) encountered on logical core [0-9]+' || true)"
    reason="$(printf '%s\n' "$strip" | grep -m1 -oE 'Checksum Mismatch|Redundancy Check Failed' || true)"
    verdict="$(awk '{print $1; exit}' "$d/verdict.txt" 2>/dev/null || echo '-')"
    echo "| $(basename "$d") | ${target:-?} | ${verdict:-?} | ${fail:-none}${reason:+ ($reason)} |"
  done
  [ "$any" -eq 0 ] && echo "no core-target runs recorded"
  return 0
}

# ── fenced log block ──────────────────────────────────────────────────────────
fenced_log() {
  local f="$1"
  if [ -f "$f" ] && [ -s "$f" ]; then
    echo '```'
    cat "$f"
    echo '```'
  else
    echo "none recorded"
  fi
}

# ── write report ──────────────────────────────────────────────────────────────
{
  echo "# Intel RMA Report — CPU Degradation Testkit"
  echo ""
  echo "Generated: $REPORT_DATE"
  echo ""
  echo "---"
  echo ""

  # 1. System section
  echo "## System"
  echo ""
  echo "| Field | Value |"
  echo "| --- | --- |"
  echo "| CPU | $(tk_cpu_model) |"
  echo "| Microcode | $(microcode_ver) |"
  echo "| BIOS | $(bios_version) / $(bios_date) |"
  echo "| Preferred cores (auto-detected) | $(tk_detect_preferred_cpus) |"
  echo "| Kernel | $(uname -r) |"
  echo ""

  if [ -n "$SYSINFO" ]; then
    echo "<details><summary>Full sysinfo (most recent run: $(basename "$LATEST"))</summary>"
    echo ""
    echo '```'
    echo "$SYSINFO"
    echo '```'
    echo ""
    echo "</details>"
    echo ""
  fi

  echo "---"
  echo ""

  # 2. Test runs section
  echo "## Test runs"
  echo ""
  csv_to_md_table "$RESULTS/runs.csv"
  echo ""
  echo "---"
  echo ""

  # 3. Verdict tally
  echo "## Verdict tally"
  echo ""
  verdict_tally "$RESULTS/runs.csv"
  echo ""
  echo "---"
  echo ""

  # 4. Per-core attribution
  echo "## Per-core error attribution"
  echo ""
  core_attribution
  echo ""
  echo "---"
  echo ""

  # 5. Kernel faults
  echo "## Kernel faults"
  echo ""
  fenced_log "$RESULTS/crashes.log"
  echo ""
  echo "---"
  echo ""

  # 6. Userspace faults
  echo "## Userspace faults"
  echo ""
  fenced_log "$RESULTS/userspace-traps.log"
  echo ""
  echo "---"
  echo ""

  # 7. Interpretation footer
  echo "## Interpretation"
  echo ""
  echo "A reproducible FAIL or CRASHED result obtained while the system BIOS is set to"
  echo "**Intel Default Settings** with **XMP/EXPO disabled** indicates CPU instability"
  echo "consistent with Raptor Lake (Intel 13th/14th-gen) Vmin-shift degradation. This"
  echo "condition is covered by Intel's extended 5-year warranty and qualifies the"
  echo "processor for replacement or refund under Intel's RMA programme. Attach this"
  echo "report when opening a support case at"
  echo "https://www.intel.com/content/www/us/en/support/contact-support.html"
  echo ""
} > "$OUT"

echo "Report written to: $OUT"
