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
    xcodebuild build "${COMMON[@]}" -derivedDataPath "$OUT/DerivedData" CODE_SIGN_IDENTITY="-"
    cp -R "$OUT/DerivedData/Build/Products/Release/Dimit.app" "$APP"
fi

# Prove what was built before anything ships it.
codesign --verify --deep --strict "$APP"
echo "signature: valid"
echo "architectures: $(lipo -archs "$APP/Contents/MacOS/Dimit")"
VERSION=$(app_version "$APP")
echo "version: $VERSION ($(app_build "$APP"))"
assert_release_signature "$APP"

ditto -c -k --keepParent "$APP" "$OUT/Dimit-$VERSION.zip"
echo "built: $APP  and  $OUT/Dimit-$VERSION.zip"
