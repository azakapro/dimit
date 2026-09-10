# CLAUDE.md — Dimit: blue-light + PWM-flicker utility for macOS, then Windows

> **Build order is MVP-first (decided 2026-09-09).** Work goes in cycles C0…C7 defined in `docs/PLAN.md` §2, one PR each. C0–C6 have shipped (v0.1–v0.4): the display engine, PWM-Safe, presets, three languages, settings, scheduling, experimental DDC and release tooling. **C7 is free, open-source distribution through GitHub Releases and opt-in updates.** Every cycle starts with the prompt at the top of `docs/PLAN.md` §2, and every PR must satisfy `docs/PLAN.md` §3 and `.github/pull_request_template.md`.
>
> **Distribution decided 2026-09-10:** Dimit is **free and open source under the MIT licence**, copyright **2026 Azizullo Temirov**. Downloads come from [GitHub Releases](https://github.com/azakapro/dimit/releases); the README is the product page. Sparkle uses the appcast at `https://azakapro.github.io/dimit/appcast.xml`, served from the repository's `docs/` folder by GitHub Pages. §4 below and `docs/ARCHITECTURE.md` §4 define distribution and the network policy.
>
> **Project identity:** product name **Dimit**, bundle ID `app.dimit.mac`, author **Azizullo Temirov**.
>
> **Dev machine facts** (2026-09-08): MacBook Pro 16" M1 Pro (built-in XDR), macOS **27.0 beta** (26A5416b), no Xcode installed yet, one external monitor available at home, auto-brightness ON. There is no macOS 13–26 machine; older-OS QA comes from beta testers or a macOS 26 install on an external SSD. **Run `swift scripts/gamma_spike.swift` before writing any display code** (see §3.3 and M0).

---

## 0. One-paragraph brief

Build a native macOS menu-bar app that (1) warms the screen from 6500K down to a pure-red "0K" by rewriting the display gamma tables, (2) dims the screen in software, (3) offers a **PWM-Safe mode** that pins supported hardware backlights at 100% and does dimming in software, (4) manages connected displays, (5) ships in **Uzbek (Latin), Russian and English**, and (6) is **free and open source under MIT**, available from GitHub Releases or built from source. No accounts, no licence keys, no trial, no activation, no analytics, no telemetry, and no application server. Hardware support and capture limitations must be described against the evidence in `docs/QA.md`. Phase 2 is a Windows port with feature parity.

---

## 1. Non-negotiable product rules

1. **Two sliders, three presets, one button.** Warmth (6500K→0K), Brightness (100%→10%), presets DAY/EVENING/NIGHT, a big ON/OFF ("ZAP") button. Anything else lives behind a Settings gear.
2. **Zero network traffic by default.** The only exception is Sparkle updates: automatic checks are opt-in and default off; choosing "Check for Updates…" explicitly consents to a one-off check without enabling automatic checks. Without either action there are no requests. No crash reporters, no analytics SDKs, no activation calls, no "phone home" of any kind.
3. **No accounts, no licence keys, no trial.** Every copy is identical and fully functional forever. No code may gate a feature on payment (§4).
4. **Screenshots, screen recordings and screen-shares must not be tinted.** Gamma tables satisfy this; the Extreme-Dim overlay window must set `sharingType = .none`.
5. **Never require Accessibility, Screen Recording or admin.** (We will use private frameworks via `dlopen`; that is allowed outside the App Store. We are **not** an App Store app.)
6. **Every user-visible string goes through the String Catalog** (`Localizable.xcstrings`) with `en`, `uz`, `ru`. No hard-coded English. Uzbek is **Latin script**.
7. **No medical claims** in any language. Allowed: "removes blue light", "stops backlight flicker", "may help with eye strain (see studies)". Not allowed: "cures", "treats", "prevents disease".
8. **Fail safe.** On quit, crash, sleep or display reconfiguration, the display must return to (or be restorable to) normal colours. Gamma is restored with `CGDisplayRestoreColorSyncSettings()`; overlay windows are torn down.

---

## 2. Stack and repo layout

- **Language/UI:** Swift 5.10+, AppKit for the menu-bar item + `NSPopover`, SwiftUI for the popover content and Settings window. Minimum **macOS 13 Ventura**. Universal binary (arm64 + x86_64).
- **Identity:** product name `Dimit`, bundle ID `app.dimit.mac`, both as constants in `Config.swift` (`PRODUCT_NAME`, `PRODUCT_BUNDLE_ID`). Menu-bar name "Dimit".
- **Build:** Xcode 26 or newer (whatever runs on the dev machine's macOS 27 beta; download from developer.apple.com, not the App Store). Swift 6 toolchain with **Swift 5 language mode** to avoid strict-concurrency churn in AppKit code. Swift Package Manager only (no CocoaPods). Dependencies allowed: `sparkle-project/Sparkle` (updates), `sindresorhus/KeyboardShortcuts` (global hotkey), `sindresorhus/LaunchAtLogin-Modern` or `SMAppService` directly. Nothing else without asking.
- **No application server.** GitHub Releases hosts release artifacts and GitHub Pages serves the static Sparkle appcast; no backend, database or authentication service (§4).
- **Product page:** `README.md`, with installation, tested systems and honest limitations. Release artifacts live in GitHub Releases; only the appcast needs Pages (`docs/ARCHITECTURE.md` §4).
- **Windows (phase 2):** C++20 / Win32, no frameworks, folder `windows/`. Spec in §11.

```
dimit/
  CLAUDE.md
  Dimit.xcodeproj / Package.swift
  Dimit/
    App/            DimitApp.swift, AppDelegate.swift, Config.swift
    Display/        DisplayManager.swift, GammaController.swift, BrightnessController.swift,
                    DDCController.swift, OverlayDimmer.swift, WarmthCurve.swift, DisplayModels.swift
    Features/       PresetStore.swift, ScheduleEngine.swift, ScheduleCoordinator.swift,
                    PWMSafeCoordinator.swift, HotkeyManager.swift
    UI/             MenuBarController.swift, PopoverView.swift, SettingsView.swift, OnboardingView.swift,
                    Settings/, Components/
    Resources/      Localizable.xcstrings, Assets.xcassets, Studies.md
    Support/        Logger.swift, DiagnosticsBundle.swift, Persistence.swift
  DimitTests/       WarmthCurveTests, ScheduleEngineTests, GammaMathTests, DDCTests, …
  scripts/          bootstrap.sh, build_dmg.sh, notarize.sh, make_appcast.sh
  docs/             ARCHITECTURE.md, PLAN.md, QA.md, RELEASE.md, appcast.xml
```

---

## 3. Display engine — the core

### 3.1 Enumerate displays
`CGGetActiveDisplayList` → for each `CGDirectDisplayID` build `DisplayInfo { id, uuid (CGDisplayCreateUUIDFromDisplayID), name (from NSScreen.localizedName), isBuiltin (CGDisplayIsBuiltin), isAppleDisplay (vendor 0x610 via IOKit/`CGDisplayVendorNumber`), supportsDDC }`. Register `CGDisplayRegisterReconfigurationCallback` to re-enumerate and **re-apply** on any change (plug/unplug, sleep/wake, resolution change). Also observe `NSWorkspace.didWakeNotification` and `screensDidWakeNotification` and re-apply after a 1.0 s delay (WindowServer resets gamma on wake).

### 3.2 Warmth → RGB multipliers (`WarmthCurve.swift`)
- Input: Kelvin `k ∈ [0, 6500]`. Output: `(r, g, b) ∈ [0,1]³`, with `(1,1,1)` at 6500K.
- For `k ≥ 1000`: use the Tanner Helland / Krystek CCT→RGB approximation (white point 6500K normalized to 1.0). Unit-test known points: 6500K≈(1,1,1); 2700K≈(1, 0.72–0.78, 0.45–0.55); 1900K≈(1, 0.55–0.62, 0.20–0.30).
- For `k < 1000` ("below the physics"): linearly interpolate from the 1000K value down to **(1, 0, 0) at k=0**. This is the "0K = pure red" behaviour. Green must reach exactly 0 and blue exactly 0 at k=0.
- Optional "chromaticity mode": compute in CIE xy and convert; ship the simple curve first, keep the function signature stable.

### 3.3 Gamma tables (`GammaController.swift`)
- Read original tables once per display at first touch with `CGGetDisplayTransferByTable` (capacity via `CGDisplayGammaTableCapacity`) and cache them as the restore baseline.
- Build tables: for i in 0..<n: `x = i/(n-1)`; `r[i] = orig_r[x] * mulR * dim`, same for g, b, where `dim ∈ [dimFloor, 1]` is the software brightness. Apply with `CGSetDisplayTransferByTable(displayID, n, r, g, b)`.
- Apply to all displays unless `perDisplay` override exists (Settings → per-display sliders, off by default).
- Restore: `CGDisplayRestoreColorSyncSettings()` on OFF, on quit (`applicationWillTerminate`), and from a `atexit`/signal handler for crashes (SIGTERM/SIGINT; do not try to handle SIGSEGV elaborately).
- **Verification step (mandatory, this is the Tahoe workaround):** after applying, read back with `CGGetDisplayTransferByTable`. Read-back succeeding does **not** prove the screen changed (the Tahoe bug returns success and stores the table but the display ignores it), and we cannot sample pixels without the Screen Recording permission. So: (a) on macOS ≥ 26, and (b) if auto-brightness is detectably enabled — **the `com.apple.BezelServices dAuto` key does not exist on macOS 27** (checked 2026-09-08); spend at most 2 hours in C3 looking for a replacement (candidates: `com.apple.CoreBrightness` prefs, `CBClient` in the private CoreBrightness framework, keys under `AppleARMBacklight` in `ioreg`), and if nothing reliable is found, skip detection and show the banner unconditionally on macOS ≥ 26 the first time the filter is turned ON, dismissable forever — show a one-time banner "Automatic brightness can block colour changes on macOS 26 — turn it off in System Settings → Displays" with a button that opens `x-apple.systempreferences:com.apple.Displays-Settings.extension`. And (c) ~~provide Fallback mode~~ — **removed 2026-09-10 by maintainer decision ("too confusing")**: the overlay-tint escape hatch built in C3 and briefly offered from the banner after the 26.6.2 report is gone (`AppState.fallbackMode`, `OverlayTint.red`, `Config.fallbackMaxWarmthVeil`, the Advanced toggle, the menu item, all `fallback.*` strings). Consequence, stated plainly in the README: on Macs where Apple ignores the table, Dimit cannot change colours until Apple fixes it; dimming below 30% (black overlay) and PWM-Safe still work. The overlay window itself stays, for the dim floor.
- Known Apple bugs to reference in code comments: FB18559786, FB19136488, FB22273730 (developer.apple.com/forums/thread/795074 and /819331).
- **As found in the field, 2026-09-10 (first stable-macOS tester, MacBook Pro XDR on 26.6.2, docs/QA.md § "First stable-macOS report"):** the bug is real on a shipping OS with auto-brightness and True Tone already off — 0K left the screen its normal colours, and because PWM-Safe still pinned the backlight while the software dim never landed, the screen got *brighter*. Both forum threads confirm it (DTS reproduced on 26.3.1–26.5.1; f.lux users swap colour profiles nightly), and thread 819331 adds that on XDR panels toggling auto-brightness can leave the table "looking permanently bad" — so the banner's old advice was not just insufficient but risky there. For one day the banner offered a one-tap Fallback mode; the maintainer then removed Fallback mode entirely (see (c) above), so the banner now names the bug and the auto-brightness step that helps on many machines, and the README's macOS 26 limitations section says the rest. `ColorSyncDeviceSetCustomProfiles()` is the one alternative path the threads mention — unconfirmed, system-wide, and not attempted.

### 3.4 Hardware brightness (`BrightnessController.swift`)
- **Apple displays (built-in, Studio Display, Pro Display XDR):** load `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices` with `dlopen`, `dlsym` → `DisplayServicesGetBrightness(CGDirectDisplayID, float*) -> Int32` and `DisplayServicesSetBrightness(CGDirectDisplayID, float) -> Int32`. Fallback: `CoreDisplay_Display_SetUserBrightness` / `CoreDisplay_Display_GetUserBrightness` from `CoreDisplay.framework`. Wrap in a protocol `BrightnessBackend` with `canControl(display)`, `get`, `set`, and return `.unsupported` cleanly when symbols are missing (future macOS may remove them).
- **Third-party external displays:** DDC/CI VCP code `0x10` (brightness) via IOKit. On Apple Silicon use the IOAVService path (`IOAVServiceCreateWithService`, `IOAVServiceWriteI2C`/`ReadI2C`, as used by `m1ddc`/MonitorControl/OpenDisplay); on Intel use `IOFramebuffer` I2C (`IOI2CSendRequest`). Implemented in `DDCController.swift` in C5b, to be tested on the one external monitor available (record vendor/model/connection in `docs/QA.md`). Ships in 1.0 as an **Experimental** toggle in Settings (`Config.ddcEnabled`, default OFF); promoted to default ON in 1.1 after a second monitor and beta feedback.
- **Verification without private APIs:** on Apple Silicon the built-in backlight exposes `IODisplayParameters.brightness {min 0, max 65536, value}` under `AppleARMBacklight` in the IORegistry (observed on the dev machine). Use it as a read-only cross-check for the PWM pin when the DisplayServices read-back is unavailable.
- **As built in C5b, two disclosed deviations from the paragraph above.** (1) `Config.ddcEnabled` landed as **`AppState.ddcEnabled`** — persisted and bound to a real Settings toggle, which a `static var` could be neither; `Config.swift` carries a note pointing here rather than a dead second copy. (2) The `IOMobileFramebufferShim` class that `m1ddc` matches against **does not exist on macOS 27** (verified: it matches zero services); the working path is `DCPAVServiceProxy`, whose `Location` property reads `Embedded` for the built-in panel and `External` otherwise. DDC resolution is also deliberately limited to the unambiguous case — exactly one external display and one `External` proxy — because guessing which proxy belongs to which `CGDirectDisplayID` would mean writing brightness to the wrong monitor; multi-monitor DDC needs someone with two external displays to verify an ordering heuristic first.
- Never call set-brightness more than 4×/second (some panels wear or lag).

### 3.5 Extreme dim overlay (`OverlayDimmer.swift`)
- Gamma dimming floor is 30% (below that, banding and lost text). For 10–30% add a borderless `NSWindow` per screen: `level = .screenSaver + 1` (above everything incl. menu bar), `ignoresMouseEvents = true`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, `sharingType = .none` (excluded from screen capture), black with alpha `1 - (brightness/0.30)`.
- Must not appear in Mission Control thumbnails as a separate window in a confusing way (`.stationary` handles it); must survive Spaces switches; must be recreated on display reconfiguration.

### 3.6 PWM-Safe mode (`PWMSafeCoordinator.swift`)
State machine per display: `off → pinning → pinned(verified) | unsupported | wontHold`.
- On enable: for each display with a `BrightnessBackend`: remember current hardware brightness, set 1.0, wait 300 ms, read back; if ≥ 0.99 → `pinned`; else retry twice then `wontHold` (UI: "DISPLAY WON'T HOLD 100%"). Displays without a backend → `unsupported` (UI: "PWM mode needs an Apple display or a DDC/CI monitor").
- While pinned: map the Brightness slider entirely to gamma `dim` (+ overlay below 30%). Re-pin on wake, on reconfiguration, and whenever the read-back drifts (poll every 5 s while pinned; stop polling when off). Detect user pressing the hardware brightness keys (read-back drops) → show "PWM-Safe re-pinned brightness to 100%; use the in-app slider" once per session.
- On disable: restore remembered hardware brightness.
- Auto-brightness: we cannot disable it without root; we detect it (best effort) and show the banner from 3.3.
- Battery note in UI: "Backlight stays at 100% — slightly more battery use."

### 3.7 Presets, state, persistence
- Presets: `DAY 4000K/100%`, `EVENING 2700K/80%`, `NIGHT 0K/40%`. User-editable; "reset to defaults".
- `AppState` (single `@Observable` class — **C1 uses `ObservableObject` + `@Published` instead**, disclosed in a code comment: `@Observable` needs macOS 14+ and this file fixes the deployment target at 13; mechanical swap if that ever changes): `isOn, warmthK, brightness, pwmSafe, activePreset, presetOverrides, scheduleConfig, ddcEnabled, launchAtLogin, updateChecksEnabled, locale`. Persist in `UserDefaults.standard`, debounced 250 ms — **not** `UserDefaults(suiteName: PRODUCT_BUNDLE_ID)` as an earlier draft of this file said: passing an app's own bundle ID as a suite name is not a real app-group suite (Foundation logs "does not make sense and will not work"), and a real one needs an App Groups entitlement we don't have per §1.5. Apply pipeline is a single pure function `render(state, displays) -> [DisplayCommand]` so it is unit-testable.

### 3.8 Scheduling (`ScheduleEngine.swift`)
- Modes: **Manual** (default), **Sunset→Sunrise** (uses `CoreLocation` *only if user grants* — otherwise fall back to a user-chosen city from a bundled list with lat/lon: Tashkent, Samarkand, Bukhara, Namangan, Andijan, Fergana, Nukus, Moscow, Almaty, Bishkek, Dushanbe, Istanbul, London, New York… plus manual lat/lon), **Fixed times**.
- Transition: linear ramp over a user-set duration (default 20 min) from DAY preset to EVENING at sunset and to NIGHT at "bedtime" (default 22:30 local). Compute sunrise/sunset locally with the NOAA solar algorithm (unit tests vs known values for Tashkent on 2026-09-08). No network.

### 3.9 Hotkeys, login item, menu bar
- Global hotkeys via `KeyboardShortcuts`: toggle ON/OFF (default ⌃⌥⌘Z), cycle presets, warmth ±, brightness ±.
- Menu bar icon: outline when OFF, filled when ON, small dot when PWM pinned. Left-click opens the popover; right-click shows a context menu (presets, toggle, settings, quit).
- Launch at login via `SMAppService.mainApp` (macOS 13+).

---

## 4. Distribution

**Dimit is free and open source under the MIT licence**, copyright **2026 Azizullo Temirov**. The root `LICENSE` contains the licence terms. See `docs/ARCHITECTURE.md` §4 for the distribution and update design.

### 4.1 Downloads and source

- Download the DMG from [GitHub Releases](https://github.com/azakapro/dimit/releases), or build the app from the source repository. The README is the product page.
- **The app is unconditional.** Every copy is fully functional forever: no key, no trial, no seat count, no activation, no expiry, no kill switch, no "pro" tier. **No code may ever gate a feature on payment.**
- Each release attaches its DMG and Sparkle ZIP to the same GitHub Release. When signing and notarization are available, both contain the same notarized app. Until then, installation instructions must disclose the ad-hoc signature and lack of notarization.

### 4.2 What the app collects, stores and logs

**Nothing that identifies anyone.** No accounts, no analytics, no telemetry, no crash reporter, no device ID, no email address, no Keychain secret, no persistent identifier of any kind. Log failures, never payloads. The diagnostics bundle (§7) is assembled locally and copied to the user's own clipboard — the app never transmits it, and the user can read every line before pasting it anywhere. This rule outranks convenience: a feature that needs an identifier does not ship.

### 4.3 Network

The app makes **no network request by default**. Sparkle is the only network-capable feature. `updateChecksEnabled` and `SUEnableAutomaticChecks` default to `false`; automatic checks require explicit opt-in in onboarding or Settings. Choosing "Check for Updates…" is explicit consent to a one-off check and leaves the automatic-check preference unchanged. Without either action, Sparkle must issue no request. C7 verifies that behaviour with a network monitor as well as code review. Any PR that adds an outbound call has to name it in the description (`docs/PLAN.md` §3) and justify it against this rule.

The feed is `https://azakapro.github.io/dimit/appcast.xml`, generated as `docs/appcast.xml` and served by GitHub Pages. Its enclosure URLs point to GitHub Release ZIP assets; Sparkle verifies each update's EdDSA signature. No application server, accounts, authentication, database or telemetry service is needed.

### 4.4 Support

Bug reports use GitHub Issues. The README may carry a single optional support link (Buy Me a Coffee) once the maintainer has an account — never a placeholder URL on a public repo; the maintainer replaces the placeholder before using it. Support buys no features. Do not add this link or any support-payment UI to the app.

## 5. Localization (EN / UZ / RU)

- `Localizable.xcstrings` with the three locales; **Uzbek locale code `uz`** (Latin is the default for `uz` on Apple platforms; do not use `uz-Cyrl`). Russian `ru`. Use plural rules for count-dependent strings.
- App follows the system language; Settings has a language override (`AppleLanguages`-free: we store `locale` and set `Bundle` on relaunch).
- Menu bar / popover must fit 1.4× English string length. Test with Russian, which is longest.
- Number/temperature formatting: "6500 K" with a space in UZ/RU, "6500K" in EN.

### 5.1 String table (initial; Claude Code must add to this, never hard-code)

| key | en | uz | ru |
|---|---|---|---|
| app.name | Dimit | Dimit | Dimit |
| main.on | ON | YOQISH | ВКЛ |
| main.off | OFF | O'CHIRISH | ВЫКЛ |
| main.warmth | Warmth | Iliqlik | Теплота |
| main.brightness | Brightness | Yorqinlik | Яркость |
| main.pwm_safe | PWM‑Safe mode | PWM‑xavfsiz rejim | Режим без мерцания (PWM) |
| main.pwm_safe.help | Keeps the backlight at 100% and dims in software, so the screen never flickers. Uses slightly more battery. | Orqa yoritishni 100% da ushlab, yorqinlikni dasturiy pasaytiradi — ekran umuman miltillamaydi. Batareya biroz ko'proq sarflanadi. | Держит подсветку на 100% и уменьшает яркость программно — экран не мерцает. Немного больше расход батареи. |
| preset.day | DAY | KUN | ДЕНЬ |
| preset.evening | EVENING | KECH | ВЕЧЕР |
| preset.night | NIGHT | TUN | НОЧЬ |
| warmth.zero_k.tip | "0K" is a name, not a physical temperature: at 0K only red light remains. | "0K" — bu nom, fizik harorat emas: 0K da faqat qizil nur qoladi. | «0K» — это название, а не физическая температура: при 0K остаётся только красный свет. |
| pwm.waiting | WAITING FOR DISPLAY | DISPLEY KUTILMOQDA | ОЖИДАНИЕ ДИСПЛЕЯ |
| pwm.wont_hold | DISPLAY WON'T HOLD 100% | DISPLEY 100% NI USHLAMAYAPTI | ДИСПЛЕЙ НЕ ДЕРЖИТ 100% |
| pwm.unsupported | PWM‑Safe needs an Apple display or a DDC/CI monitor. | PWM‑xavfsiz rejim uchun Apple displeyi yoki DDC/CI monitor kerak. | Для режима без мерцания нужен дисплей Apple или монитор с DDC/CI. |
| pwm.repinned | Brightness was re‑pinned to 100%. Use the slider in the app. | Yorqinlik yana 100% ga qaytarildi. Ilova ichidagi slayderdan foydalaning. | Яркость снова зафиксирована на 100%. Используйте ползунок в приложении. |
| banner.gamma_blocked *(replaced banner.autobrightness 2026-09-10; uz/ru need human review)* | On macOS 26 an Apple bug can stop Dimit from changing your screen's colours on some Macs. Turning off automatic brightness in System Settings → Displays fixes it on many of them. | macOS 26 da Apple xatosi tufayli Dimit ba'zi Mac'larda ekran ranglarini o'zgartira olmasligi mumkin. Tizim sozlamalari → Displeylar bo'limida avtomatik yorqinlikni o'chirish ko'pchiligida yordam beradi. | В macOS 26 из-за ошибки Apple Dimit на некоторых Mac не может менять цвета экрана. Отключение автояркости в Системных настройках → Дисплеи помогает на многих из них. |
| banner.open_settings | Open Displays settings | Displey sozlamalarini ochish | Открыть настройки дисплеев |
| banner.dismiss *(added C3, uz/ru need human review)* | Dismiss | Dismiss — TODO(i18n) | Dismiss — TODO(i18n) |
| schedule.title | Schedule | Jadval | Расписание |
| schedule.manual | Manual | Qo'lda | Вручную |
| schedule.sun | Sunset to sunrise | Quyosh botishidan chiqishigacha | От заката до рассвета |
| schedule.fixed | Fixed times | Belgilangan vaqt | Заданное время |
| schedule.city | City | Shahar | Город |
| schedule.transition | Transition | O'tish davomiyligi | Плавный переход |
| settings.title | Settings | Sozlamalar | Настройки |
| settings.launch_at_login | Launch at login | Kirishda ishga tushirish | Запускать при входе |
| settings.hotkeys | Keyboard shortcuts | Tezkor tugmalar | Горячие клавиши |
| settings.per_display | Separate settings per display | Har bir displey uchun alohida | Отдельно для каждого дисплея |
| settings.updates | Check for updates automatically | Yangilanishlarni avtomatik tekshirish | Проверять обновления автоматически |
| settings.language | Language | Til | Язык |
| settings.copy_diag | Copy diagnostics for support | Diagnostikani nusxalash (yordam uchun) | Скопировать диагностику для поддержки |
| onboarding.1.title | Block blue light. Stop the flicker. | Ko'k nurni to'sing. Miltillashni to'xtating. | Уберите синий свет. Остановите мерцание. |
| onboarding.1.body | Two sliders, three presets, one button. | Ikki slayder, uch rejim, bitta tugma. | Два ползунка, три режима, одна кнопка. |
| onboarding.2.title | Your screenshots stay normal | Skrinshotlar oddiy qoladi | Скриншоты остаются обычными |
| onboarding.3.title | No account. No tracking. | Akkaunt yo'q. Kuzatuv yo'q. | Без аккаунта. Без слежки. |
| menu.quit | Quit | Chiqish | Выйти |
| menu.settings | Settings… | Sozlamalar… | Настройки… |
| menu.restore_colours *(added C2)* | Restore Colours | Restore Colours — TODO(i18n), needs a real uz translation | Restore Colours — TODO(i18n), needs a real ru translation |
| onboarding.2.body *(added C4)* | Screenshots, recordings and calls keep their normal colours. | TODO(i18n) | TODO(i18n) |
| onboarding.3.body *(added C4, rewritten 2026-09-09)* | No account, no analytics, no tracking. Dimit connects to the internet only if you turn on update checks. | TODO(i18n) | TODO(i18n) |
| onboarding.next *(added C4)* | Next | TODO(i18n) | TODO(i18n) |
| onboarding.get_started *(added C4)* | Get Started | TODO(i18n) | TODO(i18n) |
| settings.tab.general / .displays / .advanced *(added C4)* | General / Displays / Advanced | TODO(i18n) | TODO(i18n) |
| settings.presets_title *(added C4)* | Presets | TODO(i18n) | TODO(i18n) |
| settings.preset_reset *(added C4)* | Reset | TODO(i18n) | TODO(i18n) |
| settings.preset_reset_all *(added C4)* | Reset All to Defaults | TODO(i18n) | TODO(i18n) |
| settings.display_backend *(added C4)* | Backend: %@ | TODO(i18n) | TODO(i18n) |
| settings.display_no_backend *(added C4)* | No brightness backend | TODO(i18n) | TODO(i18n) |
| settings.display_builtin / .display_apple *(added C4)* | Built-in / Apple display | TODO(i18n) | TODO(i18n) |
| settings.diagnostics_copied *(added C4)* | Diagnostics copied to clipboard | TODO(i18n) | TODO(i18n) |
| settings.language_system / _en / _uz / _ru *(added C4)* | System / English / Uzbek / Russian | TODO(i18n) | TODO(i18n) |
| settings.launch_at_login_error *(added C4)* | Couldn't change the login item: %@ | TODO(i18n) | TODO(i18n) |
| hotkey.section_title *(added C4)* | Global Shortcuts | TODO(i18n) | TODO(i18n) |
| hotkey.toggle / .cycle_presets / .warmth_up / .warmth_down / .brightness_up / .brightness_down *(added C4)* | Toggle Dimit / Cycle Presets / Warmth Up / Warmth Down / Brightness Up / Brightness Down | TODO(i18n) | TODO(i18n) |
| schedule.mode_title *(added C5)* | Mode | TODO(i18n) | TODO(i18n) |
| schedule.use_location *(added C5)* | Use my location | TODO(i18n) | TODO(i18n) |
| schedule.location_none / .location_using_city / .location_using_coordinates *(added C5)* | No location set / Using: %@ / Using manual coordinates | TODO(i18n) | TODO(i18n) |
| schedule.location_denied / .location_failed *(added C5)* | Location access denied. Choose a city instead. / Couldn't get your location. Choose a city instead. | TODO(i18n) | TODO(i18n) |
| schedule.manual_coordinates / .latitude / .longitude / .apply_coordinates *(added C5)* | Manual coordinates / Latitude / Longitude / Use These Coordinates | TODO(i18n) | TODO(i18n) |
| schedule.fixed_day_start / .fixed_evening_start / .bedtime *(added C5)* | Day starts at / Evening starts at / Bedtime | TODO(i18n) | TODO(i18n) |
| schedule.ramp_minutes_value *(added C5)* | %d min | TODO(i18n) | TODO(i18n) |
| schedule.city.tashkent / .samarkand / .bukhara / .namangan / .andijan / .fergana / .nukus / .moscow / .almaty / .bishkek / .dushanbe / .istanbul / .london / .new_york *(added C5)* | Tashkent / Samarkand / Bukhara / Namangan / Andijan / Fergana / Nukus / Moscow / Almaty / Bishkek / Dushanbe / Istanbul / London / New York | Toshkent / Samarqand / Buxoro / Namangan / Andijon / Farg'ona / Nukus / Moskva / Almati / Bishkek / Dushanbe / Istanbul / London / Nyu-York | Ташкент / Самарканд / Бухара / Наманган / Андижан / Фергана / Нукус / Москва / Алматы / Бишкек / Душанбе / Стамбул / Лондон / Нью-Йорк — standard geographic exonyms, provided directly rather than marked TODO(i18n): factual/referential data (the way any atlas renders these names), not creative or marketing copy. |

| settings.ddc_experimental *(added C5b)* | DDC/CI brightness control (Experimental) | TODO(i18n) | TODO(i18n) |
| settings.ddc_help *(added C5b)* | Lets PWM‑Safe mode pin the backlight on third-party external monitors over DDC/CI. Off by default, and untested on real hardware — turn it on only if you're willing to report what happens. | TODO(i18n) | TODO(i18n) |
| settings.ddc_single_display_only *(added C5b)* | Only used when exactly one external monitor is connected — with several, Dimit can't yet tell which is which and leaves them alone. | TODO(i18n) | TODO(i18n) |

There are no activation or feature-gating strings (§4).

(Claude Code: when adding a string, add all three languages; if unsure of Uzbek/Russian, add the English and mark `// TODO(i18n)` so a human translator sees it. Do not machine-translate silently. In the catalog, TODO(i18n) is represented as the English value with `state: needs_review` for uz/ru — Xcode's String Catalog editor flags those for a translator.)

---

## 7. Signing, notarization, updates, distribution

- Developer ID Application certificate; hardened runtime ON; entitlements: none special (no sandbox). `scripts/notarize.sh` runs `xcrun notarytool submit … --wait` then `stapler`.
- DMG with an Applications symlink and a `.zip` of the same app for Sparkle, both attached to the GitHub Release. **As built in C6:** `scripts/build_dmg.sh` uses `hdiutil`, not `create-dmg`, and ships no background image — the tool's only contribution over hdiutil is cosmetics, and §12 says a dependency has to earn its place. The order is fixed by `scripts/notarize.sh`: notarize + staple the **app** first, then build the DMG from the stapled app, then notarize + staple the DMG — so a copy dragged out of the image launches offline.
- Sparkle 2 with EdDSA keys; `docs/appcast.xml` is served at `https://azakapro.github.io/dimit/appcast.xml` by GitHub Pages. Automatic update checks are **opt-in**, default off; the manual menu item provides explicit one-off consent (§4.3). The private key lives in the login Keychain and is never committed.
- Upload the release artifacts before publishing their appcast entry, so the enclosure URL resolves when a user checks for updates. Keep old release assets available for existing feed entries (`docs/ARCHITECTURE.md` §9).
- Version scheme `MAJOR.MINOR` (v0.1–v0.4 exist as tags; `1.0` is the launch); build number = UTC date to the minute, `YYYYMMDDHHMM`, generated by `scripts/build.sh` — Sparkle orders updates by it, so it must be unique per build and never decrease (hour resolution collided twice on the first v0.4 day).
- Diagnostics bundle (`DiagnosticsBundle.swift`): macOS version, hardware model, displays (name, builtin, vendor, DDC support, brightness backend), app version, last 200 log lines. Nothing that identifies the user (§4.2). Copied to clipboard as text, so the user can read it before sending it anywhere.

---

## 8. Quality bar / acceptance tests (must pass before each milestone is "done")

- Unit: `WarmthCurve` known points; 0K yields (1,0,0); gamma tables monotonic and clamped; `ScheduleEngine` sunset for Tashkent 2026-09-08 within ±3 min of NOAA; `render()` idempotent; `PWMSafeCoordinator` against a fake backend.
- Manual matrix (document results in `docs/QA.md`): MacBook Air/Pro built-in; one external monitor over USB-C; one over HDMI; clamshell mode; sleep/wake; unplug while ON; fullscreen video (Safari/YouTube, HDR clip); screenshot ⌘⇧4 while at 0K is **not** red; QuickTime screen recording is not red; Zoom/Google Meet share is not red; quit → colours restore; `kill -9` → colours restore on relaunch ("Restore colours" button in onboarding for safety); macOS 13, 14, 15, 26 (Tahoe) with auto-brightness on and off.
- Performance: idle CPU < 0.5% (Activity Monitor, 5-minute average); popover opens < 100 ms; slider-to-screen latency < 50 ms.
- Accessibility: VoiceOver labels for both sliders and all buttons in all three languages; full keyboard operation.
- No Accessibility/Screen Recording/Location prompts unless the user enables Sunset schedule with "Use my location".

---

## 9. Cycles (each ends with a build, a short demo GIF and a PR)

**The authoritative scope, "Done when" lists, model per cycle and PR rules are in `docs/PLAN.md` §2–§3.** The summary below is for orientation only; where they differ, PLAN.md wins.

| Cycle | Tag | Content | Model |
|---|---|---|---|
| C0 | — | Xcode installed, gamma spike run with auto-brightness on/off, results in `docs/QA.md` | Sonnet 5 |
| C1 | — | Xcode project, `AppState`, menu-bar item + popover, String Catalog (§5.1), `WarmthCurve` + `render()` with tests; **no display calls yet** | Sonnet 5 |
| C2 | — | `DisplayManager`, `GammaController`, applier, restore on OFF/quit/signals/launch, multi-display, wake/reconfigure | Opus 5 |
| C3 | **v0.1 MVP** | Brightness backends, `PWMSafeCoordinator`, overlay for <30%, Fallback mode (removed 2026-09-10), auto-brightness banner, icon states | Opus 5 |
| C4 | v0.2 | Settings window, hotkeys, login item, onboarding, diagnostics, VoiceOver | Sonnet 5 |
| C5 | v0.3 | `ScheduleEngine`, DDC/CI experimental | Sonnet 5 / Opus 5 |
| C6 | v0.4 | Release scripts, signed + notarized DMG, testers, QA + capture matrix, fixes | Sonnet 5 |
| C7 | **v1.0** | MIT licence, GitHub Releases, README product page, contribution guidance, Sparkle opt-in with Pages appcast | Sonnet 5 |
| Phase 2 | v2 | Windows (§11) | — |

C0–C6 are merged and tagged (`v0.1`–`v0.4`, 2026-09-09/10). C7 includes the open-source distribution changes decided on 2026-09-10; `v1.0` remains subject to the engineering and release checks in `docs/PLAN.md` §1–§2.

`docs/PLAN.md` §1–§2 is the only schedule. A few older comments still say "M4" where they mean C5's DDC work; read them as cycle names.

---

## 10. Non-goals for 1.0
Licence keys, trials, seats or activation (§4) · feature gating or payment UI · an application backend (no server, no database, no auth: see §12) · per-display overrides (1.1) · chromaticity warmth mode (1.1) · per-app exclusions · iOS/Android · Linux · App Store distribution (gamma/private APIs require direct distribution) · subscriptions · accounts · cloud sync · analytics · Philips Hue.

---

## 11. Phase 2 — Windows port (spec only; do not start before 1.0)

- C++20, Win32, no frameworks. Tray icon + a single WS_POPUP window drawn with Direct2D; same two sliders/three presets/one button; i18n via resource string tables (en/uz/ru) or a JSON bundle.
- **Colour, primary path:** Magnification API — `MagInitialize()`, `MagSetFullscreenColorEffect(MAGCOLOREFFECT*)` with a 5×5 matrix `[r,0,0,0,0; 0,g,0,0,0; 0,0,b,0,0; 0,0,0,1,0; 0,0,0,0,1]` scaled by `dim`. Requires the process to be **DPI-aware** and works at the compositor, so screenshots via PrintScreen are usually untinted; verify and document. Known failures: some DRM video (Netflix) and exclusive-fullscreen games → **Legacy mode**.
- **Colour, legacy path:** `SetDeviceGammaRamp(hdc, WORD ramp[3][256])` per monitor DC (`CreateDC("DISPLAY", monitorName…)`). Windows rejects strong ramps unless `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM\GdiIcmGammaRange` (DWORD) = `256`; implement the "COLORS BLOCKED BY WINDOWS. CLICK TO FIX" bar that runs an elevated helper (UAC prompt) to set that value and asks for restart. Same trick f.lux uses; safe and reversible (document it).
- **Brightness pin:** laptop panels via WMI `root\WMI` → `WmiMonitorBrightnessMethods.WmiSetBrightness(timeout, 100)`, read back with `WmiMonitorBrightness.CurrentBrightness`; external monitors via `dxva2.dll` `GetPhysicalMonitorsFromHMONITOR` + `SetVCPFeature(h, 0x10, 100)` / `GetVCPFeatureAndVCPFeatureReply`. Same state machine as §3.6.
- **Extreme dim:** layered topmost window `WS_EX_LAYERED|WS_EX_TRANSPARENT|WS_EX_TOOLWINDOW|WS_EX_TOPMOST`, `SetLayeredWindowAttributes` alpha, excluded from capture with `SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)` (Win10 2004+).
- Cursor tinting is optional polish.
- Distribution: free under MIT through GitHub Releases, with no keys or activation. Installer: Inno Setup, per-user to `%LocalAppData%`, code-signed (OV/EV certificate to reduce SmartScreen warnings).
- Acceptance: same matrix as §8 plus Intel/AMD/NVIDIA GPUs, Win10 1903+ and Win11, one DDC/CI monitor, one that isn't.

---

## 12. Working agreements for Claude Code

- Run `swift scripts/gamma_spike.swift` on every new macOS build before trusting the gamma path; record the result in `docs/QA.md`.
- **There is no application backend, and adding one needs a new decision, not a commit.** No database, auth, serverless function or user-data service. GitHub Releases and the static Pages appcast handle distribution (§4.3). If a task seems to need a server, say so and stop.
- The README is the product page. Keep its claims aligned with `docs/QA.md`; publish the appcast from `docs/` through GitHub Pages, with release binaries in GitHub Releases (`docs/ARCHITECTURE.md` §4).
- Stay inside the cycle's "In" list. If something in "Out" looks necessary, stop and say so instead of building it.
- Before writing display code, write the test for the pure function it depends on.
- Every private-API call is isolated in one file, behind a protocol, with a graceful `.unsupported` path and a comment naming the framework path and symbol.
- Never delete the gamma-restore path to "simplify".
- Commit per milestone with a conventional message; open a PR with the demo GIF and the QA rows you ran.
- Ask before adding any dependency, any network call, or any permission prompt.
- When a string is needed, add it to the catalog in all three languages first.
- Preserve authorship and third-party attribution. Do not copy proprietary text, icons or code; keep engineering references factual and relevant.

---

## Appendix B — Research references (verify each DOI before citing publicly)
Lockley et al. 2003 (J Clin Endocrinol Metab 88(9):4502-5) · Brainard et al. 2001 (J Neurosci 21:6405-6412) · Chang et al. 2015 (PNAS 112(4):1232-7) · Gooley et al. 2011 (J Clin Endocrinol Metab 96(3):E463-E472) · Wahl et al. 2019 (J Biophotonics, PMC7065627) · Gupta et al. 2022 (Ophthalmol Ther, PMC9434525) · IEEE PAR1789 (2015) · Ionescu et al. 2021 (Journal of Information Display).
