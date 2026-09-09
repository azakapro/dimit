#!/bin/bash
# Builds a universal (arm64 + x86_64) Release Dimit.app into build/release/.
#
# Two modes, chosen by environment (docs/RELEASE.md):
#   DIMIT_SIGN_IDENTITY="Developer ID Application: <name> (<TEAMID>)"  and  DIMIT_TEAM_ID=<TEAMID>
#       -> xcodebuild archive + export with the Developer ID, hardened runtime,
#          ready for scripts/notarize.sh. This is the only mode that produces
#          something the public can open without a Gatekeeper workaround.
#   (neither set)
#       -> ad-hoc signed Release build. Runs on this machine and on testers'
#          machines after `xattr -d com.apple.quarantine` / right-click → Open.
#          Beta use only; never upload an ad-hoc build to Lemon Squeezy.
#
# Output: build/release/Dimit.app and build/release/Dimit-<version>.zip
# (the zip is what Sparkle serves in C7; the DMG comes from build_dmg.sh).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)".*/\1/p' project.yml | head -1)
BUILD=${DIMIT_BUILD_NUMBER:-$(date +%Y%m%d%H)}   # CLAUDE.md §7: build number = date YYYYMMDDHH
OUT=build/release
rm -rf "$OUT"; mkdir -p "$OUT"

scripts/bootstrap.sh >/dev/null

# CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO: without it Xcode adds
# com.apple.security.get-task-allow (debugger attach) even to Release builds,
# which CLAUDE.md §7 forbids and notarytool rejects outright. Found by this
# script's own entitlement check on the first v0.4 build.
COMMON=(-project Dimit.xcodeproj -scheme Dimit -configuration Release
        ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO CURRENT_PROJECT_VERSION="$BUILD"
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO)

if [ -n "${DIMIT_SIGN_IDENTITY:-}" ]; then
    : "${DIMIT_TEAM_ID:?set DIMIT_TEAM_ID alongside DIMIT_SIGN_IDENTITY}"
    echo "Building $VERSION ($BUILD), Developer ID: $DIMIT_SIGN_IDENTITY"
    xcodebuild archive "${COMMON[@]}" -archivePath "$OUT/Dimit.xcarchive" \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$DIMIT_SIGN_IDENTITY" DEVELOPMENT_TEAM="$DIMIT_TEAM_ID" \
        | grep -E "error|warning: .*sign|ARCHIVE" || true
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
        -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/export" | grep -E "error|EXPORT" || true
    cp -R "$OUT/export/Dimit.app" "$OUT/Dimit.app"
else
    echo "Building $VERSION ($BUILD), AD-HOC signed (beta/local only — no DIMIT_SIGN_IDENTITY set)"
    xcodebuild build "${COMMON[@]}" -derivedDataPath "$OUT/DerivedData" CODE_SIGN_IDENTITY="-" \
        | grep -E "error|BUILD" || true
    cp -R "$OUT/DerivedData/Build/Products/Release/Dimit.app" "$OUT/Dimit.app"
fi

# Prove what was built before anything ships it.
codesign --verify --deep --strict --verbose=1 "$OUT/Dimit.app" 2>&1 | tail -1
echo "architectures: $(lipo -archs "$OUT/Dimit.app/Contents/MacOS/Dimit")"
echo "version: $(defaults read "$PWD/$OUT/Dimit.app/Contents/Info.plist" CFBundleShortVersionString) ($(defaults read "$PWD/$OUT/Dimit.app/Contents/Info.plist" CFBundleVersion))"
# `--entitlements -` prints a bracketed listing on current macOS and an XML
# blob on older ones; match either so the check can't silently pass.
if codesign -d --entitlements - "$OUT/Dimit.app" 2>/dev/null | grep -qE "\[Key\]|<key>"; then
    echo "ERROR: the app carries entitlements — CLAUDE.md §7 says none, and notarization rejects get-task-allow:"
    codesign -d --entitlements - "$OUT/Dimit.app" 2>/dev/null | grep -E "\[Key\]|<key>"
    exit 1
else
    echo "entitlements: none (as specified)"
fi
codesign -dvv "$OUT/Dimit.app" 2>&1 | grep -q "runtime" && echo "hardened runtime: on" || echo "WARNING: hardened runtime is OFF"

ditto -c -k --keepParent "$OUT/Dimit.app" "$OUT/Dimit-$VERSION.zip"
echo "built: $OUT/Dimit.app  and  $OUT/Dimit-$VERSION.zip"
