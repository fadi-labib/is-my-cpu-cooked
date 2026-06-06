# CPU Degradation Testkit

Stress-test suite to prove or disprove **Intel i9-14900K degradation** for an
Intel RMA. Targets the suspect 6.0 GHz preferred core (logical CPU 11 = physical
core 5) where two kernel `BUG()`s occurred at light load.

See `docs/specs/2026-06-06-cpu-degradation-testkit-design.md` for the full rationale.

## ⚠️ Read first — the confounder

A FAIL only means *the CPU* if the platform is at stock. **Before trusting any
FAIL:** in BIOS set **Intel Default Settings** and **disable XMP/EXPO**.
Otherwise a failure may be the motherboard over-volting or unstable RAM OC.

## Setup (once)

    ./setup.sh        # installs stress-ng/build-essential, vendors y-cruncher + mprime

## Run

    ./run-all.sh                                  # all tests, 90 min each
    ./run-all.sh --tests core-target,core-sweep   # just the targeted detectors
    ./run-all.sh --minutes 15                       # quick smoke
    ./run-all.sh --minutes 480                      # overnight soak
    ./run-all.sh --loops 5                          # repeat the battery 5×
    ./run-all.sh --volts                            # also log per-core MHz/voltage

Monitor temps live in another terminal:

    watch -n2 'sensors | grep -E "Package|Core"'

## Tests (priority order)

| test | what it catches |
|------|-----------------|
| core-target | single-thread pinned to suspect 6.0 GHz core — the Vmin-shift condition (headline) |
| core-sweep | per-P-core, localizes which core(s) fail |
| stress-ng | all/single-core, result verification |
| y-cruncher | all-core self-verifying math |
| compile | real-world segfault / internal compiler error |
| prime95 | Small-FFT torture, rounding/hardware errors |

## Reading results

- `results/SUMMARY.md` — one row per run (verdict, max temp, errors).
- `results/runs.csv` — same, machine-readable for trends.
- `results/<timestamp>/` — full logs, temps, sysinfo, verdict for one run.
- `results/crashes.log` — real desktop kernel BUGs caught by the watcher.

Verdicts: `PASS` · `FAIL (errors)` · `THERMAL` (>95 °C, cooling not chip) ·
`CRASHED (reset)` (machine hard-reset mid-test; recorded on next launch).

## Catch real crashes automatically

    ./watcher/install-watcher.sh   # user systemd unit: scans journal each boot

## Control experiment (decisive)

If you drop the CPU a notch (disable Turbo, small negative voltage offset, or
lower max multiplier in BIOS) and crashes stop, that is strong degradation
proof — a healthy chip holds rated clocks; a degraded one is stable only slowed.
Run with `--volts` to capture clocks during tests.

## What a result means

- Reproducible FAIL on `core-target` at Intel defaults → conclusive → RMA.
- `core-sweep` failing only on specific cores → degradation localized + pinpointed.
- Long string of PASSes → reassuring but never fully clears (degradation is
  intermittent); keep the watcher running on real-use crashes.
