# Releasing Dimit

Dimit is free and open source under the MIT licence. The README is the product page, [GitHub Releases](https://github.com/azakapro/dimit/releases) hosts downloads, and GitHub Pages serves only the update feed and repository documentation. Builds and signing run on the maintainer's Mac; signing credentials stay in the login Keychain.

## 0. One-time setup

### Signing

1. Install the **Developer ID Application** certificate in the login Keychain (Xcode → Settings → Accounts → Manage Certificates). Check with `security find-identity -v -p codesigning`.
2. Store notarization credentials once: `xcrun notarytool store-credentials Dimit --apple-id <email> --team-id <TEAMID> --password <app-specific-password>`. Keep these credentials out of the repository.
3. Set `DIMIT_SIGN_IDENTITY="Developer ID Application: <name> (<TEAMID>)"` and `DIMIT_TEAM_ID=<TEAMID>` in the release shell. The Developer ID does not go into `project.yml`.
4. Keep the existing Sparkle EdDSA private key in the login Keychain. Its public half must match `SUPublicEDKey` in `Dimit/Info.plist`. Sparkle's `generate_keys` and `sign_update` tools are included in the resolved SPM artifact after building. Preserve secure backups of signing keys; do not regenerate the Sparkle key for each release or commit its private half.

Developer ID signing and Sparkle archive signing are separate checks. Keep the established signing identities across releases; investigate Sparkle's supported key-rotation process before changing either one.

### GitHub Pages

Use **the `docs/` directory on `main`**, with `docs/.nojekyll` to serve files directly. This keeps feed changes in the same reviewable history as the app, avoids a separate branch or deployment tool, and requires no dependency. Repository documentation in `docs/` is public too. No DMG or zip belongs in that directory.

After reviewing the open-source conversion, the repository maintainer must make the repository public and configure **Settings → Pages → Build and deployment → Deploy from a branch → `main` → `/docs`**. This task does not change repository visibility or Pages settings. The configured appcast URL is:

`https://azakapro.github.io/dimit/appcast.xml`

The checked-in feed initially has an empty channel: there is no signed update to advertise yet. It becomes reachable only after Pages is configured and deployed. Confirm the URL serves the expected XML before announcing update availability. Until then, users who opt in can receive a feed error; automatic checks remain off by default, and no update request occurs without opt-in.

## 1. Every signed release

`scripts/build.sh` regenerates `Dimit.xcodeproj` from `project.yml` first; close the project in Xcode before running it. Complete the build and hardware gates in §2 before uploading, then the download and update checks before announcing the release.

```bash
# 1. Edit MARKETING_VERSION in project.yml (normally MAJOR.MINOR).
#    Use a new version for every new release asset. Do not reuse a tag.
#    CFBundleVersion is UTC to the minute, YYYYMMDDHHMM. Each build must
#    increase; if rebuilding within a minute, wait or set DIMIT_BUILD_NUMBER.
# 2. Build a universal Release app using the signing variables from §0.
scripts/build.sh
# 3. Notarize and staple the app, refresh the Sparkle zip, build the DMG
#    from the stapled app, then notarize and staple the DMG.
scripts/notarize.sh
# 4. Record the reviewed release commit, then upload BOTH assets.
#    Replace X.Y and the notes-file path with the actual version and file.
git tag -a vX.Y -m "vX.Y"
git push origin vX.Y
gh release create vX.Y \
  build/release/Dimit-X.Y.dmg build/release/Dimit-X.Y.zip \
  --verify-tag --title "vX.Y" --notes-file /path/to/release-notes.md
# 5. Confirm both uploaded assets are publicly downloadable and match the
#    local files. Only then generate the feed from this exact build.
scripts/make_appcast.sh
git diff -- docs/appcast.xml
# 6. Commit the reviewed docs/appcast.xml and merge it to main using the
#    usual PR workflow. Pages then publishes the feed from main:/docs.
```

The app is stapled before packaging so a copy dragged out of the DMG can first-launch offline with the ticket on the app itself. The Sparkle zip contains that same stapled app.

Both assets use version-specific release URLs, for example `https://github.com/azakapro/dimit/releases/download/vX.Y/Dimit-X.Y.zip`. Treat published tags and assets as immutable: do not use a `latest/download` URL in the feed, replace an asset under an existing tag, or remove an asset still referenced by the feed. To correct a release, build a new version with a larger build number.

`make_appcast.sh` stages only the current zip and a copy of the feed. It refuses ad-hoc builds, verifies both app signatures, compares the archived app's files with the current build, checks the generated archive URL, version, build number, length and EdDSA signature, and verifies that signature with Sparkle's tool. Sparkle retains up to five entries per compatibility branch without needing old local archives. Existing enclosures must keep their version-specific URLs and signing metadata. Generation or validation failure leaves `docs/appcast.xml` intact; temporary archives are cleaned up. The script runs locally and cannot confirm that GitHub assets or Pages are reachable: the upload checks above remain release gates.

After Pages deploys, confirm the feed URL serves the new item and its enclosure downloads the exact uploaded zip. On a separate Mac, opt in on an older signed build and verify an update installs and launches. Do not describe this as tested until that end-to-end check has a `docs/QA.md` row.

## 2. Release gates

Check the **built artifact**, not only an Xcode run:

- [ ] `scripts/build.sh` reports both `x86_64` and `arm64`, the intended version/build, `entitlements: none`, `hardened runtime: on`, and a successful launch check.
- [ ] The notarized DMG from a fresh GitHub Release download opens on another Mac using the README's install instructions. Both DMG and Sparkle zip match the local files; record their SHA-256 checksums with `shasum -a 256 build/release/Dimit-X.Y.dmg build/release/Dimit-X.Y.zip`.
- [ ] OFF, quit, `kill -9` + relaunch, sleep/wake and unplug/replug leave the display normal, with rows for this version in `docs/QA.md`.
- [ ] At least one Mac on a stable macOS release tested, in addition to the development beta.
- [ ] No open report of a display left unusable. Experimental DDC stays off by default.
- [ ] Every compatibility and capture claim in the README has supporting evidence in `docs/QA.md`.
- [ ] `xcodebuild test -project Dimit.xcodeproj -scheme Dimit -destination 'platform=macOS'` passes; include the test count in release notes.
- [ ] Both assets are uploaded before the appcast is merged, and the deployed feed and opt-in update path are verified before announcing update availability.

## 3. Ad-hoc beta builds

Without `DIMIT_SIGN_IDENTITY`, `build.sh` produces an ad-hoc signed app. Skip `notarize.sh` (it refuses ad-hoc builds) and run `scripts/build_dmg.sh` instead. Publish the DMG only as a clearly labelled **GitHub prerelease**, with the current limitations and un-notarized status in its release notes. Never add an ad-hoc build to the appcast; the empty bootstrap feed stays empty until a signed release is ready.

**Ad-hoc builds have the hardened runtime off, on purpose.** With it on, library validation only lets a process load libraries signed by its own Team ID. An ad-hoc signature has none, so the embedded `Sparkle.framework` is refused and the app dies before `main()` (`Library not loaded … different Team IDs`). A beta once passed the static checks and failed this way. `build.sh` now runs every artifact for three seconds and fails if it dies; retain that check. The Developer ID path keeps the hardened runtime on and re-signs the embedded framework with the app's Team ID.

For an un-notarized beta, include these instructions in its release notes and keep the README in sync:

> After dragging Dimit to Applications, open Terminal and run:
> `xattr -dr com.apple.quarantine /Applications/Dimit.app`
> Then open Dimit normally. This beta is not notarized. Remove quarantine only from the Dimit copy you downloaded from this repository and trust.

## 4. What lands where

| Artifact | Made by | Destination |
|---|---|---|
| `build/release/Dimit.app` | `build.sh`, stapled in place by `notarize.sh` | Source for the two archives below |
| `build/release/Dimit-X.Y.dmg` | `notarize.sh` via `build_dmg.sh`; `build_dmg.sh` alone for ad-hoc betas | GitHub Release asset; prerelease for ad-hoc betas |
| `build/release/Dimit-X.Y.zip` | `build.sh`, replaced by `notarize.sh` with the stapled app | GitHub Release asset for Sparkle |
| `docs/appcast.xml` | `make_appcast.sh` after both assets are uploaded | Tracked on `main`, served by GitHub Pages |
| `docs/.nojekyll` | Checked in once | Keeps Pages serving the documentation directory directly |

`build/` is gitignored. Binary artifacts and private signing keys are never committed.
