#!/bin/bash
# Builds a universal (arm64 + x86_64) Release Dimit.app into build/release/.
#
# Two modes, chosen by environment (docs/RELEASE.md):
#   DIMIT_SIGN_IDENTITY="Developer ID Application: <name> (<TEAMID>)"  and  DIMIT_TEAM_ID=<TEAMID>
#       -> xcodebuild archive + export with the Developer ID, hardened runtime.
#          Continue with scripts/notarize.sh, which notarizes, staples and
#          builds the DMG in the right order. The only mode that produces
#          something the public can open without a Gatekeeper workaround.
#   (neither set)
#       -> ad-hoc signed Release build. Runs on testers' machines after the
#          quarantine flag is removed (docs/RELEASE.md §3). Beta use only;
#          never upload an ad-hoc build to Lemon Squeezy. Continue with
#          scripts/build_dmg.sh.
#
# Output: build/release/Dimit.app and build/release/Dimit-<version>.zip.
#
# Regenerates Dimit.xcodeproj from project.yml first (scripts/bootstrap.sh),
# so close the project in Xcode before running this.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

# CLAUDE.md §7: build number = UTC date to the minute, YYYYMMDDHHMM. Minute
# resolution and UTC because Sparkle orders updates by CFBundleVersion: two
# builds in one hour (which happened for v0.4) or a timezone change must never
# produce an equal or smaller number. Override with DIMIT_BUILD_NUMBER.
BUILD=${DIMIT_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}
rm -rf "$OUT"; mkdir -p "$OUT"
scripts/bootstrap.sh >/dev/null

# -quiet: xcodebuild prints only warnings and errors, and its exit status
# propagates under `set -e` — no output filtering that could swallow a
# failed archive (C6 review).
COMMON=(-project Dimit.xcodeproj -scheme Dimit -configuration Release -quiet
        ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CURRENT_PROJECT_VERSION="$BUILD")

if [ -n "${DIMIT_SIGN_IDENTITY:-}" ]; then
    : "${DIMIT_TEAM_ID:?set DIMIT_TEAM_ID alongside DIMIT_SIGN_IDENTITY}"
    echo "Building ($BUILD), Developer ID: $DIMIT_SIGN_IDENTITY"
    xcodebuild archive "${COMMON[@]}" -archivePath "$OUT/Dimit.xcarchive" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DIMIT_SIGN_IDENTITY" DEVELOPMENT_TEAM="$DIMIT_TEAM_ID"
    cat > "$OUT/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$DIMIT_TEAM_ID</string>
    <key>signingStyle</key><string>manual</string>
    <key>signingCertificate</key><string>Developer ID Application</string>
</dict></plist>
PLIST
    xcodebuild -exportArchive -archivePath "$OUT/Dimit.xcarchive" \
        -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export" -quiet
    mv "$OUT/export/Dimit.app" "$APP"
    rm -rf "$OUT/export"
else
    echo "Building ($BUILD), AD-HOC signed (beta/local only — no DIMIT_SIGN_IDENTITY set)"
    # ENABLE_HARDENED_RUNTIME=NO for ad-hoc builds only. With the hardened
    # runtime on, macOS enforces *library validation*: a process may load
    # only libraries signed by the same Team ID. An ad-hoc signature carries
    # no Team ID, so the embedded Sparkle.framework — signed separately —
    # fails that check and dyld kills the app at launch before `main`:
    #
    #   Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
    #   Reason: ... mapping process and mapped file (non-platform) have
    #   different Team IDs
    #
    # This is why the Debug build ran fine while the Release build did not:
    # Debug carries `get-task-allow`, which relaxes library validation, and
    # has the hardened runtime off. Nothing caught it because no build
    # before C7 embedded a framework at all.
    #
    # Turning it off costs nothing here — an ad-hoc build can't be notarized
    # and Gatekeeper rejects it regardless, so the hardened runtime protects
    # nothing in a build only testers side-load. The Developer ID path above
    # keeps it ON (CLAUDE.md §7), and there it genuinely works: Xcode
    # re-signs embedded frameworks with the same Team ID as the app.
    xcodebuild build "${COMMON[@]}" -derivedDataPath "$OUT/DerivedData" \
        CODE_SIGN_IDENTITY="-" ENABLE_HARDENED_RUNTIME=NO
    cp -R "$OUT/DerivedData/Build/Products/Release/Dimit.app" "$APP"
fi

# Prove what was built before anything ships it.
codesign --verify --deep --strict "$APP"
echo "signature: valid"
echo "architectures: $(lipo -archs "$APP/Contents/MacOS/Dimit")"
VERSION=$(app_version "$APP")
echo "version: $VERSION ($(app_build "$APP"))"
if [ -n "${DIMIT_SIGN_IDENTITY:-}" ]; then
    assert_release_signature "$APP" developer-id
else
    assert_release_signature "$APP" adhoc
fi

# Prove it launches. Every check above is static, and a statically perfect
# build shipped dead on arrival once: valid signature, right architectures,
# no entitlements — and dyld killed it before main() because the hardened
# runtime rejected the embedded Sparkle.framework. Nothing short of running
# the artifact catches that class of failure, so this runs it: three
# seconds alive, then a clean exit on SIGTERM (which is also the
# gamma-restore path, CLAUDE.md §1.8).
#
# The binary is started directly rather than via `open`, so this is a new
# process with a known PID and not a re-activation of a copy that is
# already running. It refuses to run beside one: two Dimits fight over the
# gamma table, and the check would be measuring the wrong process anyway.
# If the saved state has the filter ON, the screen tints for those three
# seconds and restores — the same thing every QA probe in docs/QA.md does.
if pgrep -x Dimit >/dev/null; then
    echo "ERROR: Dimit is running — quit it first; the launch check needs to start its own copy" >&2
    exit 1
fi
"$APP/Contents/MacOS/Dimit" >/dev/null 2>&1 &
SMOKE_PID=$!
sleep 3
if kill -0 "$SMOKE_PID" 2>/dev/null; then
    kill -TERM "$SMOKE_PID"
    sleep 1
    if kill -0 "$SMOKE_PID" 2>/dev/null; then
        kill -KILL "$SMOKE_PID" 2>/dev/null || true
        echo "ERROR: the built app ignored SIGTERM — the gamma-restore-on-quit path (CLAUDE.md §1.8) may be broken" >&2
        exit 1
    fi
    echo "launch check: alive after 3 s, quit cleanly on SIGTERM"
else
    wait "$SMOKE_PID" 2>/dev/null || true
    echo "ERROR: the built app died within 3 s of launch — see the newest ~/Library/Logs/DiagnosticReports/Dimit-*.ips" >&2
    exit 1
fi

ditto -c -k --keepParent "$APP" "$OUT/Dimit-$VERSION.zip"
echo "built: $APP  and  $OUT/Dimit-$VERSION.zip"
