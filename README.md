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

Status (2026-09-09): C1 skeleton built (menu bar item, popover, string catalog, warmth curve — see PR c1-skeleton). Next is C2 in docs/PLAN.md §2.

PR rules: docs/PLAN.md §3 and .github/pull_request_template.md.