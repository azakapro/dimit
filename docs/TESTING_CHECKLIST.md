# Dimit beta — tester checklist

Thank you for trying it. This takes 15–20 minutes. Please do the steps in order and send the report at the bottom even if everything worked — "all fine on my Mac" is a result too.

## Install

1. Open the DMG, drag **Dimit** to **Applications**.
2. This beta is not yet notarized, so macOS will refuse it on first open: **right-click Dimit.app → Open → Open**. (Or in Terminal: `xattr -d com.apple.quarantine /Applications/Dimit.app`.)
3. Dimit lives in the **menu bar** (top right) — there is no Dock icon. Click the icon to open it.

## Checks

Tick each one; write a sentence if anything was different.

**Colour**
- [ ] Turn it **ON** and drag Warmth all the way left (0K). The whole screen is deep red.
- [ ] Turn it **OFF**. Colours are back to normal immediately.
- [ ] Take a screenshot (⌘⇧4) while red. Open it: it is **not** red. *(Expected — that's the point.)*
- [ ] Record a short screen recording (⌘⇧5) while red and play it back: **not** red.
- [ ] If you can: share your screen in Zoom / Google Meet / Teams while red. The other side sees **normal** colours. Say which app.
- [ ] Drag Brightness below 30%. The screen gets darker than the keyboard keys allow. Take a screenshot: is it dark or normal? *(Tell us either way — this one we genuinely don't know for every Mac.)*

**Safety**
- [ ] Quit Dimit from its menu while red. Colours restore.
- [ ] Turn it on, then force-quit it (Activity Monitor → Dimit → Quit → Force Quit). Relaunch it. Colours are normal after relaunch.
- [ ] Turn it on, close the lid or put the Mac to sleep, wake it. The tint is still there (or comes back within a second).
- [ ] If you have an external monitor: plug it in and unplug it while ON. Both screens tint; nothing crashes.

**PWM-Safe (Settings → PWM-Safe / the toggle in the popover)**
- [ ] Turn PWM-Safe on. What does the status line under it say? (*pinned*, *waiting*, *won't hold*, *unsupported*)
- [ ] With PWM-Safe on, press the keyboard brightness-down key. Within about 5 seconds the brightness jumps back up and a small message appears. Yes / no?
- [ ] Turn PWM-Safe off. Brightness returns to what it was before.

**Everything else**
- [ ] Settings → General: switch language to Uzbek, then Russian, then back. Everything is translated? Note anything still in English.
- [ ] Settings → Schedule: choose *Sunset to sunrise* and pick your city. If it's after sunset where you are, the filter turns itself on within a minute; if it's daytime, it turns itself off. Did it?
- [ ] Turn on *Launch at login*, log out and back in (or reboot). Dimit is back in the menu bar.
- [ ] Press ⌃⌥⌘Z while another app is in front. Dimit toggles.
- [ ] Did macOS ask you for **any** permission (Accessibility, Screen Recording, Location, Input Monitoring)? It should not, unless you pressed "Use my location". Which?

## Report

Copy, fill in, send to the Telegram handle or email in the message that gave you the download:

```
Mac model:            (e.g. MacBook Air M2, 2022)
macOS version:        (Apple menu → About This Mac)
Display(s):           (built-in / external model + cable type)
Dimit version:        (first lines of the diagnostics text below)
Everything ticked?    yes / no
What was different:   (steps → what you expected → what happened)
Diagnostics:          Settings → Advanced → "Copy diagnostics" → paste here
```

The diagnostics text contains your macOS version, Mac model, display list and Dimit's own last 200 log lines — nothing else. Read it before pasting if you like.

Please **don't** send serial numbers or photos of your screen unless the problem is about how the screen looks (then a phone photo is the only thing that shows it — screen recordings can't capture the tint).
