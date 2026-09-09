# QA matrix

One row per check per machine. Fill by hand; a PR that claims a check passed must have its row here.

## Gamma spike (C0)

| Date | Machine | macOS | Auto-brightness | `set` return | read-back green max | Screen turned red? |
|---|---|---|---|---|---|---|
| 2026-09-09 | MacBookPro18,1 M1 Pro | 27.0 (26A5416b) | ON | 0 (success) | 0.0 | **pending — needs human eyes.** Claude Code cannot screencapture (`could not create image from display` — no Screen Recording TCC grant for this process, which is exactly why the spec requires a human here, not a pixel check). Owner: please run `swift scripts/gamma_spike.swift` and confirm the screen actually flashed red for ~4s. |
| | MacBookPro18,1 M1 Pro | 27.0 (26A5416b) | OFF | | | pending — also needs "Automatically adjust brightness" turned off in System Settings → Displays first (not done automatically: system-setting changes are left to the owner). |

## App checks

| Date | Version | Machine | macOS | Display(s) | Check | Result | Notes |
|---|---|---|---|---|---|---|---|

Checks to cover (from CLAUDE.md §8): 0K red on every display · ⌘⇧4 screenshot not red · QuickTime recording not red · Zoom/Meet share not red · Fallback-mode screenshot IS red · unplug while ON · sleep/wake · clamshell · fullscreen HDR video · quit restores · kill -9 then relaunch restores · idle CPU < 0.5% · PWM pinned state · brightness key re-pin · 10% brightness via overlay · hotkeys with another app frontmost · login item after reboot · no permission prompts · VoiceOver in en/uz/ru.

## Performance

| Date | Version | Machine | Idle CPU (5 min avg) | Popover open (ms) | Slider latency |
|---|---|---|---|---|---|
