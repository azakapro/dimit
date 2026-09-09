# Dimit

Blue-light and PWM-flicker utility for macOS (Windows later). Uzbekistan-first, then global.

- Product and engineering spec: [CLAUDE.md](CLAUDE.md)
- Schedule, critical path, decisions, model assignment: [docs/PLAN.md](docs/PLAN.md)
- Architecture (modules, state machines, server API, payment flows): [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

First-time setup (installs XcodeGen if needed, generates `Dimit.xcodeproj` from `project.yml`):

```bash
scripts/bootstrap.sh
```

Re-run `scripts/bootstrap.sh` any time `project.yml` changes — `Dimit.xcodeproj` itself is gitignored and regenerated, never hand-edited or committed.

First thing to run on any new macOS build:

```bash
swift scripts/gamma_spike.swift
```

Status (2026-09-09): C0, C1, C2 done and merged to main (43 tests green). The app now really warms and dims every connected display, with restore on quit/off/crash-adjacent signals/launch, all verified against the real hardware via direct gamma-table readback. Next is C3 in docs/PLAN.md §2: PWM-Safe mode and the extreme-dim overlay (tags v0.1).

PR rules: docs/PLAN.md §3 and .github/pull_request_template.md.