# Dimit

Blue-light and PWM-flicker utility for macOS (Windows later). Sold as a pay-what-you-want download ($5 minimum) through Lemon Squeezy on our own site; no accounts, no license keys, no network traffic from the app except an opt-in update check.

- Product and engineering spec: [CLAUDE.md](CLAUDE.md)
- Cycles, PR rules, business track, decisions: [docs/PLAN.md](docs/PLAN.md)
- Architecture (modules, state machines, distribution, site, updates): [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Hardware evidence per cycle: [docs/QA.md](docs/QA.md)

First-time setup (installs XcodeGen if needed, generates `Dimit.xcodeproj` from `project.yml`):

```bash
scripts/bootstrap.sh
```

Re-run `scripts/bootstrap.sh` any time `project.yml` changes — `Dimit.xcodeproj` itself is gitignored and regenerated, never hand-edited or committed.

First thing to run on any new macOS build:

```bash
swift scripts/gamma_spike.swift
```

Status (2026-09-09): **C0–C5 done and merged to main, tagged `v0.3`** (180 tests green). The app has the full display engine (0K warmth, software dim, PWM-Safe, extreme dim, Fallback mode), everything behind the Settings gear (General / Schedule / Displays / Advanced, editable presets, six global hotkeys, launch at login, live Uzbek/Russian/English switch, onboarding, diagnostics), sunset→sunrise and fixed-time scheduling with a bundled city list, and experimental DDC/CI brightness for external monitors (default off — never verified against a real monitor yet).

The headline promise — "screenshots, recordings and screen-shares stay normal" — has real evidence for the gamma path: a Zoom share and a QuickTime recording on macOS 27, both untinted, with the filter working on screen throughout. It does **not** yet cover the two overlay-driven paths (brightness below 30%, Fallback mode), which rely on a window-exclusion flag Apple now calls legacy; those need a capture matrix in C6 before the claim is repeated unqualified on the site. Also open: the CoreDisplay brightness fallback can report a pin that never happened, on hardware nobody has tested; cold popover measures 180 ms against a 100 ms budget; DDC has never talked to a monitor. See docs/QA.md's **pending** rows.

**Distribution was re-decided on 2026-09-09** (docs/PLAN.md → Decisions): no license server, no keys, no trial, no Payme/Click. Next is C6 in docs/PLAN.md §2 — release scripts, a signed and notarized DMG, beta testers, the QA matrix (tags v0.4) — then C7: the Astro site with the Lemon Squeezy checkout, Sparkle opt-in updates, and the v1.0 launch.

PR rules: docs/PLAN.md §3 and .github/pull_request_template.md.
