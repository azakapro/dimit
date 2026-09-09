# CLAUDE.md — Dimit: blue-light + PWM-flicker utility for macOS, then Windows

> **Build order is MVP-first (decided 2026-09-09).** Work goes in cycles C0…C9 defined in `docs/PLAN.md` §2, one PR each. The MVP (C0–C3, tag v0.1) is the display engine, PWM-Safe, presets and three languages, shared as a zip with friends. **Licensing (§4.1–4.3) starts at C7, payments and the website (§4.4, §6) at C8.** Until then `License/`, `server/` and `site/` do not exist and nothing in the app touches the network. Every cycle starts with the prompt at the top of `docs/PLAN.md` §2, and every PR must satisfy `docs/PLAN.md` §3 and `.github/pull_request_template.md`.
>
> **Decisions locked on 2026-09-08** (full list in `docs/PLAN.md` → Decisions): product name **Dimit**, bundle ID `app.dimit.mac`, key prefix `DIMT-`, primary domain **dimit.uz** (dimit.app later), **Uzbekistan launch first** (Payme + Click in 1.0, Lemon Squeezy at the global launch, M7), 7-day trial without card, seller is the owner's Uzbek LLC, one developer working part-time with Claude Code + Codex on parallel tracks.
>
> **Dev machine facts** (2026-09-08): MacBook Pro 16" M1 Pro (built-in XDR), macOS **27.0 beta** (26A5416b), no Xcode installed yet, one external monitor available at home, auto-brightness ON. There is no macOS 13–26 machine; older-OS QA comes from beta testers or a macOS 26 install on an external SSD. **Run `swift scripts/gamma_spike.swift` before writing any display code** (see §3.3 and M0).

---

## 0. One-paragraph brief

Build a native macOS menu-bar app that (1) warms the screen from 6500K down to a pure-red "0K" by rewriting the display gamma tables, (2) dims the screen in software, (3) offers a **PWM-Safe mode** that pins the hardware backlight at 100% and does all dimming in software so LED backlights never flicker, (4) works on every connected display, (5) ships in **Uzbek (Latin), Russian and English**, (6) is sold as a **one-time license for 3 computers** through Payme and Click (Uzbekistan, in 1.0) and later Lemon Squeezy (worldwide cards, global launch), all issuing keys from **our own** license server. No accounts, no analytics, no telemetry. Phase 2 is a Windows port with feature parity. The reference product is Tap Zap (tapzap.app, $39, one person, $18.8k in 7 weeks); the reference competitor is CircadianShield ($47, adds solar scheduling). We match Tap Zap's core, add scheduling and external-monitor PWM control on Mac, and localize.

---

## 1. Non-negotiable product rules

1. **Two sliders, three presets, one button.** Warmth (6500K→0K), Brightness (100%→10%), presets DAY/EVENING/NIGHT, a big ON/OFF ("ZAP") button. Anything else lives behind a Settings gear.
2. **Zero network traffic** except license activation/validation. No crash reporters, no analytics SDKs, no auto-update pings without user opt-in (Sparkle update check is opt-in and explained).
3. **No accounts.** License key in, done. Key stored in Keychain.
4. **Screenshots, screen recordings and screen-shares must not be tinted.** Gamma tables satisfy this; the Extreme-Dim overlay window must set `sharingType = .none`.
5. **Never require Accessibility, Screen Recording or admin.** (We will use private frameworks via `dlopen`; that is allowed outside the App Store. We are **not** an App Store app.)
6. **Every user-visible string goes through the String Catalog** (`Localizable.xcstrings`) with `en`, `uz`, `ru`. No hard-coded English. Uzbek is **Latin script**.
7. **No medical claims** in any language. Allowed: "removes blue light", "stops backlight flicker", "may help with eye strain (see studies)". Not allowed: "cures", "treats", "prevents disease".
8. **Fail safe.** On quit, crash, sleep, display reconfiguration or license failure, the display must return to (or be restorable to) normal colours. Gamma is restored with `CGDisplayRestoreColorSyncSettings()`; overlay windows are torn down.

---

## 2. Stack and repo layout

- **Language/UI:** Swift 5.10+, AppKit for the menu-bar item + `NSPopover`, SwiftUI for the popover content and Settings window. Minimum **macOS 13 Ventura** (Tap Zap supports 12, but 12 has sticky-slider bugs per its own help page; don't pay for it). Universal binary (arm64 + x86_64).
- **Identity:** product name `Dimit`, bundle ID `app.dimit.mac`, both as constants in `Config.swift` (`PRODUCT_NAME`, `PRODUCT_BUNDLE_ID`). Menu-bar name "Dimit".
- **Build:** Xcode 26 or newer (whatever runs on the dev machine's macOS 27 beta; download from developer.apple.com, not the App Store). Swift 6 toolchain with **Swift 5 language mode** to avoid strict-concurrency churn in AppKit code. Swift Package Manager only (no CocoaPods). Dependencies allowed: `sparkle-project/Sparkle` (updates), `sindresorhus/KeyboardShortcuts` (global hotkey), `sindresorhus/LaunchAtLogin-Modern` or `SMAppService` directly. Nothing else without asking.
- **License server:** Cloudflare Worker (TypeScript) + D1 (SQLite) + KV for rate limiting. Repo folder `server/`.
- **Website:** Astro static site in `site/`, three locales `/`, `/uz/`, `/ru/`, deployed to Cloudflare Pages.
- **Windows (phase 2):** C++20 / Win32, no frameworks, folder `windows/`. Spec in §11.

```
dimit/
  CLAUDE.md
  Dimit.xcodeproj / Package.swift
  Dimit/
    App/            DimitApp.swift, AppDelegate.swift, Config.swift
    Display/        DisplayManager.swift, GammaController.swift, BrightnessController.swift,
                    DDCController.swift, OverlayDimmer.swift, WarmthCurve.swift, DisplayModels.swift
    Features/       PresetStore.swift, ScheduleEngine.swift, PWMSafeCoordinator.swift, HotkeyManager.swift
    License/        LicenseClient.swift, LicenseStore.swift (Keychain), DeviceID.swift, LicenseState.swift
    UI/             MenuBarController.swift, PopoverView.swift, SettingsView.swift, OnboardingView.swift,
                    LicenseView.swift, Components/
    Resources/      Localizable.xcstrings, Assets.xcassets, Studies.md
    Support/        Logger.swift, DiagnosticsBundle.swift, Persistence.swift
  DimitTests/        WarmthCurveTests, LicenseStateTests, ScheduleEngineTests, GammaMathTests
  server/           worker/src/index.ts, schema.sql, wrangler.toml, README.md
  site/             Astro project (en/uz/ru)
  scripts/          build_dmg.sh, notarize.sh, make_appcast.sh
  docs/             ARCHITECTURE.md, RELEASE.md, SUPPORT.md
```

---

## 3. Display engine — the core

### 3.1 Enumerate displays
`CGGetActiveDisplayList` → for each `CGDirectDisplayID` build `DisplayInfo { id, uuid (CGDisplayCreateUUIDFromDisplayID), name (from NSScreen.localizedName), isBuiltin (CGDisplayIsBuiltin), isAppleDisplay (vendor 0x610 via IOKit/`CGDisplayVendorNumber`), supportsDDC }`. Register `CGDisplayRegisterReconfigurationCallback` to re-enumerate and **re-apply** on any change (plug/unplug, sleep/wake, resolution change). Also observe `NSWorkspace.didWakeNotification` and `screensDidWakeNotification` and re-apply after a 1.0 s delay (WindowServer resets gamma on wake — Tap Zap documents this exact bug).

### 3.2 Warmth → RGB multipliers (`WarmthCurve.swift`)
- Input: Kelvin `k ∈ [0, 6500]`. Output: `(r, g, b) ∈ [0,1]³`, with `(1,1,1)` at 6500K.
- For `k ≥ 1000`: use the Tanner Helland / Krystek CCT→RGB approximation (white point 6500K normalized to 1.0). Unit-test known points: 6500K≈(1,1,1); 2700K≈(1, 0.72–0.78, 0.45–0.55); 1900K≈(1, 0.55–0.62, 0.20–0.30).
- For `k < 1000` ("below the physics"): linearly interpolate from the 1000K value down to **(1, 0, 0) at k=0**. This is the "0K = pure red" behaviour. Green must reach exactly 0 and blue exactly 0 at k=0.
- Optional "chromaticity mode" (Tap Zap v2.22): compute in CIE xy and convert; ship the simple curve first, keep the function signature stable.

### 3.3 Gamma tables (`GammaController.swift`)
- Read original tables once per display at first touch with `CGGetDisplayTransferByTable` (capacity via `CGDisplayGammaTableCapacity`) and cache them as the restore baseline.
- Build tables: for i in 0..<n: `x = i/(n-1)`; `r[i] = orig_r[x] * mulR * dim`, same for g, b, where `dim ∈ [dimFloor, 1]` is the software brightness. Apply with `CGSetDisplayTransferByTable(displayID, n, r, g, b)`.
- Apply to all displays unless `perDisplay` override exists (Settings → per-display sliders, off by default).
- Restore: `CGDisplayRestoreColorSyncSettings()` on OFF, on quit (`applicationWillTerminate`), and from a `atexit`/signal handler for crashes (SIGTERM/SIGINT; do not try to handle SIGSEGV elaborately).
- **Verification step (mandatory, this is the Tahoe workaround):** after applying, read back with `CGGetDisplayTransferByTable`. Read-back succeeding does **not** prove the screen changed (the Tahoe bug returns success and stores the table but the display ignores it), and we cannot sample pixels without the Screen Recording permission. So: (a) on macOS ≥ 26, and (b) if auto-brightness is detectably enabled — **the `com.apple.BezelServices dAuto` key does not exist on macOS 27** (checked 2026-09-08); spend at most 2 hours in M2 looking for a replacement (candidates: `com.apple.CoreBrightness` prefs, `CBClient` in the private CoreBrightness framework, keys under `AppleARMBacklight` in `ioreg`), and if nothing reliable is found, skip detection and show the banner unconditionally on macOS ≥ 26 the first time the filter is turned ON, dismissable forever — show a one-time banner "Automatic brightness can block colour changes on macOS 26 — turn it off in System Settings → Displays" with a button that opens `x-apple.systempreferences:com.apple.Displays-Settings.extension`. And (c) provide **Fallback mode** (Settings toggle, auto-suggested when the user reports "no tint"): tint via the overlay described in 3.5 instead of gamma. Fallback mode is visible in recordings — say so in the UI.
- Known Apple bugs to reference in code comments: FB18559786, FB19136488, FB22273730 (developer.apple.com/forums/thread/795074 and /819331).

### 3.4 Hardware brightness (`BrightnessController.swift`)
- **Apple displays (built-in, Studio Display, Pro Display XDR):** load `/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices` with `dlopen`, `dlsym` → `DisplayServicesGetBrightness(CGDirectDisplayID, float*) -> Int32` and `DisplayServicesSetBrightness(CGDirectDisplayID, float) -> Int32`. Fallback: `CoreDisplay_Display_SetUserBrightness` / `CoreDisplay_Display_GetUserBrightness` from `CoreDisplay.framework`. Wrap in a protocol `BrightnessBackend` with `canControl(display)`, `get`, `set`, and return `.unsupported` cleanly when symbols are missing (future macOS may remove them).
- **Third-party external displays:** DDC/CI VCP code `0x10` (brightness) via IOKit. On Apple Silicon use the IOAVService path (`IOAVServiceCreateWithService`, `IOAVServiceWriteI2C`/`ReadI2C`, as used by `m1ddc`/MonitorControl/OpenDisplay); on Intel use `IOFramebuffer` I2C (`IOI2CSendRequest`). Implement in `DDCController.swift` in M4, tested on the one external monitor available (record vendor/model/connection in `docs/QA.md`). Ships in 1.0 as an **Experimental** toggle in Settings (`Config.ddcEnabled`, default OFF); promoted to default ON in 1.1 after a second monitor and beta feedback. This is the feature Tap Zap lacks on Mac.
- **Verification without private APIs:** on Apple Silicon the built-in backlight exposes `IODisplayParameters.brightness {min 0, max 65536, value}` under `AppleARMBacklight` in the IORegistry (observed on the dev machine). Use it as a read-only cross-check for the PWM pin when the DisplayServices read-back is unavailable.
- Never call set-brightness more than 4×/second (some panels wear or lag).

### 3.5 Extreme dim overlay (`OverlayDimmer.swift`)
- Gamma dimming floor is 30% (below that, banding and lost text). For 10–30% add a borderless `NSWindow` per screen: `level = .screenSaver + 1` (above everything incl. menu bar), `ignoresMouseEvents = true`, `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]`, `sharingType = .none` (excluded from screen capture), black with alpha `1 - (brightness/0.30)`. Also used as **Fallback tint mode** (red-tinted overlay, alpha by warmth) when gamma is broken.
- Must not appear in Mission Control thumbnails as a separate window in a confusing way (`.stationary` handles it); must survive Spaces switches; must be recreated on display reconfiguration.

### 3.6 PWM-Safe mode (`PWMSafeCoordinator.swift`)
State machine per display: `off → pinning → pinned(verified) | unsupported | wontHold`.
- On enable: for each display with a `BrightnessBackend`: remember current hardware brightness, set 1.0, wait 300 ms, read back; if ≥ 0.99 → `pinned`; else retry twice then `wontHold` (UI: "DISPLAY WON'T HOLD 100%"). Displays without a backend → `unsupported` (UI: "PWM mode needs an Apple display or a DDC/CI monitor").
- While pinned: map the Brightness slider entirely to gamma `dim` (+ overlay below 30%). Re-pin on wake, on reconfiguration, and whenever the read-back drifts (poll every 5 s while pinned; stop polling when off). Detect user pressing the hardware brightness keys (read-back drops) → show "PWM-Safe re-pinned brightness to 100%; use the in-app slider" once per session.
- On disable: restore remembered hardware brightness.
- Auto-brightness: we cannot disable it without root; we detect it (best effort) and show the banner from 3.3.
- Battery note in UI: "Backlight stays at 100% — slightly more battery use."

### 3.7 Presets, state, persistence
- Presets: `DAY 4000K/100%`, `EVENING 2700K/80%`, `NIGHT 0K/40%` (Tap Zap: 4000/2700/0K). User-editable; "reset to defaults".
- `AppState` (single `@Observable` class — **C1 uses `ObservableObject` + `@Published` instead**, disclosed in a code comment: `@Observable` needs macOS 14+ and this file fixes the deployment target at 13; mechanical swap if that ever changes): `isOn, warmthK, brightness, pwmSafe, activePreset, perDisplayOverrides, schedule, hotkeys, launchAtLogin, updateChecks, locale`. Persist in `UserDefaults.standard`, debounced 250 ms — **not** `UserDefaults(suiteName: PRODUCT_BUNDLE_ID)` as an earlier draft of this file said: passing an app's own bundle ID as a suite name is not a real app-group suite (Foundation logs "does not make sense and will not work"), and a real one needs an App Groups entitlement we don't have per §1.5. Apply pipeline is a single pure function `render(state, displays) -> [DisplayCommand]` so it is unit-testable.

### 3.8 Scheduling (`ScheduleEngine.swift`) — the feature Tap Zap doesn't have
- Modes: **Manual** (default), **Sunset→Sunrise** (uses `CoreLocation` *only if user grants* — otherwise fall back to a user-chosen city from a bundled list with lat/lon: Tashkent, Samarkand, Bukhara, Namangan, Andijan, Fergana, Nukus, Moscow, Almaty, Bishkek, Dushanbe, Istanbul, London, New York… plus manual lat/lon), **Fixed times**.
- Transition: linear ramp over a user-set duration (default 20 min) from DAY preset to EVENING at sunset and to NIGHT at "bedtime" (default 22:30 local). Compute sunrise/sunset locally with the NOAA solar algorithm (unit tests vs known values for Tashkent on 2026-09-08). No network.

### 3.9 Hotkeys, login item, menu bar
- Global hotkeys via `KeyboardShortcuts`: toggle ON/OFF (default ⌃⌥⌘Z), cycle presets, warmth ±, brightness ±.
- Menu bar icon: outline when OFF, filled when ON, small dot when PWM pinned. Left-click opens the popover; right-click shows a context menu (presets, toggle, settings, quit).
- Launch at login via `SMAppService.mainApp` (macOS 13+).

---

## 4. Licensing and payments

### 4.1 Key format and crypto
- Key: `DIMT-XXXX-XXXX-XXXX-XXXX` (Crockford base32, 20 chars payload). Generated by the server as a random ID; **the server is the source of truth**, keys are not self-verifying (simpler, and allows refunds to revoke).
- Device ID: SHA-256 of (`IOPlatformUUID` + user home path) → hex; store in Keychain so it is stable across reinstalls. Never send hardware serials.

### 4.2 Server API (Cloudflare Worker, `server/`)
```
POST /v1/orders      { email, locale:"uz"|"ru"|"en", provider:"payme"|"click", telegram? }
   → 201 { orderId, checkoutUrl }              (site /buy page calls this, then redirects)
GET  /v1/orders/:id  → 200 { status:"pending"|"paid"|"cancelled", key? }   (/download page polls, 5 s, max 15 min)
POST /v1/activate    { key, deviceId, deviceName, platform:"mac", appVersion }
   → 200 { status:"active", seatsUsed, seatsTotal:3, validUntil (now+90d), instanceId }
   → 409 { error:"no_seats", devices:[{instanceId, deviceName, activatedAt}] }
   → 404 { error:"invalid_key" } · 410 { error:"revoked" }
POST /v1/validate    { key, instanceId }         → 200 { status, validUntil } | 410 revoked
POST /v1/deactivate  { key, instanceId }         → 200
POST /webhooks/lemonsqueezy   (HMAC-signed, M7)  → create license row on order_created; revoke on refund
POST /webhooks/payme          (Payme Merchant API JSON-RPC: CheckPerformTransaction, CreateTransaction,
                               PerformTransaction, CancelTransaction, CheckTransaction, GetStatement)
POST /webhooks/click          (Click prepare/complete)
GET  /r/:handle              → affiliate redirect (sets 60-day cookie, forwards to checkout with ?aff=)
```
- D1 tables: `licenses(key PK, email, source enum(ls,payme,click,manual), order_ref, seats INT default 3, status enum(active,revoked), created_at)`, `activations(instance_id PK, key FK, device_id, device_name, platform, activated_at, last_seen)`, `orders(id PK, email, locale, provider enum(payme,click,ls), amount_tiyin INT, status enum(pending,paid,cancelled), license_key FK null, created_at, paid_at)`, `payme_transactions(id PK — Payme's transaction id, order_id FK, state INT, create_time INT, perform_time INT, cancel_time INT, reason INT)`, `click_transactions(click_trans_id PK, order_id FK, prepare_id INT, status, created_at)`, `affiliates(handle PK, payout_method, rate default 0.25)` (M7), `referrals(order_ref, handle, amount, created_at)` (M7). Full schema and the payment sequences are in `docs/ARCHITECTURE.md`.
- Rate limit per IP and per key (KV). Log nothing but key-hash + timestamps.
- Email delivery of the key: Resend (or Cloudflare Email Workers) with EN/UZ/RU templates chosen by the checkout locale.

### 4.3 Client behaviour (`LicenseClient.swift`, `LicenseState.swift`)
- States: `unlicensed → trial(daysLeft) → active(validUntil) → grace(offlineSince) → expiredNeedsValidation → revoked`.
- **Trial:** 7 days full-featured, then the filter still works but the app shows a persistent "Trial ended" bar and disables PWM-Safe and scheduling. (Tap Zap has no trial; CircadianShield has 7 days with card. We do 7 days without card.)
- Re-validate every 30 days silently; if offline, 14-day grace (Tap Zap: 90 days/7 days — we validate more often but forgive longer). Store `validUntil` in Keychain with the key.
- Deactivate from Settings ("This Mac uses 1 of 3 seats · Manage").
- All license errors are localized and actionable ("No seats left — deactivate another Mac or contact support").

### 4.4 Checkout flows
- **Uzbekistan (1.0):** Payme and Click checkout from `/uz/buy` and `/ru/buy`. Buyer enters email (optional Telegram handle) → site calls `POST /v1/orders` → redirect to the Payme or Click checkout URL → provider calls our webhook → server marks the order paid, mints the key, emails it (Resend, UZ/RU template) and the `/download?order=…` page shows it. Price in UZS lives in exactly two places that must match: `server/src/config.ts` and `site/src/config.ts`. Starting hypothesis 199 000 UZS, to be validated (see `docs/PLAN.md` → Pricing).
- **International (M7, after 1.0):** Lemon Squeezy product "Dimit Personal (3 Macs)" at `$39`. LS is used **only for payment + tax**; on `order_created` our server mints the same key format and emails it (do not use LS license keys, so all customers get identical keys).
- **Teams:** 5+ seats → mailto/Telegram; server has an admin script `server/scripts/mint.ts --seats 10 --email …`.
- Refund policy: 30 days, no questions. Refund webhook → `status=revoked` → app shows "License refunded" on next validation and returns the screen to normal.

---

## 5. Localization (EN / UZ / RU)

- `Localizable.xcstrings` with the three locales; **Uzbek locale code `uz`** (Latin is the default for `uz` on Apple platforms; do not use `uz-Cyrl`). Russian `ru`. Plural rules for days/seats.
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
| banner.autobrightness | Automatic brightness can block colour changes on macOS 26. Turn it off in System Settings → Displays. | Avtomatik yorqinlik macOS 26 da rang o'zgarishini bloklashi mumkin. Tizim sozlamalari → Displeylar bo'limida o'chiring. | Автояркость может блокировать изменение цвета в macOS 26. Отключите её в Системных настройках → Дисплеи. |
| banner.open_settings | Open Displays settings | Displey sozlamalarini ochish | Открыть настройки дисплеев |
| banner.dismiss *(added C3, uz/ru need human review)* | Dismiss | Dismiss — TODO(i18n) | Dismiss — TODO(i18n) |
| fallback.title | Fallback mode | Zaxira rejim | Резервный режим |
| fallback.help | Tints with an overlay instead of colour tables. Screenshots will look tinted in this mode. | Rang jadvallari o'rniga qatlam bilan bo'yaydi. Bu rejimda skrinshotlar ham rangli chiqadi. | Окрашивает экран слоем вместо цветовых таблиц. В этом режиме скриншоты тоже будут окрашены. |
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
| license.title | License | Litsenziya | Лицензия |
| license.enter | Enter license key | Litsenziya kalitini kiriting | Введите лицензионный ключ |
| license.activate | Activate | Faollashtirish | Активировать |
| license.seats | This Mac uses %d of %d seats | Bu Mac %d / %d o'rindan foydalanmoqda | Этот Mac занимает %d из %d мест |
| license.manage | Manage devices | Qurilmalarni boshqarish | Управление устройствами |
| license.deactivate | Deactivate this Mac | Bu Mac'ni o'chirish | Отвязать этот Mac |
| license.trial_days | Trial: %d days left | Sinov: %d kun qoldi | Пробный период: осталось %d дн. |
| license.trial_over | Trial ended — buy a license to keep PWM‑Safe and scheduling. | Sinov tugadi — PWM‑xavfsiz rejim va jadval uchun litsenziya sotib oling. | Пробный период закончился — купите лицензию, чтобы сохранить режим без мерцания и расписание. |
| license.buy | Buy — one payment, 3 Macs | Sotib olish — bir marta to'lov, 3 ta Mac | Купить — разовый платёж, 3 Mac |
| license.invalid | This key is not valid. | Bu kalit yaroqsiz. | Этот ключ недействителен. |
| license.no_seats | No seats left. Deactivate another Mac or contact support. | Bo'sh o'rin yo'q. Boshqa Mac'ni o'chiring yoki yordamga yozing. | Свободных мест нет. Отвяжите другой Mac или напишите в поддержку. |
| license.revoked | This license was refunded or revoked. | Bu litsenziya qaytarilgan yoki bekor qilingan. | Лицензия возвращена или отозвана. |
| license.offline | Can't reach the license server. Works offline for %d more days. | Litsenziya serveriga ulanib bo'lmadi. Yana %d kun oflayn ishlaydi. | Нет связи с сервером лицензий. Работает офлайн ещё %d дн. |
| onboarding.1.title | Block blue light. Stop the flicker. | Ko'k nurni to'sing. Miltillashni to'xtating. | Уберите синий свет. Остановите мерцание. |
| onboarding.1.body | Two sliders, three presets, one button. | Ikki slayder, uch rejim, bitta tugma. | Два ползунка, три режима, одна кнопка. |
| onboarding.2.title | Your screenshots stay normal | Skrinshotlar oddiy qoladi | Скриншоты остаются обычными |
| onboarding.3.title | No account. No tracking. | Akkaunt yo'q. Kuzatuv yo'q. | Без аккаунта. Без слежки. |
| menu.quit | Quit | Chiqish | Выйти |
| menu.settings | Settings… | Sozlamalar… | Настройки… |
| menu.restore_colours *(added C2)* | Restore Colours | Restore Colours — TODO(i18n), needs a real uz translation | Restore Colours — TODO(i18n), needs a real ru translation |
| error.gamma_failed | Couldn't change display colours. Try Fallback mode in Settings. | Displey ranglarini o'zgartirib bo'lmadi. Sozlamalarda Zaxira rejimni sinab ko'ring. | Не удалось изменить цвета дисплея. Попробуйте Резервный режим в Настройках. |
| onboarding.2.body *(added C4)* | Screenshots, recordings and calls keep their normal colours. | TODO(i18n) | TODO(i18n) |
| onboarding.3.body *(added C4)* | No account, no analytics — nothing is sent anywhere except a future license check. | TODO(i18n) | TODO(i18n) |
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

(Claude Code: when adding a string, add all three languages; if unsure of Uzbek/Russian, add the English and mark `// TODO(i18n)` so a human translator sees it. Do not machine-translate silently. In the catalog, TODO(i18n) is represented as the English value with `state: needs_review` for uz/ru — Xcode's String Catalog editor flags those for a translator.)

---

## 6. Website (`site/`, Astro)

Pages per locale: home, /buy, /faq, /help, /science, /changelog, /affiliates, /terms, /privacy, /refund, /download (post-purchase). Copy structure mirrors tapzap.app but must be original text. Home = headline, 40-second demo video, the "vs" table (Night Shift ~2500K · f.lux ~1900K · Color Filters · us 0K + PWM), pricing card, FAQ accordion, studies list. Buy page shows **two checkouts**: card (Lemon Squeezy overlay) and Payme/Click (UZS). Footer must show a legal entity name and contact email (Tap Zap doesn't — a trust advantage). No analytics; Cloudflare Web Analytics only if cookieless.

---

## 7. Signing, notarization, updates, distribution

- Developer ID Application certificate; hardened runtime ON; entitlements: none special (no sandbox). `scripts/notarize.sh` runs `xcrun notarytool submit … --wait` then `stapler`.
- DMG via `create-dmg` with background + Applications symlink. Also a `.zip` for Sparkle.
- Sparkle 2 with EdDSA keys; appcast hosted on the site; update check **opt-in** in onboarding step 3 (default off to honour "zero network").
- Version scheme `MAJOR.MINOR` starting at `1.0`; build number = CI run.
- Diagnostics bundle (`DiagnosticsBundle.swift`): macOS version, hardware model, displays (name, builtin, vendor, DDC support, brightness backend), app version, last 200 log lines, license **state only** (never the key). Copied to clipboard as text.

---

## 8. Quality bar / acceptance tests (must pass before each milestone is "done")

- Unit: `WarmthCurve` known points; 0K yields (1,0,0); gamma tables monotonic and clamped; `ScheduleEngine` sunset for Tashkent 2026-09-08 within ±3 min of NOAA; `LicenseState` transitions incl. offline grace; `render()` idempotent.
- Manual matrix (document results in `docs/QA.md`): MacBook Air/Pro built-in; one external monitor over USB-C; one over HDMI; clamshell mode; sleep/wake; unplug while ON; fullscreen video (Safari/YouTube, HDR clip); screenshot ⌘⇧4 while at 0K is **not** red; QuickTime screen recording is not red; Zoom/Google Meet share is not red; Fallback mode screenshot **is** red (expected); quit → colours restore; `kill -9` → colours restore on relaunch ("Restore colours" button in onboarding for safety); macOS 13, 14, 15, 26 (Tahoe) with auto-brightness on and off.
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
| C3 | **v0.1 MVP** | Brightness backends, `PWMSafeCoordinator`, overlay for <30%, Fallback mode, auto-brightness banner, icon states | Opus 5 |
| C4 | v0.2 | Settings window, hotkeys, login item, onboarding, diagnostics, VoiceOver | Sonnet 5 |
| C5 | v0.3 | `ScheduleEngine`, DDC/CI experimental | Sonnet 5 / Opus 5 |
| C6 | v0.4 | Release scripts, DMG, 20 testers, QA matrix, fixes | Sonnet 5 |
| C7 | **v1.0** | License server + client, trial, keys minted by hand and sold via Telegram, Sparkle opt-in | Opus 5 |
| C8 | v1.1 | Payme + Click, Astro site | Opus 5 / Sonnet 5 |
| C9 | v1.2 | Lemon Squeezy, dimit.app, affiliates | Sonnet 5 |
| Phase 2 | v2 | Windows (§11) | — |

The original milestone list (M0–M7) is kept below only because §3–§7 reference it by name; M0–M2 ≈ C1–C3, M3 ≈ C7–C8, M4 ≈ C5, M5 ≈ C6 + C8, M6 ≈ C6, M7 ≈ C9.

- **M0 — Skeleton + gamma spike (week 0, Sep 9–14):** Xcode installed; `swift scripts/gamma_spike.swift` run with auto-brightness ON and OFF, results in `docs/QA.md`; Xcode project, menu-bar item, popover with two sliders/three presets/one button bound to `AppState`, String Catalog with the §5.1 table, unit-test target, `scripts/`. The app itself does not touch the display yet. *Model: Sonnet 5.*
- **M1 — Gamma warmth + software dim (week 1, Sep 15–21):** `DisplayManager`, `WarmthCurve`, `GammaController`, restore-on-quit/crash, multi-display, wake/reconfigure re-apply. Acceptance: 0K red on all displays; screenshot not red. *Model: Opus 5.*
- **M2 — PWM-Safe on Apple displays (week 2, Sep 22–28):** `BrightnessController` (DisplayServices + CoreDisplay fallback + IORegistry read-only cross-check), `PWMSafeCoordinator` state machine, overlay dimmer for <30%, auto-brightness banner (see §3.3 for the detection caveat), Fallback mode. Acceptance: pinned/verified states shown correctly; brightness keys re-pin; battery note. *Model: Opus 5.*
- **M3 — License server + client + Payme/Click (week 3, Sep 29–Oct 5):** Cloudflare Worker + D1 + KV; `/v1/orders`, activate/validate/deactivate; Payme Merchant API JSON-RPC (all six methods) and Click prepare/complete against the sandboxes; Keychain, trial, localized error states; key email via Resend (UZ/RU/EN). The server can start in week 1 on the Codex track from `docs/ARCHITECTURE.md` → Server. *Model: Opus 5 for the payment handlers and the client state machine, Sonnet 5 for scaffolding.*
- **M4 — Scheduling, hotkeys, login item, DDC experimental (week 4, Oct 6–12):** `ScheduleEngine` with city list + optional CoreLocation, transitions; `KeyboardShortcuts`; `SMAppService`; `DDCController` behind `Config.ddcEnabled`, tested on the home monitor. *Model: Sonnet 5; Opus 5 for DDC.*
- **M5 — Site, signing, updates (week 5, Oct 13–19):** Astro site with `uz` as default locale, `ru`, `en`; `/uz/buy` and `/ru/buy` with both checkouts; Payme/Click switched to production; notarized DMG under the LLC's Developer ID; Sparkle appcast (opt-in). *Model: Sonnet 5.*
- **M6 — Beta and 1.0 (weeks 6–7, Oct 20–Nov 1):** 20 testers via Telegram, `docs/QA.md` matrix on every macOS version the testers have (target 13/14/15/26/27), fix list, `1.0` tag, Uzbekistan launch on **Mon 2026-11-02**. *Model: Opus 5 for display bugs, Sonnet 5 otherwise.*
- **M7 — Global launch (2 weeks after 1.0):** Lemon Squeezy webhook, `/en` copy polish, dimit.app domain, affiliates (`/r/:handle`), r/ledstrain and PWM communities.
- **Phase 2 — Windows (§11), after M7.**

---

## 10. Non-goals for 1.0
Lemon Squeezy / USD checkout (M7) · affiliates (M7) · per-display overrides (1.1) · chromaticity warmth mode (1.1) · Telegram sales bot (1.1) · per-app exclusions · iOS/Android · Linux (watch Tap Zap: they said Linux is "coming out soon" on 2026-09-06) · App Store distribution (impossible with gamma/private APIs) · subscriptions · accounts · cloud sync · analytics · Philips Hue.

---

## 11. Phase 2 — Windows port (spec only; do not start before 1.0)

- C++20, Win32, no frameworks (Tap Zap: "Native C++ rewrite, zero dependencies"). Tray icon + a single WS_POPUP window drawn with Direct2D; same two sliders/three presets/one button; i18n via resource string tables (en/uz/ru) or a JSON bundle.
- **Colour, primary path:** Magnification API — `MagInitialize()`, `MagSetFullscreenColorEffect(MAGCOLOREFFECT*)` with a 5×5 matrix `[r,0,0,0,0; 0,g,0,0,0; 0,0,b,0,0; 0,0,0,1,0; 0,0,0,0,1]` scaled by `dim`. Requires the process to be **DPI-aware** and works at the compositor, so screenshots via PrintScreen are usually untinted; verify and document. Known failures: some DRM video (Netflix) and exclusive-fullscreen games → **Legacy mode**.
- **Colour, legacy path:** `SetDeviceGammaRamp(hdc, WORD ramp[3][256])` per monitor DC (`CreateDC("DISPLAY", monitorName…)`). Windows rejects strong ramps unless `HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ICM\GdiIcmGammaRange` (DWORD) = `256`; implement the "COLORS BLOCKED BY WINDOWS. CLICK TO FIX" bar that runs an elevated helper (UAC prompt) to set that value and asks for restart. Same trick f.lux uses; safe and reversible (document it).
- **Brightness pin:** laptop panels via WMI `root\WMI` → `WmiMonitorBrightnessMethods.WmiSetBrightness(timeout, 100)`, read back with `WmiMonitorBrightness.CurrentBrightness`; external monitors via `dxva2.dll` `GetPhysicalMonitorsFromHMONITOR` + `SetVCPFeature(h, 0x10, 100)` / `GetVCPFeatureAndVCPFeatureReply`. Same state machine as §3.6.
- **Extreme dim / fallback tint:** layered topmost window `WS_EX_LAYERED|WS_EX_TRANSPARENT|WS_EX_TOOLWINDOW|WS_EX_TOPMOST`, `SetLayeredWindowAttributes` alpha, excluded from capture with `SetWindowDisplayAffinity(hwnd, WDA_EXCLUDEFROMCAPTURE)` (Win10 2004+).
- Cursor tinting (Tap Zap v2.19) is optional polish.
- License: same server, `platform:"win"`, device ID = SHA-256(MachineGuid + username), key stored with DPAPI. Installer: Inno Setup, per-user to `%LocalAppData%`, code-signed (OV/EV certificate to reduce SmartScreen warnings).
- Acceptance: same matrix as §8 plus Intel/AMD/NVIDIA GPUs, Win10 1903+ and Win11, one DDC/CI monitor, one that isn't.

---

## 12. Working agreements for Claude Code

- Run `swift scripts/gamma_spike.swift` on every new macOS build before trusting the gamma path; record the result in `docs/QA.md`.
- `server/` and `site/` do not exist before C7/C8. When they do, they are built against the contract in `docs/ARCHITECTURE.md`; never change a route, payload or table without updating that file in the same commit.
- Stay inside the cycle's "In" list. If something in "Out" looks necessary, stop and say so instead of building it.
- Before writing display code, write the test for the pure function it depends on.
- Every private-API call is isolated in one file, behind a protocol, with a graceful `.unsupported` path and a comment naming the framework path and symbol.
- Never delete the gamma-restore path to "simplify".
- Commit per milestone with a conventional message; open a PR with the demo GIF and the QA rows you ran.
- Ask before adding any dependency, any network call, or any permission prompt.
- When a string is needed, add it to the catalog in all three languages first.
- Do not copy text, icons, or code from tapzap.app or circadianshield.com. Architecture and feature ideas are fair; their copy and assets are not.

---

## Appendix A — Reference facts about the reference product (for context, not to copy)
Tap Zap: $39 one-time, 3 devices, 30-day refund, Dodo Payments MoR, license re-validation ~90 days with 7-day offline grace, presets 4000K/2700K/0K, brightness floor 10% (30% with Extreme Dim), PWM-Safe via DisplayServices (Mac) / WMI + DDC/CI (Windows), Magnification API + Legacy gamma (Windows), no Accessibility permission, prefs in `com.antigravity.tapzap2.plist`, affiliate 25% / 60-day cookie / $50 min. Verified $18,781 all-time revenue on TrustMRR as of 2026-09-08. Competitor CircadianShield: $47, 2 computers, 7-day trial with card, solar scheduling with 11 phases, 1800K floor, "software dimming overlay" for PWM. Apple bug threads: developer.apple.com/forums/thread/795074, /819331.

## Appendix B — Studies to cite on the /science page (as cited by tapzap.app/science; verify each DOI before publishing)
Lockley et al. 2003 (J Clin Endocrinol Metab 88(9):4502-5) · Brainard et al. 2001 (J Neurosci 21:6405-6412) · Chang et al. 2015 (PNAS 112(4):1232-7) · Gooley et al. 2011 (J Clin Endocrinol Metab 96(3):E463-E472) · Wahl et al. 2019 (J Biophotonics, PMC7065627) · Gupta et al. 2022 (Ophthalmol Ther, PMC9434525) · IEEE PAR1789 (2015) · Ionescu et al. 2021 (Journal of Information Display).
