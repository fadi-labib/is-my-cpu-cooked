# Contributing

Thanks for helping improve **is-my-cpu-cooked**. Two kinds of contributions are
especially valuable:

1. **Test results from other CPUs.** Runs (pass *or* fail) from any 13th/14th-gen
   Intel chip widen the proven envelope. Open a **"CPU test result"** issue and
   paste your `results/RMA-REPORT.md` highlights. This is the single most useful
   thing you can contribute.
2. **Code and fixes.** Bug fixes, new detectors, broader topology support.

## Dev setup

Pure bash, no build step. The only dev dependency is
[`shellcheck`](https://www.shellcheck.net/).

```bash
git clone https://github.com/fadi-labib/is-my-cpu-cooked.git
cd is-my-cpu-cooked
```

## Before you open a PR

Run the same checks CI runs, and please keep them green:

```bash
shellcheck -S warning imcc libexec/*.sh tests/*.sh watcher/*.sh lib/*.sh test/*.sh
bash test/test-common.sh
bash test/test-watchdog.sh
bash test/test-imcc.sh
```

## Conventions

- **Pure functions in `lib/common.sh`** (parse input, return data, no `lscpu`/
  `sensors` calls) with an impure `tk_detect_*` wrapper where needed. Add a unit
  test in `test/test-common.sh` (or `test/test-watchdog.sh`) for every pure
  function: feed it fixture text, then assert it.
- **Stress tools run through `tk_run_watched`** so failures surface live and the
  process is killed on the spot. Don't shell out to a tool directly.
- **`./imcc` is the only entrypoint.** Underlying scripts live in `libexec/` and
  assume `$HERE` is `libexec/` (repo-root paths are `$HERE/../...`).
- Keep changes focused; match the surrounding style; update the README if you
  change a flag or command.

## Reporting a vulnerability

See [SECURITY.md](SECURITY.md).

By contributing you agree your work is licensed under the project's
[MIT License](LICENSE).
