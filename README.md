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

Status (2026-09-09): **C0–C4 done and merged to main, tagged `v0.2`** (118 tests green). Everything CLAUDE.md §1 puts "behind a Settings gear" now exists: a Settings window (General / Displays / Advanced), editable presets, six global hotkeys, launch at login, a live Uzbek/Russian/English switch, first-run onboarding, and diagnostics to the clipboard — on top of the v0.1 display engine (0K warmth, software dim, PWM-Safe, extreme dim, Fallback mode).

An independent second review of the whole repo landed with v0.2 and found a bug that predated it: **the tint was silently lost on every wake**, because the apply pipeline diffed against what it believed was already on the hardware, and WindowServer resets the gamma table across sleep. Reproduced on the real display, fixed, and re-verified. Same review caught Fallback mode going fully opaque at the NIGHT preset — an opaque red window over the menu bar, in the mode that exists *because* the display is misbehaving.

Known and open, both gating public claims: screen-capture exclusion is **not** guaranteed by any public macOS API (`sharingType = .none` is legacy), so "screenshots and screen-shares stay normal" needs a real capture matrix in C6 before it ships as a promise; and the CoreDisplay brightness fallback can report a pin that never happened on hardware nobody has tested. Cold popover measures 180 ms against a 100 ms budget. See docs/QA.md.

Next is C5 in docs/PLAN.md §2: sunset/sunrise scheduling and experimental DDC/CI for external monitors (tags v0.3).

PR rules: docs/PLAN.md §3 and .github/pull_request_template.md.