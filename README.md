# is-my-cpu-cooked 🔥

[![CI](https://github.com/fadi-labib/is-my-cpu-cooked/actions/workflows/ci.yml/badge.svg)](https://github.com/fadi-labib/is-my-cpu-cooked/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: Linux](https://img.shields.io/badge/platform-Linux-informational)
![Shell: Bash](https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)
![Target: Intel 13th / 14th Gen](https://img.shields.io/badge/Intel-13th%20%2F%2014th%20Gen-0071C5?logo=intel&logoColor=white)
![No deps](https://img.shields.io/badge/runtime-pure%20bash-success)

> Is your Intel chip cooked? Find out, then build the evidence to RMA it.

Intel's 13th and 14th-gen Raptor Lake chips have a degradation problem: over time
the minimum voltage a core needs to compute correctly creeps up, and once it
passes what the board actually applies at light single-core boost, the core
starts returning wrong answers. You see it as random app crashes, kernel
`BUG()`s, and compile errors that come and go for no obvious reason.

This kit reproduces that on purpose. It detects the fastest-boosting cores on any
13th/14th-gen chip, pins targeted single-thread pressure on them, catches a
failure the instant it happens, and writes up a report you can hand to Intel
support. It is pure bash and runs entirely offline.

The whole thing is one command:

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

## Contents

- [Is this for me?](#is-this-for-me)
- [Install](#install)
- [Quickstart](#quickstart)
- [Commands](#commands)
- [Usage and flags](#usage-and-flags)
- [How it works](#how-it-works)
  - [Why single-core, light-load tests?](#why-single-core-light-load-tests)
  - [How the kit picks which cores to test](#how-the-kit-picks-which-cores-to-test)
  - [Live failure detection](#live-failure-detection)
  - [The tests](#the-tests-priority-order)
- [Step 0: eliminate the confounder](#step-0-eliminate-the-confounder-important)
- [Reading results](#reading-results)
- [The RMA report](#the-rma-report)
- [Catching real crashes automatically](#catching-real-crashes-automatically)
- [RMA guidance](#rma-guidance)
- [Control experiment](#control-experiment-for-extra-confidence)
- [Safety](#safety)
- [Known limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

## Is this for me?

You probably landed here because of one of these:

- Random app crashes or segfaults (SIGSEGV / signal 11)
- `internal compiler error` when building software
- Kernel `BUG()` / Oops in `dmesg` at light load, not during heavy all-core work
- Game shader-compile crashes
- Python, Firefox, or other apps faulting for no reason you can pin down

Affected chips are Intel 13th-gen (Raptor Lake) and 14th-gen (Raptor Lake
Refresh) Core i5, i7, and i9, so model numbers in the `i5/i7/i9-13xxx` and
`-14xxx` range. Nothing is hard-coded to a specific part; the kit reads your
topology at runtime and targets the right cores on a 13600K, 13700K, 14700K,
and so on.

Linux only. It is a set of bash scripts driving `stress-ng`, `y-cruncher`, and
`mprime` (Prime95). On Windows, run OCCT, y-cruncher, or Prime95 directly.

## Install

There is no runtime beyond bash. Clone it and run the one-time setup:

```bash
git clone https://github.com/fadi-labib/is-my-cpu-cooked.git
cd is-my-cpu-cooked
./imcc setup        # installs stress-ng (apt) and downloads y-cruncher + mprime into vendor/
```

`setup` is idempotent and checks the downloads against known hashes. After that,
everything goes through the single `./imcc` command.

## Quickstart

```bash
./imcc setup               # once: install and fetch tools
sudo ./imcc check          # confirm BIOS is at stock (XMP off, microcode, power limits)
./imcc run                 # full battery; finds a bad core with no prior knowledge
./imcc report              # bundle the evidence into results/RMA-REPORT.md
```

If you already know which core is suspect (say a `dmesg` crash named `CPU: 11`),
go straight at it:

```bash
./imcc ab --suspect 11     # A/B: stress core 11's pair against an auto-picked control
```

Not sure what to run? `./imcc guide` walks through the whole flow.

## Commands

```console
$ ./imcc help
is-my-cpu-cooked - is your Intel chip toast?

usage: ./imcc <command> [options]

  setup      install tools (run once)
  check      verify BIOS baseline (sudo for full RAM/XMP check)
  run        run the stress test            <- most people start here
  ab         suspect-vs-control A/B protocol
  report     build the RMA report bundle
  watch      install the background crash scanner
  warranty   how to file an Intel warranty claim (RMA)
  guide      explain the whole flow, start to finish
  version    print the kit version
  help       show this help

New? start with:  ./imcc setup
```

## Usage and flags

### `imcc run`: the stress battery

| Flag | Effect |
|------|--------|
| `--tests a,b,c` | Run only these tests (default: all, see [The tests](#the-tests-priority-order)) |
| `--minutes N` | Duration per test phase (default `90`) |
| `--quick` | Preset: 15 minutes. A smoke test, not conclusive |
| `--soak` | Preset: 8-hour overnight soak |
| `--loops N` | Repeat the whole battery N times |
| `--volts` | Also log per-core MHz / voltage during the run |

### `imcc ab`: suspect-vs-control A/B protocol

| Flag | Effect |
|------|--------|
| `--suspect CPU` | A logical CPU (as named in a `dmesg` crash line). Its SMT sibling pair becomes the suspect; the control is picked automatically |
| `--minutes N` | Duration per tool, per leg (default `20`; 3 tools x 2 legs is roughly 6N min) |
| `--check` | Setup verification only. Prints the detected suspect/control and exits, no stress |

### `imcc check`: BIOS baseline

Run it plain for microcode, power-limit, and governor checks. Run it with `sudo`
to also read RAM XMP/EXPO state via `dmidecode`. It exits `0` on `BASELINE OK`,
`1` if confounders are present.

### Environment overrides

| Variable | Used by | Effect |
|----------|---------|--------|
| `TK_SUSPECT` / `TK_CONTROL` | `ab` | Force the suspect/control CPU pairs (e.g. `10,11` / `8,9`) |
| `TK_TESTS` | `ab` | Tools per leg (default `core-target,stress-ng,prime95`) |
| `TK_TARGET_CPU` | `run` | Pin `core-target` to a specific logical CPU or pair |
| `SWEEP_MIN` | `run` | Explicit per-core minutes for `core-sweep` (default: `--minutes` split across P-cores) |
| `TK_NOTES` | `run` | Free-text note recorded in the run summary |

## How it works

### Why single-core, light-load tests?

The defect lowers the minimum voltage a core needs to compute correctly. At full
all-core Turbo the board applies a high voltage and the chip looks fine. The
trouble shows up at light single-core boost, which is what most everyday apps
actually hit: the applied voltage is too low for a degraded core, and you get
transient faults. So the kit pins its tests to the highest-boosting (preferred)
cores on purpose, to force exactly that condition.

### How the kit picks which cores to test

It works on any Raptor Lake chip because core selection is read from `lscpu` at
runtime. Nothing is baked in.

It targets P-cores only. The defect is a P-core boost problem; it shows up on the
high-frequency performance cores, not the efficiency (E) cores, which never boost
that high. A P-core is detected as a physical core with two SMT siblings
(HyperThreading). With HT disabled the kit falls back to the top MAXMHZ tier and
says so. Either way, E-cores are left out.

There are two ways to find a bad core:

- **Sweep** (`./imcc run`, no knowledge needed). It stresses each P-core in turn,
  fastest first, and flags any that fail. You don't have to know which core is
  bad: the one that breaks while the rest pass is the evidence, and the cores
  that pass act as the control.
- **A/B** (`./imcc ab`, suspect vs control). It runs the heavier FFT-class suite
  on the fastest-boosting P-core (the suspect, most likely to expose a degraded
  Vmin), then the same suite on the next P-core (the control, which should pass).
  When the suspect fails and the control passes the identical load, the fault is
  in the core, not the board, RAM, or cooling.

Saw a specific CPU in a crash? `./imcc ab --suspect 11` expands `11` into its
sibling pair and picks a control for you. You can also set both sides yourself
with `TK_SUSPECT=10,11 TK_CONTROL=8,9 ./imcc ab`.

### Live failure detection

Every stress tool runs through a watchdog. The moment a tool emits an error
signature (a y-cruncher checksum mismatch, a Prime95 `FATAL ERROR`, a stress-ng
verify failure) the kit prints a banner naming the offending logical core and
kills that test immediately, instead of idling out the rest of the duration.
That last part matters: y-cruncher otherwise sits on a `Press ENTER` prompt after
an error and the run looks hung.

```text
+================================================+
|  X  CPU FAILURE DETECTED                        |
+================================================+
  tool:    ycruncher
  signal:  Checksum Mismatch
  core:    logical CPU 11
```

The full output still lands in the run's log, so you don't have to watch the
terminal to know a run failed.

### The tests (priority order)

| Test | What it catches |
|------|-----------------|
| `core-target` | Single thread pinned to the preferred (highest-boosting) core. The headline Vmin-shift test |
| `core-sweep` | Per-P-core sweep that localises which core(s) fail |
| `stress-ng` | All-core and single-core with result verification |
| `y-cruncher` | All-core, self-verifying extended-precision arithmetic |
| `compile` | A real workload: triggers `internal compiler error` / segfault regressions |
| `prime95` | Small-FFT torture for rounding errors and hardware faults |

## Step 0: eliminate the confounder (important)

A FAIL only points at the CPU if the platform is at stock. In BIOS, before any
test, set Intel Default Settings and disable XMP / EXPO. A board voltage offset,
an undervolt, or an unstable RAM overclock produces the same symptoms, so clear
those variables first. (If you re-enable them later and the failures come back,
that is still the CPU: a degraded Vmin can't handle conditions the chip used to
be stable on.)

`./imcc check` verifies this for you:

```bash
./imcc check            # microcode, power limits, governor
sudo ./imcc check       # adds RAM/XMP via dmidecode
```

## Reading results

```text
results/SUMMARY.md           one row per run (verdict, max temp, errors)
results/runs.csv             same data, machine-readable
results/<timestamp>/         full logs, temps, sysinfo, verdict for each run
results/crashes.log          real-desktop kernel BUGs caught by the watcher
results/userspace-traps.log  userspace SIGSEGV / trap events
```

| Verdict | Meaning |
|---------|---------|
| `PASS` | No errors detected |
| `FAIL (errors)` | Compute errors or process faults detected. This is the strong signal |
| `THERMAL` | Peak package temp hit 95 °C or more. Check cooling before blaming the CPU |
| `CRASHED (kernel BUG)` | A kernel fault captured from real desktop use |

## The RMA report

`./imcc report` bundles everything into `results/RMA-REPORT.md`, written to stand
on its own in front of Intel support. It leads with the stress reproduction (the
tool's own output, not a summary of it), then the run history and any real-world
crashes:

```markdown
## Controlled reproduction (stress-test A/B)

### Suspect leg - CPU(s) 10,11 - verdict: FAIL (errors)
    Running BKT: Passed
    Exception Encountered: AlgorithmFailedException
    Checksum Mismatch
    Error(s) encountered on logical core 10.
    Stress test failed with 1 error.

### Control leg - CPU(s) 8,9 - verdict: THERMAL (0 errors)
    Running BKT: Passed
    Running BBP: Passed
    Running SFTv4: Passed
    Running FFTv4: Passed
    Running N63: Passed
    Running VT3: Passed
```

Both legs reach the same peak temperature, so the asymmetry (suspect fails,
control passes the identical load) puts the fault on the core rather than the
board, RAM, or cooling. The report also records CPU identity (model, CPUID,
microcode) and reminds you that the serial/batch number is laser-etched on the
chip lid (IHS) and printed on the retail box, so photograph it and attach it with
your proof of purchase.

## Catching real crashes automatically

```bash
./imcc watch
```

This installs a user-level systemd unit that scans the journal each boot and
appends new kernel BUGs and userspace traps to `results/`. A crash that happened
during normal use is often more persuasive than a synthetic test result.

## RMA guidance

Intel has acknowledged the defect and extended the warranty on affected
processors to 5 years from the purchase date, so a degraded chip is eligible for
replacement or refund even past the original 3-year window.

> The 0x12B+ microcode update (late 2023) lowers boost voltage to slow further
> degradation, but it does not undo damage already done. A chip that failed
> before the update still fails after it, which is the point: the silicon is the
> problem, not the firmware.

1. Run the kit and collect `results/RMA-REPORT.md` (`./imcc report`).
2. Have your purchase proof ready (receipt or order confirmation).
3. Open a case at <https://www.intel.com/content/www/us/en/support/contact-support.html>.
4. Attach the report plus a photo of the chip/box serial, and describe the
   real-world symptoms.

## Control experiment (for extra confidence)

Drop the CPU a notch (disable Turbo, apply a small negative voltage offset, or
lower the max multiplier) and see if the crashes stop. If they do, that is strong
independent proof: a healthy chip is stable at rated clocks, and a degraded one
is only stable when you slow it down. Run with `--volts` to capture clock speeds
during the tests.

## Safety

Stress testing drives the CPU to sustained high power and temperature, so make
sure your cooler is seated properly and can keep up. Don't run extended tests
(over 90 minutes) if you already see thermal throttling under normal use. Results
above 95 °C are flagged `THERMAL` and are not attributable to a CPU defect, so
fix cooling first.

Use at your own risk, as-is under the MIT License.

## Known limitations

The proven envelope is deliberately narrow. Keep it in mind before trusting
results on hardware unlike the author's:

- Tested on Ubuntu 24.04 only. It should work on any modern systemd-based Linux
  distribution, but other distros and kernels are unverified.
- Validated against a single physical CPU, one 13th/14th-gen Intel Core chip. The
  cross-chip core detection (P/E split, suspect/control selection) is unit-tested
  against synthetic `lscpu` topologies for other layouts, but it has not been run
  end-to-end on a different physical Raptor Lake model.
- Built and reviewed heavily with [Claude Code](https://claude.com/claude-code)
  (spec, plan, implementation, with review per change). That caught real bugs,
  but it is not a substitute for broad real-world testing.
- No guarantees on other machines. Treat results on untested hardware as
  indicative rather than authoritative, and always confirm a FAIL with the
  [baseline check](#step-0-eliminate-the-confounder-important) at stock BIOS.

Contributions are very welcome, especially test runs and `RMA-REPORT.md` results
from other 13th/14th-gen models. Those are what widen the envelope above.

## Contributing

Issues and PRs are welcome. Results from other Raptor Lake models are the most
useful thing you can send. The kit is pure bash with a dependency-free test
harness:

```bash
shellcheck -S warning imcc libexec/*.sh tests/*.sh watcher/*.sh lib/*.sh test/*.sh
bash test/test-common.sh && bash test/test-watchdog.sh && bash test/test-imcc.sh
```

Both run in CI on every push. Please keep them green. See
[CONTRIBUTING.md](CONTRIBUTING.md) for conventions.

## License

MIT, Copyright (c) 2026 Fadi Labib. See [LICENSE](LICENSE).
