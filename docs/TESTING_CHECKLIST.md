# Dimit beta — tester checklist

Thank you for trying it. This takes 15–20 minutes. Please do the steps in order and send the report at the bottom even if everything worked — "all fine on my Mac" is a result too.

## Install

1. Download the DMG from [GitHub Releases](https://github.com/azakapro/dimit/releases), open it, and drag **Dimit** to **Applications**.
2. This beta is not yet notarized, so macOS will refuse to open it. Open **Terminal** (⌘Space, type Terminal) and paste:
   `xattr -dr com.apple.quarantine /Applications/Dimit.app`
   then open Dimit normally. (The other route — System Settings → Privacy & Security → *Open Anyway* — also works but asks for your password. The old right-click → Open trick no longer works on recent macOS.)
3. Dimit lives in the **menu bar** (top right) — there is no Dock icon. Click the icon to open it.

## Checks

Tick each one; write a sentence if anything was different.

**Colour**
- [ ] Turn it **ON** and drag Warmth all the way left (0K). The whole screen is deep red.
- [ ] Turn it **OFF**. Colours are back to normal immediately.
- [ ] Take a screenshot (⌘⇧4) while red. Open it: it is **not** red. *(Expected — that's the point.)*
- [ ] Record a short screen recording (⌘⇧5) while red and play it back: **not** red.
- [ ] If you can: share your screen in Zoom / Google Meet / Teams while red. The other side sees **normal** colours. Say which app.
- [ ] Drag Brightness below 30%. The screen gets darker than the keyboard keys allow. Take a screenshot: it should look **normal**, not dark. *(Confirmed on the Macs tested so far — tell us if yours differs.)*

**Safety**
- [ ] Quit Dimit from its menu while red. Colours restore.
- [ ] Turn it on, then force-quit it (Activity Monitor → Dimit → Quit → Force Quit). Colours go back to normal the moment it dies? Relaunch it: it remembers it was ON and the tint comes back — then turn it OFF and colours are normal.
- [ ] Turn it on, close the lid or put the Mac to sleep, wake it. The tint is still there (or comes back within a second).
- [ ] If you have an external monitor: plug it in and unplug it while ON. Both screens tint; nothing crashes.

**PWM-Safe (the toggle in the main Dimit window, under the sliders)**
- [ ] Turn PWM-Safe on. Copy the sentence that appears under the toggle. It will be one of: "Keeps the backlight at 100%…" (working), "WAITING FOR DISPLAY", "DISPLAY WON'T HOLD 100%", or "PWM-Safe needs an Apple display or a DDC/CI monitor."
- [ ] With PWM-Safe on, press the keyboard brightness-down key. Within about 5 seconds the brightness jumps back up and a small message appears. Yes / no?
- [ ] Turn PWM-Safe off. Brightness returns to what it was before.

**Everything else**
- [ ] Settings → General: switch language to Uzbek, then Russian, then back. The main window and its presets should change language. (Known and expected in this beta: Settings, onboarding and the schedule screen are still mostly English in Uzbek/Russian — no need to list those.) Anything that looks *wrong* rather than untranslated?
- [ ] Settings → Schedule: choose *Sunset to sunrise* and pick your city. If it's after sunset where you are, the filter turns itself on within a minute; if it's daytime, it turns itself off. Did it?
- [ ] Turn on *Launch at login*, log out and back in (or reboot). Dimit is back in the menu bar.
- [ ] Press ⌃⌥⌘Z while another app is in front. Dimit toggles.
- [ ] Did macOS ask you for **any** permission (Accessibility, Screen Recording, Location, Input Monitoring)? It should not, unless you pressed "Use my location". Which?

## Report

Copy, fill in, and open a [GitHub issue](https://github.com/azakapro/dimit/issues/new?template=bug_report.md):

```
Mac model:            (e.g. MacBook Air M2, 2022)
macOS version:        (Apple menu → About This Mac)
Display(s):           (built-in / external model + cable type)
Dimit version:        (first lines of the diagnostics text below)
Everything ticked?    yes / no
What was different:   (steps → what you expected → what happened)
Diagnostics:          Settings → Advanced → "Copy diagnostics" → paste here
```

The diagnostics text contains your macOS version, Mac model, display list and Dimit's own last 200 log lines. Read it before posting publicly and remove any private details.

Please **don't** send serial numbers or photos of your screen unless the problem is about how the screen looks (then a phone photo is the only thing that shows it — screen recordings can't capture the tint).
