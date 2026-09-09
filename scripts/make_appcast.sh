#!/bin/bash
# Regenerates the Sparkle appcast for the site from the release zip(s) —
# ARCHITECTURE.md §8 / docs/RELEASE.md §1 step 6.
#
#   build/release/Dimit-<v>.zip  →  site/public/updates/Dimit-<v>.zip
#                                   site/public/updates/appcast.xml  (EdDSA-signed)
#
# The EdDSA private key is read from the login Keychain, where
# `generate_keys` put it (run once, never committed; export with
# `generate_keys -x` to move it to another Mac). The public half is
# SUPublicEDKey in Dimit/Info.plist. Sparkle's tools come from the resolved
# SPM package, so this works on any clone that has built the app.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

FEED_DIR=site/public/updates
FEED_URL=https://dimit.uz/updates
BIN=$(ls -d ~/Library/Developer/Xcode/DerivedData/Dimit-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1)
[ -n "$BIN" ] && [ -x "$BIN/generate_appcast" ] || { echo "Sparkle tools not found — build the app once so SPM resolves the package" >&2; exit 1; }

require_app "$APP"
VERSION=$(app_version "$APP")
ZIP="$OUT/Dimit-$VERSION.zip"
[ -f "$ZIP" ] || { echo "missing $ZIP — run scripts/build.sh (and notarize.sh)" >&2; exit 1; }
# Sparkle updates must never be ad-hoc: Gatekeeper would refuse the
# installed update on the user's Mac, and CLAUDE.md §7 says so.
is_developer_id_signed "$APP" || { echo "$APP is not Developer-ID signed; an ad-hoc build must not go into the appcast" >&2; exit 1; }

mkdir -p "$FEED_DIR"
cp "$ZIP" "$FEED_DIR/"
# generate_appcast signs every zip in the directory it is given, keeps the
# last few entries, and writes/merges appcast.xml in place.
"$BIN/generate_appcast" --download-url-prefix "$FEED_URL/" --maximum-versions 5 "$FEED_DIR"
echo "appcast: $FEED_DIR/appcast.xml"
grep -E "sparkle:version|sparkle:edSignature" "$FEED_DIR/appcast.xml" | head -4
