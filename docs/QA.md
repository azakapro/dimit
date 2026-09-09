# QA matrix

One row per check per machine. Fill by hand; a PR that claims a check passed must have its row here.

## Gamma spike (C0)

| Date | Machine | macOS | Auto-brightness | `set` return | read-back green max | Screen turned red? |
|---|---|---|---|---|---|---|
| 2026-09-09 | MacBookPro18,1 M1 Pro | 27.0 (26A5416b) | ON | 0 (success) | 0.0 | **pending — needs human eyes, structurally.** Tried two ways to verify automatically: (1) raw `screencapture` CLI failed outright (`could not create image from display`, no Screen Recording TCC grant); (2) a computer-use screenshot taken 2s into the red window *succeeded* but showed normal full-color menu-bar icons, not red. That is not a bug — macOS screen-capture composites from the pre-LUT framebuffer, so `CGSetDisplayTransferByTable` changes are invisible to *any* screenshot API by design (this is the same mechanism CLAUDE.md rule 4 relies on for "screenshots aren't tinted"). So no software check, with any permission, can ever confirm this — only a human looking at the physical panel can. Owner: please run `swift scripts/gamma_spike.swift` yourself and confirm the screen visibly flashed red for ~4s. |
| | MacBookPro18,1 M1 Pro | 27.0 (26A5416b) | OFF | | | pending — also needs "Automatically adjust brightness" turned off in System Settings → Displays first (a system-setting change left to the owner, not done automatically). |

## App checks

| Date | Version | Machine | macOS | Display(s) | Check | Result | Notes |
|---|---|---|---|---|---|---|---|
| 2026-09-09 | C1 (pre-0.1) | MacBookPro18,1 M1 Pro | 27.0 (26A5416b) | built-in | `xcodebuild test` | pass | 27/27 (started at 22, `/code-review high` on the PR found a real inverted-label bug plus several gaps and added 5 more tests while fixing them — see the PR) |
| 2026-09-09 | C1 | same | same | built-in | App launches, no crash | pass | verified via `ps`, plus os_log line at launch |
| 2026-09-09 | C1 | same | same | built-in | Menu bar icon shows, toggles outline/filled | pass | confirmed via screenshot; SF Symbol placeholder, real icon is C3 |
| 2026-09-09 | C1 | same | same | n/a | Left-click opens popover; right-click shows menu | pass (logic), **not confirmed visually on-screen** | AppKit itself confirms the click event is received with the correct type, `togglePopover()` runs, and the popover reports `isShown=true` with a sane content size — but this session's virtual display could not screenshot the live popover: Dimit's frontmost status kept reverting to the terminal within about a second (likely this sandboxed display's window-focus handling for accessory apps), and the automation tool separately refuses to interact with a non-allowlisted app while it is frontmost. **Owner: please click the status item once for real and confirm the popover appears** — this is the one C1 behavior I could not verify end-to-end myself. |
| 2026-09-09 | C1 | same | same | n/a | Popover layout + string fit, en/uz/ru at 320pt | pass | Not verifiable via the live popover (see row above), so verified instead by hosting `PopoverView` in a real (off-screen-positioned) `NSWindow` with the actual compiled `.lproj` catalogs and rasterizing it — same AppKit drawing path a real popover uses, just not the literal status-item window. All three languages fit with no truncation or wrapping; Russian's longest string (`main.pwm_safe`, "Режим без мерцания (PWM)") fits on one line. Screenshots sent to the owner directly. |
| 2026-09-09 | C1 | same | same | n/a | State persists across relaunch | pass (automated) | `AppStateTests.test_persistence_roundTrips`; found and fixed a real bug in the process — `Persistence` was passing the app's own bundle ID as a `UserDefaults` suite name, which Foundation logs as invalid and silently does not work as a shared suite (there is no App Group entitlement, so it never could); fixed to use `.standard`. |

Checks to cover (from CLAUDE.md §8): 0K red on every display · ⌘⇧4 screenshot not red · QuickTime recording not red · Zoom/Meet share not red · Fallback-mode screenshot IS red · unplug while ON · sleep/wake · clamshell · fullscreen HDR video · quit restores · kill -9 then relaunch restores · idle CPU < 0.5% · PWM pinned state · brightness key re-pin · 10% brightness via overlay · hotkeys with another app frontmost · login item after reboot · no permission prompts · VoiceOver in en/uz/ru.

## Performance

| Date | Version | Machine | Idle CPU (5 min avg) | Popover open (ms) | Slider latency |
|---|---|---|---|---|---|
