# is-my-cpu-cooked 🔥

[![CI](https://github.com/fadi-labib/is-my-cpu-cooked/actions/workflows/ci.yml/badge.svg)](https://github.com/fadi-labib/is-my-cpu-cooked/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform: Linux](https://img.shields.io/badge/platform-Linux-informational)
![Shell: Bash](https://img.shields.io/badge/shell-Bash-4EAA25?logo=gnu-bash&logoColor=white)
![Target: Intel 13th / 14th Gen](https://img.shields.io/badge/Intel-13th%20%2F%2014th%20Gen-0071C5?logo=intel&logoColor=white)
![No deps](https://img.shields.io/badge/runtime-pure%20bash-success)

> **Is your Intel chip cooked?** Prove it — then build the evidence to RMA it.

`is-my-cpu-cooked` is a Linux stress-test suite that proves or disproves
**Intel Raptor Lake (13th/14th-gen) Vmin-shift degradation** — the hardware
defect behind random crashes, kernel `BUG()`s, and *silent* compute errors
under ordinary workloads. It auto-detects the fastest-boosting cores on **any**
13th/14th-gen chip, pins targeted single-thread pressure where the defect
actually shows, surfaces failures live, and bundles a self-contained report for
an Intel warranty claim.

One command does it all:

```console
$ ./imcc ab --suspect 11        # stress the suspect core vs a healthy control
…
+================================================+
|  X  CPU FAILURE DETECTED                        |
+================================================+
  tool:    ycruncher
  signal:  Checksum Mismatch
  core:    logical CPU 11
…
conclusion: DEFECT ISOLATED: suspect core fails, control core clean under identical load
```

---

## Contents

- [Is this for me?](#is-this-for-me)
- [Install](#install)
- [Quickstart](#quickstart)
- [Commands](#commands)
- [Usage & flags](#usage--flags)
- [How it works](#how-it-works)
  - [Why single-core, light-load tests?](#why-single-core-light-load-tests)
  - [How the kit picks which cores to test](#how-the-kit-picks-which-cores-to-test)
  - [Live failure detection](#live-failure-detection)
  - [The tests](#the-tests-priority-order)
- [Step 0 — eliminate the confounder](#step-0--eliminate-the-confounder-important)
- [Reading results](#reading-results)
- [The RMA report](#the-rma-report)
- [Catching real crashes automatically](#catching-real-crashes-automatically)
- [RMA guidance](#rma-guidance)
- [Control experiment](#control-experiment-for-extra-confidence)
- [Safety](#safety)
- [Known limitations](#known-limitations)
- [Contributing](#contributing)
- [License](#license)

---

## Is this for me?

**Symptoms that bring people here:**

- Random application crashes or segmentation faults (SIGSEGV / signal 11)
- `internal compiler error` when building software
- Kernel `BUG()` / Oops in `dmesg` at light load (not during heavy all-core work)
- Game shader-compile crashes
- Python, Firefox, or other apps faulting for no obvious reason

**Affected CPUs:** Intel 13th-gen (Raptor Lake) and 14th-gen (Raptor Lake
Refresh) Core i5, i7, and i9 — model numbers in the range `i5/i7/i9-13xxx` and
`-14xxx`. Nothing is hard-coded to a specific chip; the kit auto-detects the
right cores on a 13600K, 13700K, 14700K, 14900K, and so on.

**Platform:** Linux only. Pure-bash scripts driving `stress-ng`, `y-cruncher`,
and `mprime` (Prime95). Windows users should run OCCT, y-cruncher, or Prime95
directly.

---

## Install

No runtime beyond bash. Clone and run the one-time setup:

```bash
git clone https://github.com/fadi-labib/is-my-cpu-cooked.git
cd is-my-cpu-cooked
./imcc setup        # installs stress-ng (apt) + downloads y-cruncher & mprime into vendor/
```

`setup` is idempotent and verifies download checksums. Everything else is driven
through the single `./imcc` entrypoint.

---

## Quickstart

```bash
./imcc setup               # once: install/fetch tools
sudo ./imcc check          # confirm BIOS is at stock (XMP off, microcode, power limits)
./imcc run                 # full battery — finds a bad core with zero prior knowledge
./imcc report              # bundle the evidence into results/RMA-REPORT.md
```

Already know which core is suspect (e.g. a `dmesg` crash named `CPU: 11`)?
Go straight at it:

```bash
./imcc ab --suspect 11     # A/B: stress core 11's pair vs an auto-picked control
```

Not sure what to run? `./imcc guide` prints the whole flow.

---

## Commands

```console
$ ./imcc help
is-my-cpu-cooked — is your Intel chip toast?

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

---

## Usage & flags

### `imcc run` — the stress battery

| Flag | Effect |
|------|--------|
| `--tests a,b,c` | Run only these tests (default: all — see [The tests](#the-tests-priority-order)) |
| `--minutes N` | Duration per test phase (default `90`) |
| `--quick` | Preset: 15 min — a smoke test, **not** conclusive |
| `--soak` | Preset: 8-hour overnight soak |
| `--loops N` | Repeat the whole battery N times |
| `--volts` | Also log per-core MHz / voltage during the run |

### `imcc ab` — suspect-vs-control A/B protocol

| Flag | Effect |
|------|--------|
| `--suspect CPU` | A logical CPU (as named in a `dmesg` crash line); its SMT sibling pair becomes the suspect, control is auto-picked |
| `--minutes N` | Duration per tool, per leg (default `20`; 3 tools × 2 legs ≈ 6N min) |
| `--check` | Setup verification only — print detected suspect/control and exit, no stress |

### `imcc check` — BIOS baseline

Run plain for microcode / power-limit / governor checks; run with `sudo` to also
read RAM XMP/EXPO state via `dmidecode`. Exits `0` = `BASELINE OK`, `1` =
confounders present.

### Environment overrides

| Variable | Used by | Effect |
|----------|---------|--------|
| `TK_SUSPECT` / `TK_CONTROL` | `ab` | Force the suspect/control CPU pairs (e.g. `10,11` / `8,9`) |
| `TK_TESTS` | `ab` | Tools per leg (default `core-target,stress-ng,prime95`) |
| `TK_TARGET_CPU` | `run` | Pin `core-target` to a specific logical CPU / pair |
| `SWEEP_MIN` | `run` | Explicit per-core minutes for `core-sweep` (default: `--minutes` split across P-cores) |
| `TK_NOTES` | `run` | Free-text note recorded in the run summary |

---

## How it works

### Why single-core, light-load tests?

The Vmin-shift defect lowers the minimum voltage a core needs to compute
correctly. At full all-core Turbo the board applies high voltage and the chip
looks fine. At **light single-core boost** — exactly what most everyday apps hit
— the applied voltage is too low for a degraded core, causing transient faults.
The kit pins tests to the highest-boosting (preferred) core(s) to trigger that
condition deliberately.

### How the kit picks which cores to test

**Works on any Raptor Lake chip** — core selection is detected from `lscpu` at
runtime, nothing is hard-coded.

**P-cores only.** The defect is a *P-core boost* phenomenon — it appears on the
high-frequency performance cores, not the efficiency (E) cores, which never boost
that high. A P-core is detected as a physical core with two SMT siblings
(HyperThreading); with HT disabled it falls back to the top MAXMHZ tier (and says
so). **E-cores are excluded.**

**Two ways to find a bad core:**

- **Sweep** (`./imcc run`, zero knowledge needed) — stresses each P-core in turn
  (fastest first) and flags any that fail. The core that breaks while the others
  pass *is* the evidence; the passing cores are their own control.
- **A/B** (`./imcc ab`, suspect vs control) — runs the heavier FFT-class suite on
  the **fastest-boosting P-core** (suspect, most likely to expose a degraded
  Vmin), then the **next P-core** (control, a same-tier core that *should* pass).
  The asymmetry isolates the defect to the core rather than the board/RAM/cooling.

Saw a specific CPU in a crash? `./imcc ab --suspect 11` expands `11` to its
sibling pair and auto-picks a control. Override either side with
`TK_SUSPECT=10,11 TK_CONTROL=8,9 ./imcc ab`.

### Live failure detection

Every stress tool streams through a watchdog. The instant a tool emits an error
signature — a y-cruncher checksum mismatch, a Prime95 `FATAL ERROR`, a stress-ng
verify failure — the kit prints a banner naming the offending logical core and
**kills that test immediately**, instead of idling out the remaining duration
(y-cruncher otherwise blocks on a `Press ENTER` prompt after an error):

```text
+================================================+
|  X  CPU FAILURE DETECTED                        |
+================================================+
  tool:    ycruncher
  signal:  Checksum Mismatch
  core:    logical CPU 11
```

The full output still lands in the run's log — you just don't have to babysit
the terminal to know a run failed.

### The tests (priority order)

| Test | What it catches |
|------|-----------------|
| `core-target` | Single-thread pinned to the preferred (highest-boosting) core — the Vmin-shift headline test |
| `core-sweep` | Per-P-core sweep; localises *which* core(s) fail |
| `stress-ng` | All-core and single-core with result verification |
| `y-cruncher` | All-core self-verifying extended-precision arithmetic |
| `compile` | Real-world workload: triggers `internal compiler error` / segfault regressions |
| `prime95` | Small-FFT torture; rounding errors and hardware faults |

---

## Step 0 — eliminate the confounder (important)

**A FAIL only indicts the CPU if the platform is at stock.** In BIOS, before any
test: set **Intel Default Settings** and disable **XMP / EXPO**. A board voltage
offset, undervolt, or unstable RAM overclock produces identical symptoms — remove
those variables first. (If you re-enable them and failures return, that's *still*
the CPU: a degraded Vmin can't handle conditions the chip was once stable on.)

`./imcc check` verifies this for you:

```bash
./imcc check            # microcode, power limits, governor
sudo ./imcc check       # + RAM/XMP via dmidecode
```

---

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
| `FAIL (errors)` | Compute errors or process faults detected — **the strong signal** |
| `THERMAL` | Peak package temp ≥ 95 °C — check cooling before blaming the CPU |
| `CRASHED (kernel BUG)` | A kernel fault captured from real desktop use |

---

## The RMA report

`./imcc report` bundles everything into `results/RMA-REPORT.md` — a
**self-contained** document built to stand on its own in front of Intel support.
It leads with the controlled stress reproduction (the tool's *own* output, not a
paraphrase), then the run history and corroborating real-world crashes:

```markdown
## Controlled reproduction (stress-test A/B)

### Suspect leg — CPU(s) 10,11 — verdict: FAIL (errors)
    Running BKT: Passed
    Exception Encountered: AlgorithmFailedException
    Checksum Mismatch
    Error(s) encountered on logical core 10.
    Stress test failed with 1 error.

### Control leg — CPU(s) 8,9 — verdict: THERMAL (0 errors)
    Running BKT: Passed
    Running BBP: Passed
    Running SFTv4: Passed
    Running FFTv4: Passed
    Running N63: Passed
    Running VT3: Passed
```

Both legs reach the same peak temperature, so the asymmetry — suspect fails,
control passes the *identical* load — isolates the fault to the core, not the
board, RAM, or cooling. The report also records CPU identity (model, CPUID,
microcode) and a reminder that the **serial/batch number is laser-etched on the
chip lid (IHS) / retail box** — photograph it and attach it with your proof of
purchase.

---

## Catching real crashes automatically

```bash
./imcc watch
```

Installs a user-level systemd unit that scans the journal each boot and appends
new kernel BUGs / userspace traps to `results/`. Real-world fault evidence is
often more persuasive than synthetic test results.

---

## RMA guidance

Intel has publicly acknowledged the defect and extended the warranty on affected
processors to **5 years from purchase date** — degraded chips are eligible for
**replacement or refund** even past the original 3-year window.

> The 0x12B+ microcode update (late 2023) lowers boost voltage to *prevent
> further* degradation, but **does not reverse damage already done**. A chip that
> crashed before the update still fails after it — proof the silicon, not the
> firmware, is the problem.

1. Run the kit and collect `results/RMA-REPORT.md` (`./imcc report`).
2. Have your purchase proof ready (receipt / order confirmation).
3. Open a case at <https://www.intel.com/content/www/us/en/support/contact-support.html>.
4. Attach the report + a photo of the CPU lid/box serial, and describe the
   real-world symptoms.

---

## Control experiment (for extra confidence)

Drop the CPU a notch — disable Turbo, apply a small negative voltage offset, or
lower the max multiplier — and if crashes stop, that's strong independent proof:
a healthy chip is stable at rated clocks; a degraded one is only stable when
slowed. Run with `--volts` to capture clock speeds during tests.

---

## Safety

Stress testing drives the CPU to sustained high power and temperature. Ensure
your cooler is properly seated and capable. Don't run extended tests (>90 min) if
you already see thermal throttling under normal use. Results above 95 °C are
flagged `THERMAL` and are **not** attributable to a CPU defect — fix cooling
first.

**Use at your own risk**, as-is under the MIT License.

---

## Known limitations

A deliberately narrow *proven* envelope — be aware of it before trusting results
on hardware unlike the author's:

- **Tested on Ubuntu 24.04 only** (kernel 6.17). It should work on any modern
  systemd-based Linux distribution, but other distros/kernels are unverified.
- **Validated against a single physical CPU** — the author's Intel **i9-14900K**.
  The cross-chip core detection (P/E split, suspect/control selection) is
  unit-tested against synthetic `lscpu` topologies for other layouts, but has not
  been run end-to-end on a different physical Raptor Lake model.
- **AI-assisted development.** The kit was built and **extensively code-reviewed
  with [Claude Code](https://claude.com/claude-code)** (spec → plan →
  implementation, with adversarial review per change). That caught real bugs, but
  is not a substitute for broad real-world testing.
- **No guarantees on other machines.** Treat results on untested hardware as
  indicative, not authoritative — and always confirm a FAIL with the
  [baseline check](#step-0--eliminate-the-confounder-important) at stock BIOS.

**Contributions are very welcome** — especially test runs and `RMA-REPORT.md`
results from other 13th/14th-gen models, which directly widen the proven envelope
above.

---

## Contributing

Issues and PRs welcome — especially results from other Raptor Lake models to
broaden the dataset. The kit is pure bash with a dependency-free test harness:

```bash
shellcheck -S warning imcc libexec/*.sh tests/*.sh watcher/*.sh lib/*.sh test/*.sh
bash test/test-common.sh && bash test/test-watchdog.sh && bash test/test-imcc.sh
```

Both run in CI on every push. Please keep them green.

---

## License

MIT © 2026 Fadi Labib — see [LICENSE](LICENSE).
