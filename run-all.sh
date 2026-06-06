#!/usr/bin/env bash
# Orchestrates the testkit: crash-scan prior runs, run selected tests, record verdict.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/lib/common.sh"
RESULTS="$HERE/results"; mkdir -p "$RESULTS"

MODEL="$(tk_cpu_model)"
echo "CPU: $MODEL | preferred cores: $(tk_detect_preferred_cpus) | microcode: $(grep -m1 microcode /proc/cpuinfo | awk '{print $3}')"
if ! tk_is_affected_intel "$MODEL"; then
  echo "WARNING: '$MODEL' is not a 13th/14th-gen Intel Core i5/i7/i9."
  echo "This kit targets Intel Raptor Lake Vmin-shift degradation; results may not be meaningful on your CPU."
  if [ -t 0 ]; then
    printf "Continue anyway? [y/N] "
    read -r ans; case "$ans" in y|Y) ;; *) echo "aborted."; exit 0;; esac
  else
    echo "(non-interactive: continuing)"
  fi
fi

TESTS="core-target,core-sweep,stress-ng,y-cruncher,compile,prime95"
MINUTES=90; LOOPS=1; VOLTS=0; THERMAL=95
while [ $# -gt 0 ]; do
  case "$1" in
    --tests) TESTS="$2"; shift 2;;
    --minutes) MINUTES="$2"; shift 2;;
    --loops) LOOPS="$2"; shift 2;;
    --volts) VOLTS=1; shift;;
    *) echo "unknown arg: $1"; exit 1;;
  esac
done

declare -A SCRIPT=(
  [core-target]=tests/01-core-target.sh [core-sweep]=tests/02-core-sweep.sh
  [stress-ng]=tests/03-stress-ng.sh [y-cruncher]=tests/04-y-cruncher.sh
  [compile]=tests/05-compile-loop.sh [prime95]=tests/06-prime95.sh
)

# 1) Record any previous crashed run before starting.
crashed="$(tk_scan_crashed "$RESULTS")"
if [ -n "$crashed" ]; then
  echo "$crashed"
  while IFS= read -r line; do
    [ -n "$line" ] && tk_summary_append "$RESULTS" "$(date +%Y%m%d-%H%M%S)" "-" "-" "CRASHED (reset)" "-" "-" "$line"
  done <<< "$crashed"
fi

run_once() {
  local ts; ts="$(date +%Y%m%d-%H%M%S)"
  local dir="$RESULTS/$ts"; mkdir -p "$dir"
  tk_mark_start "$dir"
  { echo "== sysinfo =="; lscpu | grep -E "Model name|^CPU\(s\)|Socket"; \
    echo "microcode: $(grep -m1 microcode /proc/cpuinfo)"; \
    echo "bios: $(cat /sys/class/dmi/id/bios_version) $(cat /sys/class/dmi/id/bios_date)"; \
    echo "preferred cpus: $(tk_detect_preferred_cpus)"; \
    echo "governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)"; \
    echo "CONFOUNDER CHECK: confirm BIOS = Intel Default + XMP OFF before trusting a FAIL"; \
  } > "$dir/sysinfo.txt"

  tk_temp_sampler_start "$dir" 5
  [ "$VOLTS" -eq 1 ] && tk_volts_sampler_start "$dir" 5
  trap 'tk_temp_sampler_stop; [ "$VOLTS" -eq 1 ] && tk_volts_sampler_stop' EXIT INT TERM

  local errs=0 ran=""
  IFS=',' read -ra LIST <<< "$TESTS"
  for t in "${LIST[@]}"; do
    local s="${SCRIPT[$t]:-}"; [ -z "$s" ] && { echo "skip unknown test: $t"; continue; }
    echo "--- $t ---"
    RUN_DIR="$dir" DURATION_MIN="$MINUTES" bash "$HERE/$s"
    local rc=$?
    ran="$ran$t "
    [ "$rc" -ne 0 ] && errs=$((errs+1))
  done

  tk_temp_sampler_stop
  [ "$VOLTS" -eq 1 ] && tk_volts_sampler_stop
  trap - EXIT INT TERM
  local maxpkg; maxpkg="$(tk_max_temp "$dir/temps.log")"
  local verdict; verdict="$(tk_overall_verdict "$errs" "$maxpkg" "$THERMAL")"
  echo "$verdict (errors=$errs maxpkg=${maxpkg}C tests: $ran)" > "$dir/verdict.txt"
  tk_mark_finished "$dir"
  tk_summary_append "$RESULTS" "$ts" "$MINUTES" "${ran% }" "$verdict" "$maxpkg" "$errs" "-"
  echo "==> $verdict | logs: $dir | summary: $RESULTS/SUMMARY.md"
}

for i in $(seq 1 "$LOOPS"); do echo "===== loop $i/$LOOPS ====="; run_once; done
