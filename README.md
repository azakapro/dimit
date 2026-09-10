# Dimit

Warm your Mac's screen down to a pure-red "0K", dim it below the keyboard's floor, and keep the backlight from flickering. A native macOS menu-bar app: two sliders, three presets, one button. Uzbek, Russian and English. No account, no tracking, no subscription.

**Get it:** pay what you want from $5 at [dimit.uz/download](https://dimit.uz/download) (Lemon Squeezy checkout, cards and PayPal). Every copy is identical and unconditional — no key, no trial, no activation.

## What it does

- **Warmth to 0K.** Night Shift stops near 2500K, f.lux near 1900K; Dimit rewrites the display's gamma tables all the way to pure red. "0K" is a name, not a physical temperature.
- **Software dimming to 10%**, on every connected display, below what the brightness keys allow.
- **PWM-Safe mode** pins the hardware backlight at 100% and dims in software instead, so LED backlights that dim by pulsing (PWM) stop pulsing. Apple displays today; third-party monitors over DDC/CI are experimental and off by default.
- **Screenshots, recordings and screen shares keep their real colours** at brightness 30% and above, because the tint lives in the display's colour tables, not in a window. Verified with QuickTime and Zoom on macOS 27 (docs/QA.md). Below 30% an overlay window is used for dimming, and some recorders may capture it.
- **Sunset→sunrise or fixed-time schedules**, computed locally from a bundled city list or a one-time location read. Nothing is sent anywhere.
- **Fail-safe.** OFF, quit, sleep/wake and unplugging a monitor all leave the display normal; after a crash or `kill -9` the next launch restores it before doing anything else (on macOS 27 WindowServer even does it immediately); a "Restore Colours" button exists for anything else.

Requires macOS 13 or later, Apple silicon or Intel. Never asks for Accessibility, Screen Recording or admin. Not on the Mac App Store, because the sandbox forbids the display access it needs.

**macOS 26 (Tahoe):** on some Macs, Apple's own display bug (FB22273730, confirmed by Apple DTS on 26.3.1–26.5.1 and by our first tester on 26.6.2) silently ignores colour-table changes, so the screen doesn't turn warm. Dimit can't detect this — macOS reports success. Turning off automatic brightness in System Settings → Displays fixes it on many machines; on the rest, Dimit's colour changes do nothing until Apple fixes the bug (dimming below 30% and PWM-Safe still work). macOS 27 works normally.

## Privacy, in one paragraph

The app makes no network request of any kind unless you turn on update checks (off by default), in which case Sparkle fetches one signed appcast from dimit.uz. There is no analytics, no crash reporter, no identifier, no server of ours. See docs/ARCHITECTURE.md §4 and the Privacy page on the site.

## Building it

```bash
scripts/bootstrap.sh      # installs XcodeGen if needed, generates Dimit.xcodeproj from project.yml
xcodebuild test -project Dimit.xcodeproj -scheme Dimit -destination 'platform=macOS'
```

`Dimit.xcodeproj` is generated and gitignored; edit `project.yml`, never the project. Xcode 26 or newer, Swift 5 language mode on the Swift 6 toolchain, macOS 13 deployment target, universal binary. Two Swift packages: [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) and [Sparkle](https://github.com/sparkle-project/Sparkle), both pinned.

Run `swift scripts/gamma_spike.swift` on any new macOS build before trusting the gamma path — the display engine's known Apple bugs are documented in CLAUDE.md §3.3.

Releases: `scripts/build.sh` → `scripts/notarize.sh` (which also builds the DMG) → `scripts/make_appcast.sh`; the procedure and gates are in docs/RELEASE.md. The site lives in `site/` (Astro, static; `npm run build`, `npm run build:release` refuses to ship placeholders).

## Where things are

| | |
|---|---|
| Product and engineering spec, non-negotiable rules | [CLAUDE.md](CLAUDE.md) |
| Cycles, decisions, PR rules, business track | [docs/PLAN.md](docs/PLAN.md) |
| Architecture, display engine, distribution, site, updates | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Hardware evidence behind every claim above | [docs/QA.md](docs/QA.md) |
| Releasing | [docs/RELEASE.md](docs/RELEASE.md) |
| Beta tester checklist | [docs/TESTING_CHECKLIST.md](docs/TESTING_CHECKLIST.md) |

## Status

2026-09-10: **C0–C7 built** — display engine, PWM-Safe, settings, scheduling, experimental DDC, release scripts, opt-in Sparkle updates, and the site. Tagged through `v0.4`; 183 tests. What stands between this and **v1.0**: a Developer ID certificate under the LLC (the friend's account is beta-only, because Sparkle ties updates to the Team ID), the Lemon Squeezy store with a verified payout method and the checkout URL in `site/src/config.ts`, the site's Uzbek/Russian copy read by a fluent person (`site/TRANSLATIONS.md`), and tester reports on a stable macOS release. All four are in docs/PLAN.md §2 C7 "Done when".
