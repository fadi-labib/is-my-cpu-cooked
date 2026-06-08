# is-my-cpu-cooked

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: Linux](https://img.shields.io/badge/platform-Linux-informational)
![Shell: Bash](https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)
![Target: Intel 13th / 14th Gen](https://img.shields.io/badge/Intel-13th%20%2F%2014th%20Gen-0071C5?logo=intel&logoColor=white)
[![CI](https://github.com/fadi-labib/is-my-cpu-cooked/actions/workflows/ci.yml/badge.svg)](https://github.com/fadi-labib/is-my-cpu-cooked/actions/workflows/ci.yml)

> **Is your Intel chip cooked?** Find out for sure — then build the evidence to RMA it.

A Linux stress-test suite that proves or disproves
**Intel Raptor Lake (13th/14th-gen) Vmin-shift degradation** — the hardware
defect that causes random crashes, kernel BUGs, and silent compute errors under
ordinary workloads. It auto-detects the suspect preferred/fastest-boosting core
on your CPU and applies targeted single-thread pressure where the defect shows
most clearly, then bundles the evidence for an Intel RMA.

See `docs/specs/2026-06-06-cpu-degradation-testkit-design.md` for the full
technical rationale.

---

## Contents

- [Is this for me?](#is-this-for-me)
- [Why single-core, light-load tests?](#why-single-core-light-load-tests)
- [Step 0 — eliminate the confounder](#step-0--eliminate-the-confounder-important)
  - [preflight.sh — automated baseline check](#preflightsh--automated-baseline-check)
- [Quickstart](#quickstart)
- [Example output](#example-output)
- [Live failure detection](#live-failure-detection)
- [Tests](#tests-priority-order)
- [Reading results](#reading-results)
- [Generating an RMA report](#generating-an-rma-report)
- [Catching real crashes automatically](#catching-real-crashes-automatically-recommended)
- [RMA guidance](#rma-guidance)
- [Control experiment](#control-experiment-for-extra-confidence)
- [Safety disclaimer](#safety-disclaimer)

---

## Is this for me?

**Symptoms that bring people here:**

- Random application crashes or segmentation faults (SIGSEGV / signal 11)
- `internal compiler error` when building software
- Kernel BUG() / Oops in dmesg at light load (not during heavy all-core work)
- Game shader-compile crashes
- Python, Firefox, or other apps faulting for no obvious reason

**Affected CPUs:** Intel 13th-gen (Raptor Lake) and 14th-gen (Raptor Lake
Refresh) Core i5, i7, and i9 desktop/laptop processors. Look for a model
number in the range i5-13xxx, i5-14xxx, i7-13xxx, i7-14xxx, i9-13xxx,
i9-14xxx.

**Platform:** Linux only. The kit is a set of bash scripts and uses
`stress-ng`, `y-cruncher`, and `mprime` (Prime95). Windows users should run
OCCT, y-cruncher, or Prime95 directly.

---

## Why single-core, light-load tests?

The Vmin-shift defect lowers the minimum voltage a core needs to operate
correctly. At full all-core Turbo the board applies the normal high voltage and
the chip looks fine. At light single-core boost — exactly the condition most
everyday apps hit — the voltage applied is too low for a degraded core, causing
transient faults. This kit pins each test to the highest-boosting (preferred)
core(s) detected on your CPU to trigger that condition deliberately.

---

## Step 0 — eliminate the confounder (important)

A FAIL only indicts *the CPU* if the platform is at stock.

**In BIOS before running any test: set Intel Default Settings and disable
XMP / EXPO.** A motherboard voltage offset, undervolting, or unstable RAM
overclock can produce identical symptoms. Remove those variables first, then
run the kit. If you re-enable them and failures return, that is still the CPU
(the degraded Vmin cannot handle non-default conditions the chip was once
perfectly stable on).

### preflight.sh — automated baseline check

Use `preflight.sh` to verify the BIOS baseline programmatically before
trusting any stress result. It checks microcode version, RAPL power limits,
CPU frequency governor, and (with root) RAM XMP/EXPO state:

```bash
./preflight.sh            # checks microcode, power limits, governor
sudo ./preflight.sh       # full check including RAM/XMP via dmidecode
```

`preflight.sh` exits 0 ("BASELINE OK") if no hard confounders are detected,
or exits 1 ("CONFOUNDERS PRESENT") if XMP/EXPO is on or power limits are
removed. Fix any flagged issues before running the test battery — otherwise
a FAIL may reflect the board configuration, not the CPU.

---

## Quickstart

```bash
./setup.sh        # once: installs stress-ng/build-essential, downloads y-cruncher + mprime
./run-all.sh      # full battery, 90 min per test
```

Common options:

```bash
./run-all.sh --tests core-target,core-sweep   # targeted detectors only
./run-all.sh --quick                           # preset: 15 min smoke (not conclusive)
./run-all.sh --soak                            # preset: 8-hour overnight soak
./run-all.sh --minutes 15                      # custom duration (overrides preset if given after)
./run-all.sh --loops 5                         # repeat the battery 5×
./run-all.sh --volts                           # also log per-core MHz / voltage
```

Monitor temps live in another terminal:

```bash
watch -n2 'sensors | grep -E "Package|Core"'
```

---

## Example output

Each run prints a one-line verdict and writes a full evidence trail under
`results/`:

```text
$ ./run-all.sh --tests core-target,core-sweep --minutes 30
CPU: Intel(R) Core(TM) i9-14900K | preferred cores: 8 9 10 11 | microcode: 0x133
===== loop 1/1 =====
--- core-target ---
--- core-sweep ---
  >> CPU 8  ok
  >> CPU 10 FAILED
  >> CPU 0  ok
  >> CPU 2  ok
  ...
==> FAIL (errors) | logs: results/20260606-141230 | summary: results/SUMMARY.md
```

A failing core in the sweep that others pass *localises* the defect — exactly the
kind of pinpointed evidence an RMA needs. `results/SUMMARY.md` accumulates one
row per run:

| timestamp | min | tests | verdict | max pkg °C | errors | notes |
|-----------|-----|-------|---------|-----------|--------|-------|
| 20260606-141230 | 30 | core-target core-sweep | FAIL (errors) | 88 | 1 | - |

---

## Live failure detection

Stress tests stream through a watchdog. The instant a tool prints an error
signature — a y-cruncher checksum mismatch, a Prime95 `FATAL ERROR`, a stress-ng
verification failure — the kit prints a banner naming the offending logical core
and stops that test immediately, rather than idling out the remaining duration
(y-cruncher, for example, otherwise blocks on a `Press ENTER` prompt after an
error):

```text
+================================================+
|  X  CPU FAILURE DETECTED                        |
+================================================+
  tool:    ycruncher
  signal:  Checksum Mismatch
  core:    logical CPU 10
```

The full output still lands in the run's log either way — you just no longer
have to watch the terminal or grep a log to know a run failed.

---

## Tests (priority order)

| Test | What it catches |
|------|-----------------|
| core-target | Single-thread pinned to the auto-detected preferred (highest-boosting) core — the Vmin-shift headline test |
| core-sweep | Per-P-core sweep; localises which specific core(s) fail |
| stress-ng | All-core and single-core with result verification |
| y-cruncher | All-core self-verifying extended-precision arithmetic |
| compile | Real-world workload: triggers `internal compiler error` / segfault regressions |
| prime95 | Small-FFT torture; catches rounding errors and hardware faults |

The preferred core is auto-detected from `lscpu` (the logical CPU(s) with the
highest MAXMHZ). It is not hard-coded to any particular CPU number.

---

## Reading results

```
results/SUMMARY.md          one row per run (verdict, max temp, errors)
results/runs.csv             same data, machine-readable
results/<timestamp>/         full logs, temps, sysinfo, verdict for each run
results/crashes.log          real-desktop kernel BUGs caught by the watcher
results/userspace-traps.log  userspace SIGSEGV / trap events
```

Verdicts:

| Verdict | Meaning |
|---------|---------|
| `PASS` | No errors detected in this run |
| `FAIL (errors)` | Compute errors or process faults detected — strong signal |
| `THERMAL` | Peak package temp >= 95 °C; check cooling before blaming the CPU |
| `CRASHED (reset)` | Machine hard-reset mid-test; recorded on next launch |

---

## Generating an RMA report

After one or more runs:

```bash
./report.sh
```

This bundles sysinfo, the runs table, verdict tally, and any captured kernel /
userspace fault logs into `results/RMA-REPORT.md` — ready to attach to an
Intel support ticket.

---

## Catching real crashes automatically (recommended)

Install the boot-time watcher to capture kernel BUGs and userspace traps from
your normal desktop usage:

```bash
./watcher/install-watcher.sh
```

This installs a user-level systemd unit that scans the journal each boot and
appends new faults to `results/crashes.log` and `results/userspace-traps.log`.
Real-world fault evidence is often more persuasive than synthetic test results.

---

## RMA guidance

Intel has publicly acknowledged the defect and extended the warranty on
affected processors to **5 years from purchase date**. Degraded chips are
eligible for **replacement or refund** regardless of whether they are still
within the original 3-year warranty.

The 0x12B+ microcode update (released late 2023) changes the power limits to
prevent further degradation, but **it does not reverse damage already done**. A
chip that crashes before the microcode update will still crash after it, just
at a lower all-core boost clock.

Steps:
1. Run this kit and collect `results/RMA-REPORT.md` (`./report.sh`).
2. Note your purchase proof (receipt, Amazon/Newegg order).
3. Open a case at **https://www.intel.com/content/www/us/en/support/contact-support.html**
4. Attach the report and describe the real-world crash symptoms.

---

## Control experiment (for extra confidence)

If you drop the CPU a notch — disable Turbo, apply a small negative voltage
offset, or lower the max multiplier in BIOS — and crashes stop, that is strong
independent degradation proof: a healthy chip is stable at rated clocks; a
degraded one is only stable when slowed. Run with `--volts` to capture clock
speeds during tests.

---

## Safety disclaimer

Stress testing drives the CPU to sustained high power and temperature. Ensure
your cooler is properly seated and capable. Do not run extended tests (>90 min)
if you are already seeing thermal throttling under normal use. Results above
95 °C package temperature are flagged THERMAL and are not attributable to CPU
defects — fix the cooling first.

**Use at your own risk.** This kit is provided as-is under the MIT License.

---

MIT License — Copyright (c) 2026 Fadi Labib
