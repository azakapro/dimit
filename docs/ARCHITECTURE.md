# Dimit — Architecture

Companion to `CLAUDE.md` (product rules and API-level detail) and `docs/PLAN.md` (schedule). This file is the contract between the app track and the server/site track. Change it before changing code.

**MVP scope (2026-09-09):** cycles C0–C3 implement §1 (app box only), §2 in full, and §10–§11. §3 (schedule) is C5. §4 (license client) is C7. §5–§8 (server, orders, payments, site) are C7–C8; until then there is no network code in the app. §9 (release pipeline) is C6.

## 1. System context

```mermaid
flowchart LR
    subgraph Mac["Dimit.app (Swift, macOS 13+)"]
        UI[Menu bar + popover + settings] --> State[AppState]
        State --> Render["render(state, displays) → [DisplayCommand]"]
        Render --> Gamma[GammaController]
        Render --> Bright[BrightnessController]
        Render --> Overlay[OverlayDimmer]
        State --> Lic[LicenseClient]
    end
    Lic -- "HTTPS, only activate/validate/deactivate" --> API
    subgraph CF["Cloudflare (api.dimit.uz)"]
        API[Worker: license + orders + webhooks] --> D1[(D1 SQLite)]
        API --> KV[(KV rate limits)]
    end
    Site[Astro site dimit.uz\n/uz /ru /en] -- "POST /v1/orders\nGET /v1/orders/:id" --> API
    Payme[Payme Merchant API] -- "JSON-RPC callbacks" --> API
    Click[Click Shop API] -- "prepare / complete" --> API
    LS[Lemon Squeezy, M7] -- "order_created webhook" --> API
    API -- "key email" --> Resend
    Site -- "appcast.xml + .zip" --> Sparkle[Sparkle in app, opt-in]
```

Network policy: the app talks to exactly one host, `api.dimit.uz`, and only for license calls; Sparkle talks to `dimit.uz` only when the user opted in. Nothing else, ever.

## 2. App module map and layering

Dependencies point downwards only. A layer never imports a layer above it.

```
UI            MenuBarController, PopoverView, SettingsView, OnboardingView, LicenseView
              ↓ observes
State         AppState (@Observable), PresetStore, Persistence (UserDefaults, debounced)
              ↓ calls
Features      PWMSafeCoordinator, ScheduleEngine, HotkeyManager, LicenseClient/LicenseState
              ↓ calls
Display       DisplayManager, WarmthCurve (pure), Renderer (pure), GammaController,
              BrightnessController (protocol BrightnessBackend), OverlayDimmer, DDCController
              ↓ wraps
Backends      CoreGraphics gamma API · DisplayServices.framework (dlopen) · CoreDisplay.framework (dlopen)
              · IOKit (IORegistry read, IOAVService I2C for DDC) · AppKit windows for overlay
```

Rules that keep this testable:

- Everything under **Display** that does math is a pure function with unit tests: `WarmthCurve.rgb(kelvin:)`, `GammaMath.table(orig:mul:dim:)`, `Renderer.render(state:displays:)`.
- Every private-API call lives in exactly one file, behind a protocol, returning `.unsupported` when a symbol is missing. Files: `BrightnessController.swift` (DisplayServices, CoreDisplay), `DDCController.swift` (IOAVService), nothing else.
- `AppState` is the only mutable source of truth. UI mutates it; a single `apply()` pipeline reacts to it. No UI code calls a controller directly.

### 2.1 The apply pipeline

```swift
struct DisplayCommand: Equatable {
    let display: CGDirectDisplayID
    var gamma: GammaSpec?          // multipliers (r,g,b) and dim ∈ [0.30, 1]; nil = restore
    var overlayAlpha: Double       // 0 = no overlay window
    var overlayTint: OverlayTint   // .black (extreme dim) or .red(warmth) in Fallback mode
    var hardwareBrightness: Float? // 1.0 while PWM pinned; nil = leave alone
}

func render(_ s: AppState, _ displays: [DisplayInfo]) -> [DisplayCommand]
```

`render` is pure and idempotent. `Applier` diffs the new command list against the last applied one and calls controllers only for changed fields. That is what keeps idle CPU under 0.5% and slider latency under 50 ms: sliders change `AppState` at most every 16 ms, `render` is cheap, and `CGSetDisplayTransferByTable` is called once per changed display.

### 2.2 Display lifecycle events

| Event | Source | Action |
|---|---|---|
| Display added/removed/resolution change | `CGDisplayRegisterReconfigurationCallback` (flags contain `.beginConfiguration` → wait for the end flag) | re-enumerate, drop cached baselines for gone displays, read baselines for new ones, re-apply after 300 ms debounce |
| Wake from sleep | `NSWorkspace.didWakeNotification`, `screensDidWakeNotification` | re-apply after 1.0 s; PWM re-pin |
| App quit | `applicationWillTerminate` | restore gamma, close overlays, restore hardware brightness if pinned |
| SIGTERM / SIGINT | signal handlers installed at launch | `CGDisplayRestoreColorSyncSettings()` then exit |
| Crash (SIGSEGV etc.) | not handled | WindowServer keeps the last table; onboarding and Settings have a "Restore colours" button, and the app restores on next launch before doing anything else |
| License becomes `revoked` | `LicenseClient` | `isOn = false`, restore |

### 2.3 Warmth curve

`WarmthCurve.rgb(kelvin: Double) -> (r: Double, g: Double, b: Double)`

- `k ∈ [1000, 6500]`: Tanner Helland CCT approximation, normalised so 6500 K = (1, 1, 1).
- `k ∈ [0, 1000)`: linear interpolation from `rgb(1000)` to `(1, 0, 0)`. At 0: exactly `(1, 0, 0)`.
- Tests: the known points listed in CLAUDE.md §3.2, monotonic decrease of g and b as k falls, `rgb(0) == (1,0,0)` exactly.

### 2.4 Gamma tables

```
for i in 0..<n:
    x        = i / (n - 1)
    r[i]     = clamp(origR[i] * mulR * dim, 0, 1)   // same for g, b
```

- `origR/G/B` are read once per display at first touch (`CGGetDisplayTransferByTable`) and cached as the restore baseline keyed by display UUID, not by ID (IDs change across reconnects).
- `dim ∈ [0.30, 1.0]`. Below 0.30 the overlay takes over: `overlayAlpha = 1 - brightness / 0.30`, gamma dim stays at 0.30.
- After each set, read back and compare; a mismatch logs `gammaMismatch` and increments a counter shown in diagnostics. A match proves nothing on macOS 26+ (Apple bugs FB19136488, FB22273730), which is why Fallback mode exists and the auto-brightness banner is shown.

### 2.5 Brightness backends

```swift
protocol BrightnessBackend {
    var name: String { get }                 // for diagnostics
    func canControl(_ d: DisplayInfo) -> Bool
    func get(_ d: DisplayInfo) -> Float?     // 0...1
    func set(_ d: DisplayInfo, _ v: Float) -> BackendResult   // .ok | .unsupported | .failed(code)
}
```

Resolution order per display, first that `canControl` wins:

1. `DisplayServicesBackend` — `dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices")`, symbols `DisplayServicesGetBrightness`, `DisplayServicesSetBrightness`. Apple displays only.
2. `CoreDisplayBackend` — `CoreDisplay_Display_GetUserBrightness` / `SetUserBrightness`. Fallback for Apple displays.
3. `DDCBackend` (M4, experimental) — VCP 0x10 over `IOAVService` I2C on Apple Silicon, `IOI2CSendRequest` on Intel. Third-party monitors.
4. `IORegistryReadOnlyBackend` — reads `IODisplayParameters.brightness` under `AppleARMBacklight` (observed on the dev machine: min 0, max 65536). `set` returns `.unsupported`; used only to cross-check that a pin held when backend 1 or 2 cannot read back.

Rate limit: one `set` per display per 250 ms, coalesced.

### 2.6 PWM-Safe state machine (per display)

```mermaid
stateDiagram-v2
    [*] --> off
    off --> unsupported : enable, no backend canControl
    off --> pinning : enable, backend found\nremember current brightness
    pinning --> pinned : set 1.0, wait 300 ms, read-back ≥ 0.99
    pinning --> pinning : read-back < 0.99, retry (max 2)
    pinning --> wontHold : 3 failures
    pinned --> pinning : poll every 5 s shows < 0.99\n(user pressed brightness key → toast once per session)
    pinned --> pinning : wake / reconfiguration
    pinned --> off : disable → restore remembered brightness
    wontHold --> off : disable
    unsupported --> off : disable
```

While any display is `pinned`, the Brightness slider maps entirely to gamma `dim` plus the overlay. The 5 s poll runs only while at least one display is `pinned`; the timer is invalidated otherwise.

**As built in C3, with one disclosed simplification** (this file is the contract, so it says what the code does, not what an earlier draft intended): the `pinned → pinning : wake / reconfiguration` edge above is *not* a separate immediate hook. Wake and reconfiguration are caught by the same 5 s drift poll that catches a brightness-key press, so a re-pin can lag a wake by up to one poll interval. Gamma gets an immediate 1.0 s re-apply (§2.2) because a visibly wrong *colour* for a second is jarring; a backlight still at its pre-sleep level for a few more seconds is a much smaller cost than the extra wake-specific plumbing it would take to shave it. Revisit if beta testers actually notice it.

Two further C3 details worth pinning down here, both from code review rather than the original design:

- **Every retry is delayed**, including the ones whose failure is known synchronously (a `set()` that reports failure, or an unreadable initial brightness). CLAUDE.md §3.4's "never call set-brightness more than 4×/second" would otherwise be violated by three back-to-back `set()` calls in a single run-loop turn.
- **A display whose current brightness can't be read is not pinned at all.** There would be nothing to restore it to afterwards, and a backlight stuck at 100% with no way back is worse than no PWM-Safe.
- **Restoring the remembered brightness happens on quit too**, not just on toggling PWM-Safe off. The pin is real hardware state set through DisplayServices; it outlives the process.

### 2.7 Overlay windows

One `NSWindow` per screen, created lazily, keyed by display UUID. Properties from CLAUDE.md §3.5, plus:

- `sharingType = .none` set **before** `orderFront` (setting it afterwards is unreliable on some versions).
- Recreated, not moved, on reconfiguration. Frame equals `NSScreen.frame` including the notch area.
- Two uses: black with alpha for extreme dim, and red-tinted with alpha derived from warmth in Fallback mode. In Fallback mode gamma is left at baseline.

### 2.8 Persistence and secrets

| Data | Where | Key |
|---|---|---|
| `AppState` (everything user-visible) | `UserDefaults(suiteName: "app.dimit.mac")`, JSON blob, written 250 ms after last change | `state.v1` |
| Gamma baselines | memory only, never persisted (stale baselines would bake a tint in) | |
| License key, `instanceId`, `validUntil`, `lastValidated` | Keychain, service `app.dimit.mac.license` | one item, JSON |
| Device ID | Keychain, service `app.dimit.mac.device` | SHA-256(IOPlatformUUID + home path), hex |
| Trial start | Keychain (survives reinstall; UserDefaults would be trivially reset) | `trialStartedAt` |
| Logs | `~/Library/Logs/Dimit/dimit.log`, ring of 200 lines in memory for diagnostics | |

## 3. Scheduling engine

`ScheduleEngine` is a pure function over time plus a small driver:

```swift
struct SchedulePhase { let preset: PresetID; let start: Date; let rampMinutes: Int }
func phases(for day: Date, mode: ScheduleMode, location: Coordinate?, bedtime: TimeOfDay) -> [SchedulePhase]
func target(at now: Date, phases: [SchedulePhase]) -> (warmthK: Double, brightness: Double)
```

- Sunrise/sunset via the NOAA algorithm; tested against Tashkent 2026-09-08 within ±3 min.
- Location from CoreLocation only if the user pressed "Use my location"; otherwise the bundled city list; otherwise manual lat/lon.
- The driver wakes once per minute (a `Timer` tolerance of 30 s keeps energy impact nil) and during a ramp every 10 s, sets `AppState.warmthK/brightness` with `source = .schedule` so a manual slider move pauses the schedule until the next phase boundary.

**As built in C5** (this file is the contract, so it records what shipped where it differs from or extends the sketch above):

- **Three phases, not the two CLAUDE.md §3.8 spells out.** Its prose only names DAY→EVENING at sunset and EVENING→NIGHT at bedtime; a third, back to DAY at sunrise, is this cycle's reading of what the mode's own name — "Sunset→Sunrise" — has to mean for the feature to make sense at all (otherwise the screen stays warm all day once night ends). `Fixed times` mode is the same three-phase shape with user-set clock times instead of computed sunrise/sunset.
- **`target()` DOES control ON/OFF — a corrected decision, not the original one.** A first version had every mode return only warmth/brightness, keeping the user's ON/OFF toggle fully independent, reasoning that an automatic mode switching itself on unprompted (mid screen-share, say) was the worse surprise. An independent review found the real consequence: once a user turned the filter on under a non-manual schedule, there was no state it could ever reach that looked like "off" again — even the sunrise phase just held `isOn=true` at a permanent, unexplained tint forever. A mode literally named "Sunset→Sunrise" that can never actually stop at sunrise defeats the one thing its name promises. The schedule's own `.day` phase now means genuinely off (`isOn=false`, neutral values) once its ramp completes — `PresetID.day`'s own values (4000K/100%, a mild daytime warmth) stay reachable only as a manual preset button, never as what an automatic schedule settles on. Manually toggling ON/OFF is treated exactly like a slider drag: a manual override that pauses the schedule until the next phase boundary.
- **`activePreset` is re-set once a ramp settles exactly on a preset's values**, not left permanently `nil`. `warmthK`/`brightness`'s own `didSet` unconditionally clears `activePreset` on every write (C4), so a schedule ticking those fields every 10–60s left the popover's DAY/EVENING/NIGHT picker blank for as long as the schedule ran, with no way back — an independent review caught this by tracing the actual `didSet` chain, not by running the app. `ScheduleCoordinator.evaluateNow()` now re-assigns `activePreset` last (same "set last, unconditionally" pattern `AppState.apply(preset:)` already uses) whenever `ScheduleEngine.target()` reports the ramp has landed exactly on a preset; mid-ramp it correctly stays `nil`, same as a manual slider drag.
- **No `source` field on `AppState`.** The sketch above proposes tagging a write `source = .schedule`; the shipped mechanism instead has `ScheduleCoordinator` set a private flag immediately around its own writes (now four: `isOn`, `warmthK`, `brightness`, `activePreset`) and treat any change to the first three that arrives *without* that flag set as a manual override. This trades a small amount of robustness for not adding a field `AppState` itself has no other use for: the guard depends on the Combine subscription it protects staying fully synchronous (no `.receive(on:)`/`.debounce`/`.throttle`), which `ScheduleCoordinator.swift`'s own comment on the flag calls out explicitly as a constraint on any future edit to that subscription.
- **`target()` takes an injected `values: (PresetID) -> PresetValues` closure, never `PresetID.defaultValues` directly.** A user who customized EVENING in Settings (C4) gets *their* EVENING from the schedule, not the factory one — `ScheduleEngineTests.test_target_usesInjectedValues_notHardcodedDefaults` pins this after a C4 review flagged the stale `PresetID.warmthK`/`.brightness` accessors as exactly this footgun for whichever cycle built scheduling.
- **Phase start times are forced chronological** (`ScheduleEngine.chronological(_:)`) — `phases`/`target` pick the active phase by comparing raw start times, so a bedtime configured earlier than sunset (an ordinary configuration at high latitudes in summer — nothing invalid about wanting to sleep before dark) let EVENING's later clock time permanently outrank a NIGHT phase that had already begun, for the rest of the night. Found by an independent review's line-by-line pass and reproduced with a real city (London, midsummer) before being accepted. Any phase whose configured or computed start would sort at or before the one before it is nudged one second later instead.
- **The `$scheduleConfig` Combine subscription uses `.receive(on: .main)`.** `@Published` fires from `willSet`, before the new value is stored, and `handleConfigChanged()` reads `appState.scheduleConfig` itself rather than the value the publisher carried — a synchronous sink would see the *previous* config. `DisplayCoordinator` hit this exact bug already (see its own doc comment) and fixed it the same way; missing it here was reproduced directly by an independent review: switching live from Manual to a real mode in Settings silently did nothing until a second, unrelated config change happened to also fire the subscription.
- **The driver's timer runs in `.common` run-loop mode from the start**, not `.default`. A `.default`-mode timer stops firing while a menu is open or a window is being dragged — the independent C4 review found precisely this bug in `PWMSafeCoordinator`'s drift poll; that fix landed alongside this one rather than being carried forward a second time (see the PWM entry below).
- **No timer at all in Manual mode** (the default for every install). CLAUDE.md §8's idle-CPU budget shouldn't pay for a repeating wakeup nobody asked for.
- **`ScheduleCoordinator.stop()` is called from `applicationWillTerminate`, before the gamma-restore calls.** Without it, a tick already queued on the run loop could fire between the restore and the process actually exiting, re-tinting the display on the way out — the same "every coordinator with a live Timer needs an explicit teardown hook" lesson `PWMSafeCoordinator.restoreAndDisable()` already exists for, generalized here rather than reintroduced.
- **`PWMSafeCoordinator`'s drift-poll timer also switched to `.common` mode in this cycle** (`Dimit/Features/PWMSafeCoordinator.swift`), closing the docs/QA.md item carried forward from C4 — `ScheduleCoordinator` needed the fix anyway, so applying it to its sibling coordinator in the same pass cost one line instead of a fourth review cycle rediscovering it.
- **`ScheduleConfig`/`TimeOfDay`/`Coordinate` all have hand-written `decodeIfPresent`-per-field decoders**, matching `PersistedState`'s own. `Persistence`'s outer `decodeIfPresent(ScheduleConfig.self, forKey:)` only protects against the *key* being absent; it does nothing once decoding starts and a field *inside* the nested struct turns out to be missing. Without this, the next field added to any of the three (a schedule feature is likely to grow one) would reintroduce the "one new key wipes every existing user's entire saved state" bug this codebase has already hit and fixed twice.
- **The NOAA algorithm was derived from first principles, not transcribed from memory**, after two wrong transcriptions each passed an initial sanity check anyway (one swapped sunrise and sunset outright; a first "fix" put both events 9+ hours off) — see `SolarCalculator.swift`'s own comment on the final formula. Verified against two independent references before trusting it: Tashkent 2026-09-08 (±3 min per CLAUDE.md §8) and London's 2026-12-21 winter solstice — then re-verified against this machine's real system clock and timezone for the current date, and independently reproduced a third time by a reviewer with no access to the other two verifications.

## 4. License client state machine

```mermaid
stateDiagram-v2
    [*] --> unlicensed : first launch, trial starts
    unlicensed --> trial : trialStartedAt written
    trial --> trialEnded : 7 days elapsed
    trial --> active : activate 200
    trialEnded --> active : activate 200
    active --> active : validate 200 every 30 d
    active --> grace : validate unreachable
    grace --> active : validate 200
    grace --> expiredNeedsValidation : offline 14 d
    active --> revoked : validate/activate 410
    grace --> revoked : 410
    expiredNeedsValidation --> active : validate 200
    active --> unlicensed : deactivate 200
```

Feature gating: `trial` and `active` and `grace` have everything. `trialEnded` and `expiredNeedsValidation` keep warmth and dim but disable PWM-Safe and scheduling and show a persistent bar. `revoked` turns the filter off and shows the localized message.

Validation timing: on launch if `now - lastValidated > 30 d`, then retry with exponential backoff (1 h, 4 h, 24 h) while unreachable. Never more than one request in flight. All requests carry `appVersion` and `platform`, nothing else identifying beyond `deviceId`.

## 5. Server: Cloudflare Worker

Stack: TypeScript, Hono router, D1 via prepared statements, KV for rate limits, Vitest with `@cloudflare/vitest-pool-workers`. Deployed at `api.dimit.uz`. Secrets via `wrangler secret`: `PAYME_KEY`, `PAYME_TEST_KEY`, `CLICK_SECRET_KEY`, `RESEND_API_KEY`, `LS_WEBHOOK_SECRET` (M7), `ADMIN_TOKEN`.

### 5.1 Schema (`server/schema.sql`)

```sql
CREATE TABLE licenses (
  key         TEXT PRIMARY KEY,             -- DIMT-XXXX-XXXX-XXXX-XXXX
  email       TEXT NOT NULL,
  source      TEXT NOT NULL CHECK (source IN ('payme','click','ls','manual')),
  order_ref   TEXT,                         -- orders.id or LS order id
  seats       INTEGER NOT NULL DEFAULT 3,
  status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','revoked')),
  created_at  INTEGER NOT NULL              -- unix ms
);
CREATE TABLE activations (
  instance_id   TEXT PRIMARY KEY,
  key           TEXT NOT NULL REFERENCES licenses(key),
  device_id     TEXT NOT NULL,
  device_name   TEXT NOT NULL,
  platform      TEXT NOT NULL,              -- 'mac' | 'win'
  activated_at  INTEGER NOT NULL,
  last_seen     INTEGER NOT NULL,
  UNIQUE (key, device_id)                   -- re-activating the same device reuses the seat
);
CREATE TABLE orders (
  id            TEXT PRIMARY KEY,           -- 12-char base32, used as Payme account / Click merchant_trans_id
  email         TEXT NOT NULL,
  telegram      TEXT,
  locale        TEXT NOT NULL,              -- 'uz' | 'ru' | 'en'
  provider      TEXT NOT NULL CHECK (provider IN ('payme','click','ls')),
  amount_tiyin  INTEGER NOT NULL,           -- UZS * 100
  status        TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','paid','cancelled')),
  license_key   TEXT REFERENCES licenses(key),
  created_at    INTEGER NOT NULL,
  paid_at       INTEGER
);
CREATE TABLE payme_transactions (
  id            TEXT PRIMARY KEY,           -- Payme's transaction id
  order_id      TEXT NOT NULL REFERENCES orders(id),
  state         INTEGER NOT NULL,           -- 1 created, 2 performed, -1 cancelled, -2 cancelled after perform
  create_time   INTEGER NOT NULL,           -- Payme "time" field
  perform_time  INTEGER NOT NULL DEFAULT 0,
  cancel_time   INTEGER NOT NULL DEFAULT 0,
  reason        INTEGER
);
CREATE TABLE click_transactions (
  click_trans_id  TEXT PRIMARY KEY,
  order_id        TEXT NOT NULL REFERENCES orders(id),
  prepare_id      INTEGER NOT NULL,
  status          TEXT NOT NULL,            -- 'prepared' | 'completed' | 'cancelled'
  created_at      INTEGER NOT NULL
);
-- M7
CREATE TABLE affiliates (handle TEXT PRIMARY KEY, payout_method TEXT, rate REAL NOT NULL DEFAULT 0.25);
CREATE TABLE referrals  (order_ref TEXT, handle TEXT, amount INTEGER, created_at INTEGER);
```

### 5.2 Routes

| Route | Auth | Notes |
|---|---|---|
| `POST /v1/orders` | none, rate-limited 10/min/IP | validates email + locale + provider, computes amount from `config.priceUZS`, returns `checkoutUrl` (see §7) |
| `GET /v1/orders/:id` | none, rate-limited 60/min/IP | returns `status` and, when paid, `key`. The id is unguessable (12 base32 chars) and the page stops polling after 15 min |
| `POST /v1/activate` | none, rate-limited 20/min/IP and 20/day/key | seat logic: same `device_id` → reuse row; else if `count < seats` → insert; else 409 with the device list |
| `POST /v1/validate` | none | 200 with fresh `validUntil = now + 90 d`; 410 if revoked; 404 if instance unknown |
| `POST /v1/deactivate` | none | deletes the activation row |
| `POST /webhooks/payme` | HTTP Basic `Paycom:<PAYME_KEY>` | JSON-RPC 2.0, §7.1 |
| `POST /webhooks/click` | `sign_string` MD5, §7.2 | form-encoded |
| `POST /webhooks/lemonsqueezy` | HMAC-SHA256 header | M7 |
| `POST /admin/mint` | `Authorization: Bearer ADMIN_TOKEN` | used by `scripts/mint.ts` for Teams and manual sales |
| `GET /r/:handle` | none | M7 affiliate redirect |

Key generation: 20 random bytes → Crockford base32 → 4 groups of 4 after `DIMT-`. Uniqueness enforced by the primary key; retry once on collision.

Logging: request path, status, latency, SHA-256 of the key (first 12 hex chars), never the key, never the email, never the IP beyond the KV rate-limit bucket (which expires in 24 h).

### 5.3 Errors returned to the app

All errors are `{ error: "<code>" }` with codes `invalid_key`, `no_seats`, `revoked`, `unknown_instance`, `rate_limited`. The app maps each to a String Catalog key; no server text is ever shown to the user.

## 6. Order and key lifecycle

```mermaid
sequenceDiagram
    participant U as Buyer (site /uz/buy)
    participant S as Worker
    participant P as Payme
    participant R as Resend
    U->>S: POST /v1/orders {email, locale, provider: payme}
    S-->>U: 201 {orderId, checkoutUrl}
    U->>P: redirect to checkoutUrl
    P->>S: CheckPerformTransaction {account.order_id, amount}
    S-->>P: {allow: true}
    P->>S: CreateTransaction {id, time, amount, account}
    S-->>P: {create_time, transaction: order_id, state: 1}
    P->>S: PerformTransaction {id}
    S->>S: order.status = paid, mint key, licenses row
    S-->>P: {perform_time, transaction, state: 2}
    S->>R: send key email (locale template)
    P-->>U: redirect back to /download?order=orderId
    U->>S: GET /v1/orders/orderId (poll)
    S-->>U: {status: paid, key: DIMT-…}
```

Click follows the same shape with `prepare` (validate order, return `merchant_prepare_id`) and `complete` (mark paid, mint, email).

Refunds and revocations: `CancelTransaction` with state 2 → state −2, order `cancelled`, license `revoked`. Manual refunds through Click or a card dispute: `scripts/revoke.ts <key>`. The app sees `revoked` on its next validation.

## 7. Payment provider protocols

Verify every detail below against the official docs before M3 ends: Payme at `developer.help.paycom.uz`, Click at `docs.click.uz`. The PayTechUZ library (`docs.pay-tech.uz`) is a good second reference for edge cases and error codes.

### 7.1 Payme Merchant API (JSON-RPC 2.0, single endpoint)

- Auth: `Authorization: Basic base64("Paycom:" + PAYME_KEY)`; test environment uses `PAYME_TEST_KEY`. Wrong or missing → error `-32504`.
- Amounts are in **tiyin** (UZS × 100). Mismatch → `-31001`.
- Account field: `account.order_id`. Unknown order → `-31050` (any code in −31050…−31099 is "account not found" class).
- Checkout URL: `https://checkout.paycom.uz/` + base64(`m=<merchant_id>;ac.order_id=<orderId>;a=<amount_tiyin>;l=<uz|ru|en>;c=<return_url>`). Test: `https://test.paycom.uz/`.
- Methods and required behaviour:

| Method | Must do |
|---|---|
| `CheckPerformTransaction` | order exists and is `pending`, amount matches → `{allow: true}`; may also return `detail.receipt_type` and items for fiscalisation (add when Payme asks). |
| `CreateTransaction` | if a transaction with this `id` exists → return its current state (idempotent). Else if the order already has a live transaction → `-31008`. Else if `now - time > 12 h` → `-31008`. Else insert state 1. |
| `PerformTransaction` | state 1 → set state 2, `perform_time = now`, mark order paid, mint key, send email. State 2 → return the stored result (idempotent). State −1/−2 → `-31008`. |
| `CancelTransaction` | state 1 → −1; state 2 → −2 and revoke the license (Payme only allows this if the goods are returnable; we say yes, 30-day refund policy). Store `reason`. |
| `CheckTransaction` | return `create_time`, `perform_time`, `cancel_time`, `transaction`, `state`, `reason`. |
| `GetStatement` | transactions with `create_time` in `[from, to]`. |

Test cases for Vitest (Codex writes these before the merchant contract lands): wrong auth; wrong amount; unknown order; create twice with same id; create when another transaction is live; perform twice; cancel before and after perform; statement window.

### 7.2 Click Shop API

- Two form-encoded POSTs to the same URL: `action=0` (prepare) and `action=1` (complete).
- Signature: `sign_string = md5(click_trans_id + service_id + SECRET_KEY + merchant_trans_id + [merchant_prepare_id, complete only] + amount + action + sign_time)`. Mismatch → `error: -1`.
- `merchant_trans_id` is our `orders.id`. Unknown → `-5`. Already paid → `-4`. Wrong amount → `-2`. Cancelled by Click (`error != 0` in complete) → `-9` and order `cancelled`.
- Prepare returns `{click_trans_id, merchant_trans_id, merchant_prepare_id, error: 0, error_note: "Success"}`; store `merchant_prepare_id` as the `click_transactions` row id.
- Checkout URL: `https://my.click.uz/services/pay?service_id=…&merchant_id=…&amount=<UZS with 2 decimals>&transaction_param=<orderId>&return_url=<download url>`.

### 7.3 Lemon Squeezy (M7)

`order_created` with `X-Signature` HMAC-SHA256 over the raw body → mint key with `source = 'ls'`, email via Resend using the store's checkout locale (`custom_data.locale` passed from the site). `order_refunded` → revoke.

## 8. Site (`site/`, Astro)

- Locales: `uz` at `/` (default for 1.0), `ru` at `/ru/`, `en` at `/en/`. At M7 the default flips to `en` on dimit.app while dimit.uz keeps `uz`.
- Pages per locale: home, buy, download, faq, help, science, changelog, terms, privacy, refund (affiliates at M7).
- `/buy`: one form (email, optional Telegram), two buttons Payme / Click. Submits to `POST /v1/orders`, redirects to `checkoutUrl`. No JavaScript framework; a 40-line inline script.
- `/download?order=…`: polls `GET /v1/orders/:id` every 5 s for up to 15 min, shows the key, the DMG link and the activation steps. Also reached from the key email.
- Config in `site/src/config.ts`: `priceUZS`, `priceUSD`, `apiBase`, `telegram`, `supportEmail`, `legalEntity`. Footer renders the last three.
- Hosting: Cloudflare Pages, `appcast.xml` and release `.zip` files under `/updates/`.
- Analytics: Cloudflare Web Analytics (cookieless) only.

## 9. Release pipeline

1. `scripts/build.sh` — `xcodebuild archive` universal, Developer ID signing, hardened runtime.
2. `scripts/notarize.sh` — `notarytool submit --wait`, `stapler staple`, on both `.app` and `.dmg`.
3. `scripts/build_dmg.sh` — `create-dmg`, background, Applications symlink.
4. `scripts/make_appcast.sh` — Sparkle `generate_appcast` with the EdDSA private key from Keychain; uploads to `site/public/updates/`.
5. Version `MAJOR.MINOR`, build number = date `YYYYMMDDHH`. Tag `vX.Y`.

## 10. UI design spec (no Figma; build this directly)

Principles: native controls where accessibility matters (sliders, toggles), custom only for the two hero elements (the ON button and the warmth track). Follow the system appearance. Every string from the catalog. Fits 1.4× English width.

**Popover, 320 × ~440 pt:**

1. Header row: app name left, status pill right ("PWM ✓" when pinned, "Trial · 5 d" when in trial), gear button.
2. ON/OFF: full-width 56 pt button, filled with a warm gradient when ON (`#FF6A00 → #FF2D2D`), outlined when OFF. Label from `main.on` / `main.off`.
3. Warmth: label left, value right ("2700K" / "2700 K" per locale). Native `Slider` 0…6500 with a custom track gradient from white (6500) through amber (2700) to red (0). Snaps to 100 K steps.
4. Brightness: same row layout, 10…100 %, track from black to white.
5. Presets: three-segment picker DAY / EVENING / NIGHT; the active one highlighted; editing presets lives in Settings.
6. PWM-Safe row: toggle with the help text as a `?` popover; status text below in the states from CLAUDE.md §3.6.
7. Footer: one line, either "Trial: 5 days left · Buy" or "Licensed · 1 of 3 Macs" or the offline/grace text.

**Menu bar icon:** a 16 pt circle, half-filled diagonally ("dim"). Outline when OFF, filled when ON, 3 pt dot at the lower right when PWM pinned. Template image so it follows the menu bar tint.

**Settings window (tabs):** General (launch at login, language, updates opt-in, hotkeys), Schedule, Displays (per-display list with backend name and DDC experimental toggle), License, Advanced (Fallback mode, restore colours, copy diagnostics).

**Onboarding (3 steps, first launch only):** headline, screenshots-stay-normal, no-account-no-tracking with the updates opt-in checkbox and a "Restore colours" safety button.

Typography: SF Pro, values in SF Mono for the two numbers so they do not jitter. Corner radius 10 pt. Dark and light both supported by using semantic colours only.

**As built in C4** (this file is the contract, so it records what the code does where that differs from the sketch above):

- **Settings tabs shipped: General, Displays, Advanced.** Schedule (C5) and License (C7) are *omitted*, not shown disabled — an empty tab is worse than none. **Schedule shipped in C5, see that cycle's own "As built" note below; License (C7) is the only one still omitted.** The Displays tab lists each display with its real brightness-backend name but has no DDC toggle yet; that arrives with the real `DDCController` in C5. Preset editing (CLAUDE.md §3.7 "user-editable; reset to defaults") lives in General, since no tab above names it.
- **The settings window is our own `NSWindow`, not SwiftUI's `Settings {}` scene.** Opening that scene programmatically needs `openSettings` (macOS 14+) or an undocumented selector whose name Apple has changed between releases; CLAUDE.md §2 fixes the target at macOS 13. Same result for the user, none of the version risk.
- **Language override applies live, without relaunch.** CLAUDE.md §5 says "set Bundle on relaunch"; instead `AppState.effectiveLocale` is applied with `.environment(\.locale, …)` at every SwiftUI root (popover, settings, onboarding), which is how `Text` resolves String Catalog lookups. AppKit surfaces (right-click menu, window titles, toast) go through `AppState.localized(_:)`, which sets the resource's locale before `String(localized:)`. Verified by rendering all three surfaces off-screen in en/uz/ru (`DimitTests/LayoutRenderTests`).
- **Onboarding completion is recorded on "Get Started" or a user-initiated close only** (`windowShouldClose`), never on app termination — first found by a probe where SIGTERM during step 1 marked the intro as done.
- **Launch at login has no persisted mirror.** `SMAppService.mainApp.status` is the source of truth (survives reboot, visible in System Settings); `LaunchAtLogin` is a thin wrapper so the toggle has one testable surface.
- **`updateChecksEnabled` is a stored preference only.** No Sparkle, no network — C7 reads it. Defaults to off (CLAUDE.md §1.2 opt-in).
- **Global hotkeys** are `KeyboardShortcuts` (pre-approved in CLAUDE.md §2), Carbon `RegisterEventHotKey` underneath — no Accessibility or Input Monitoring prompt. The handlers are one-line calls into `AppState` (`cycleToNextPreset`, `adjustWarmth`, `adjustBrightness`), which is where the logic and the tests are; the registration layer itself has no fake to inject and is deliberately untested.

## 11. Testing strategy

| Level | What | Where |
|---|---|---|
| Unit (Swift) | `WarmthCurve`, gamma math, `render`, `LicenseState` transitions incl. grace, `ScheduleEngine` NOAA values, `PWMSafeCoordinator` with a fake backend | `DimitTests` |
| Unit (TS) | every route and every Payme/Click case in §7 | `server/test` |
| Manual matrix | CLAUDE.md §8 rows | `docs/QA.md`, one row per machine × macOS × display |
| Performance | idle CPU, popover open time, slider latency | recorded in `docs/QA.md` per release |

`docs/QA.md` is created in M0 with the gamma spike results as its first two rows.

## 12. Open questions to resolve during build

- Auto-brightness detection on macOS 26/27: no public key found on the dev machine (2026-09-08). Timebox 2 h in M2, then fall back to the unconditional banner.
- Whether Xcode 26 runs on the macOS 27 beta on the dev machine, or the 27 beta of Xcode is required.
- Payme fiscalisation (`detail` in `CheckPerformTransaction`): required only for some merchant categories; ask Payme during onboarding.
- The exact home monitor model for DDC; record it in QA.md the first time it is tested.
