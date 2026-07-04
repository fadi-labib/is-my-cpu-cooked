# is-my-cpu-cooked 🔥

[![CI](https://github.com/fadi-labib/is-my-cpu-cooked/actions/workflows/ci.yml/badge.svg)](https://github.com/fadi-labib/is-my-cpu-cooked/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: Linux](https://img.shields.io/badge/platform-Linux-informational)
![Shell: Bash](https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)
![Target: Intel 13th / 14th Gen](https://img.shields.io/badge/Intel-13th%20%2F%2014th%20Gen-0071C5?logo=intel&logoColor=white)
![No deps](https://img.shields.io/badge/runtime-pure%20bash-success)

> Is your Intel chip cooked? Find out, then build the evidence to RMA it.

Intel's 13th/14th-gen Raptor Lake chips degrade over time: the voltage a core
needs to compute correctly creeps up until, at light single-core boost, it
starts returning **wrong answers**. You see it as random segfaults, kernel
`BUG()`s, and compile errors that come and go. This kit reproduces the defect
on purpose, catches the failure the instant it happens, and writes the report
you hand to Intel support. Pure bash, fully offline, any 13th/14th-gen chip.

```console
$ ./imcc ab --suspect 11        # stress the suspect core against a healthy one
...
+================================================+
|  X  CPU FAILURE DETECTED                        |
+================================================+
  tool:    ycruncher
  signal:  Checksum Mismatch
  core:    logical CPU 11
...
conclusion: DEFECT ISOLATED: suspect core fails, control core clean under identical load
```

## Symptoms

You probably landed here because of one of these, on an `i5/i7/i9-13xxx` or `-14xxx`:

- Random app crashes / segfaults (SIGSEGV) you can't pin down
- `internal compiler error` when building software
- Kernel `BUG()` / Oops in `dmesg` at **light** load, not heavy all-core work
- Game shader-compile crashes

Linux only — the kit drives `stress-ng`, `y-cruncher`, and `mprime`. On
Windows, run OCCT or Prime95 directly.

## Quickstart

```bash
git clone https://github.com/fadi-labib/is-my-cpu-cooked.git
cd is-my-cpu-cooked
./imcc setup               # once: installs stress-ng, downloads y-cruncher + mprime (hash-checked)
sudo ./imcc check          # confirm BIOS is at stock (XMP off, microcode, power limits)
./imcc run                 # full battery; finds a bad core with no prior knowledge
./imcc report              # bundle the evidence into results/RMA-REPORT.md
```

Already know the suspect core (say a `dmesg` crash named `CPU: 11`)? Go straight at it:

```bash
./imcc ab --suspect 11     # A/B: stress core 11's pair against an auto-picked control
```

Not sure what to run? `./imcc guide` walks you through the whole flow.

## Commands

```console
$ ./imcc help
  setup      install tools (run once)
  check      verify BIOS baseline (sudo for full RAM/XMP check)
  run        run the stress test            <- most people start here
  ab         suspect-vs-control A/B protocol
  report     build the RMA report bundle
  watch      install the background crash scanner
  warranty   how to file an Intel warranty claim (RMA)
  guide      explain the whole flow, start to finish
```

<details>
<summary><b>All flags and environment overrides</b></summary>

### `imcc run`

| Flag | Effect |
|------|--------|
| `--tests a,b,c` | Run only these tests (default: all) |
| `--minutes N` | Duration per test phase (default `90`) |
| `--quick` | Preset: 15 minutes. A smoke test, not conclusive |
| `--soak` | Preset: 8-hour overnight soak |
| `--loops N` | Repeat the whole battery N times |
| `--volts` | Also log per-core MHz / voltage during the run |

### `imcc ab`

| Flag | Effect |
|------|--------|
| `--suspect CPU` | A logical CPU (as named in a `dmesg` crash line). Its SMT sibling pair becomes the suspect; control is picked automatically |
| `--minutes N` | Duration per tool, per leg (default `20`; 3 tools × 2 legs ≈ 6N min) |
| `--check` | Print the detected suspect/control and exit, no stress |

### Environment overrides

| Variable | Used by | Effect |
|----------|---------|--------|
| `TK_SUSPECT` / `TK_CONTROL` | `ab` | Force the suspect/control CPU pairs (e.g. `10,11` / `8,9`) |
| `TK_TESTS` | `ab` | Tools per leg (default `core-target,stress-ng,prime95`) |
| `TK_TARGET_CPU` | `run` | Pin `core-target` to a specific logical CPU or pair |
| `SWEEP_MIN` | `run` | Explicit per-core minutes for `core-sweep` |
| `TK_NOTES` | `run` | Free-text note recorded in the run summary |

</details>

## How it works

The defect lowers a core's minimum stable voltage. At all-core Turbo the board
applies plenty of voltage and the chip looks fine — the faults show up at
**light single-core boost**, which is what everyday apps actually hit. So the
kit reads your topology from `lscpu` at runtime, picks the highest-boosting
P-cores (E-cores never boost high enough to be affected), and pins targeted
pressure exactly there. Two ways in:

- **Sweep** (`./imcc run`) — stresses each P-core in turn, fastest first. The
  core that breaks while the rest pass *is* the evidence; the passing cores are
  the control.
- **A/B** (`./imcc ab`) — runs the same FFT-class suite on the suspect core and
  a control core. Suspect fails + control passes the identical load ⇒ the fault
  is in the core, not the board, RAM, or cooling.

Every tool runs through a **live watchdog**: the moment an error signature
appears (y-cruncher checksum mismatch, Prime95 `FATAL ERROR`, stress-ng verify
failure) it prints a banner naming the failing logical core and kills the test
— no staring at a hung terminal, and the full log is kept.

| Test | What it catches |
|------|-----------------|
| `core-target` | Single thread pinned to the preferred core. The headline Vmin-shift test |
| `core-sweep` | Per-P-core sweep that localises which core(s) fail |
| `stress-ng` | All-core and single-core with result verification |
| `y-cruncher` | Self-verifying extended-precision arithmetic |
| `compile` | Real workload: triggers `internal compiler error` regressions |
| `prime95` | Small-FFT torture for rounding errors |

## Step 0: eliminate the confounder

A FAIL only points at the CPU if the platform is at stock. Before testing, set
**Intel Default Settings** in BIOS and **disable XMP/EXPO** — an undervolt or
unstable RAM overclock produces the same symptoms. `./imcc check` verifies this
(plain: microcode, power limits, governor; with `sudo`: RAM/XMP too) and exits
non-zero if confounders are present.

## Reading results

Everything lands in `results/`: `SUMMARY.md` (one row per run), `runs.csv`,
per-run log directories, and crash logs from the background watcher.

| Verdict | Meaning |
|---------|---------|
| `PASS` | No errors detected |
| `FAIL (errors)` | Compute errors detected — **the strong signal** |
| `THERMAL` | Peak package ≥ 95 °C. Fix cooling before blaming the CPU |
| `CRASHED (kernel BUG)` | A kernel fault captured from real desktop use |

Also worth running: `./imcc watch` installs a systemd unit that scans the
journal each boot and records real-world kernel BUGs and userspace traps — a
crash from normal use is often more persuasive than a synthetic test.

## Getting it replaced (RMA)

Intel acknowledged the defect and **extended the warranty to 5 years** from
purchase on affected boxed processors. The 0x12B+ microcode update slows
further degradation but does not undo damage — a chip that failed before the
update still fails after it.

1. `./imcc report` — bundles the evidence into `results/RMA-REPORT.md`, written
   to stand on its own in front of Intel support: the stress tools' own failure
   output first, then run history, real-world crashes, and CPU identity
   (model, CPUID, microcode).
2. Photograph the serial/batch on the chip lid (IHS) and retail box, and have
   your purchase proof ready.
3. Open a case at [Intel support](https://www.intel.com/content/www/us/en/support/contact-support.html)
   and attach the report, photos, and receipt. `./imcc warranty` prints this
   checklist with details.

<details>
<summary><b>Control experiment for extra confidence</b></summary>

Drop the CPU a notch (disable Turbo, small negative offset, or lower max
multiplier) and see if the crashes stop. A healthy chip is stable at rated
clocks; a degraded one is only stable slowed down. Run with `--volts` to
capture clock speeds during the tests.

</details>

## Safety and limitations

Stress testing drives sustained high power and temperature — make sure your
cooler is up to it. Runs peaking ≥ 95 °C are flagged `THERMAL` and not
attributable to a defect, so fix cooling first.

The proven envelope is narrow: tested on Ubuntu 24.04 against **one** physical
14th-gen chip. Core detection is unit-tested against synthetic `lscpu`
topologies for other layouts, but not run end-to-end on other Raptor Lake
models — treat results on untested hardware as indicative, and always confirm
a FAIL at stock BIOS. Built and reviewed with
[Claude Code](https://claude.com/claude-code); use at your own risk, as-is
under MIT.

## Contributing

Issues and PRs welcome — **test runs and `RMA-REPORT.md` results from other
13th/14th-gen models are the most useful thing you can send**, since they
widen the envelope above. Pure bash, dependency-free test harness:

```bash
shellcheck -S warning imcc libexec/*.sh tests/*.sh watcher/*.sh lib/*.sh test/*.sh
bash test/test-common.sh && bash test/test-watchdog.sh && bash test/test-imcc.sh
```

Both run in CI on every push; please keep them green. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT, Copyright (c) 2026 Fadi Labib. See [LICENSE](LICENSE).
