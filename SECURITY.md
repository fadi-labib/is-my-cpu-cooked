# Security Policy

`is-my-cpu-cooked` is a local, offline Linux stress-test kit. It makes **no
network calls at runtime**, stores no credentials, and ships no services, so
its attack surface is small. The main risks worth reporting are:

- A script that could run unintended commands (e.g. unsafe handling of an
  environment variable, path, or downloaded tool).
- A flaw in `setup.sh`'s download/verification path that could fetch or execute
  a tampered binary.

## Reporting

Please **do not** open a public issue for a security report. Instead:

- Use GitHub's [private vulnerability reporting](https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing/privately-reporting-a-security-vulnerability)
  (the **Security** tab → *Report a vulnerability*), or
- Email **github@fadilabib.com**.

Please include the affected file, reproduction steps, and impact. You'll get an
acknowledgement as soon as possible.

## Scope

Out of scope: the third-party stress tools the kit downloads
(`y-cruncher`, `mprime`/Prime95, `stress-ng`). Report issues in those to their
respective projects.
