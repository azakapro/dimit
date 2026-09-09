# Releasing Dimit

Everything here runs on the maintainer's Mac. There is no CI and no build server on purpose (docs/ARCHITECTURE.md §7.1): notarization needs the Developer ID certificate, and uploading that to a hosted runner is a risk taken for nothing at this scale.

## 0. One-time setup (account holder only)

1. Install the **Developer ID Application** certificate in the login Keychain (Xcode → Settings → Accounts → Manage Certificates). Check with `security find-identity -v -p codesigning`.
2. Store notarization credentials once: `xcrun notarytool store-credentials Dimit --apple-id <email> --team-id <TEAMID> --password <app-specific password>` (create the app-specific password at appleid.apple.com). Nothing from this step is ever written into the repo.
3. Export, for the shell that runs releases: `export DIMIT_SIGN_IDENTITY="Developer ID Application: <name> (<TEAMID>)"` and `export DIMIT_TEAM_ID=<TEAMID>`.

**Team ID is forever.** Sparkle verifies that an update was signed by the same Team ID as the running app; changing it later strands every installed copy on the old feed. Betas (v0.x) may ship under any account; **v1.0 must ship under the account that will sign every later release** — the LLC's (docs/PLAN.md §4).

## 1. Every release

```bash
# 1. Version: edit MARKETING_VERSION in project.yml (MAJOR.MINOR). The build number is
#    generated from the date by build.sh (YYYYMMDDHH), so it never needs editing.
# 2. Build (universal, Release; Developer ID if the two variables are set, else ad-hoc):
scripts/build.sh
# 3. Package:
scripts/build_dmg.sh
# 4. Notarize + staple the DMG and the app (Developer ID builds only):
scripts/notarize.sh
# 5. Tag and record:
git tag -a vX.Y -m "vX.Y — <one line>" && git push origin vX.Y
gh release create vX.Y build/release/Dimit-X.Y.dmg --title "vX.Y — <one line>" --notes-file <notes>
```

Then the two distribution steps, both C7 (docs/ARCHITECTURE.md §5, §8):

6. **Lemon Squeezy:** upload `Dimit-X.Y.dmg` to the product as a **new or replacement** file. Every past buyer sees it in My Orders. **Never delete an older file** — deleting removes it from everyone who already bought it.
7. **Sparkle:** `scripts/make_appcast.sh` (C7) regenerates `site/public/updates/appcast.xml` from `build/release/Dimit-X.Y.zip`; deploy the site.

## 2. Before tagging — the release gates

From docs/LAUNCH_STRATEGY.md §7 and docs/PLAN.md §2 C6/C7, checked against the **built artifact**, not an Xcode run:

- [ ] `scripts/build.sh` printed `architectures: x86_64 arm64`, the intended version, and `entitlements: none`.
- [ ] The DMG from a **fresh browser download** opens on a Mac that is not the build machine, using the instructions on the download page.
- [ ] OFF, quit, `kill -9` + relaunch, sleep/wake and unplug/replug all leave the display normal (docs/QA.md rows for this version).
- [ ] At least one Mac on a **stable** macOS release tested, not only the development beta.
- [ ] No open report of a display left unusable. Experimental DDC stays default-off.
- [ ] Every claim on the download page has a docs/QA.md row behind it (docs/ARCHITECTURE.md §7).
- [ ] `xcodebuild test` green, count in the release notes.

## 3. Ad-hoc beta builds (v0.x)

Without `DIMIT_SIGN_IDENTITY`, `build.sh` produces an ad-hoc signed app. Gatekeeper will refuse it on first open. Tell testers, in the message that carries the link:

> Right-click Dimit.app → Open → Open. Or in Terminal: `xattr -d com.apple.quarantine /Applications/Dimit.app`. This is because the beta isn't notarized yet; the release will be.

Never put an ad-hoc build on Lemon Squeezy or in the appcast.

## 4. What lands where

| Artifact | Made by | Goes to |
|---|---|---|
| `build/release/Dimit.app` | build.sh | nowhere directly — the source of the two below |
| `build/release/Dimit-X.Y.dmg` | build_dmg.sh (+ notarize.sh) | Lemon Squeezy product file; GitHub release asset |
| `build/release/Dimit-X.Y.zip` | build.sh, refreshed by notarize.sh | `site/public/updates/` for Sparkle (C7) |

`build/` is gitignored; nothing under it is ever committed.
