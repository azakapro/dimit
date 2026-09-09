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

Status (2026-09-09): **C0–C3 done and merged to main — the MVP milestone, tagged `v0.1`** (72 tests green). The app warms every connected display from 6500K to a pure-red 0K, dims in software, pins the backlight at 100% in PWM-Safe mode so LED panels don't flicker, drops to an overlay below the 30% gamma floor, and has a Fallback tint mode for displays that ignore gamma tables. Colours restore on OFF, on quit, on SIGTERM/SIGINT and on launch. All of it verified against the real hardware — gamma tables read back directly, overlay geometry checked against the window server, brightness pin confirmed at the backend — not just unit-tested.

Still needs a human on real hardware before it's trustworthy: an external monitor, sleep/wake, and confirming by eye that 0K looks red (see the **pending** rows in docs/QA.md). Next is C4 in docs/PLAN.md §2: settings window, hotkeys, launch at login, onboarding (tags v0.2).

PR rules: docs/PLAN.md §3 and .github/pull_request_template.md.