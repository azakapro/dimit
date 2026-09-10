#!/bin/bash
# Notarizes a Developer-ID build and produces the two shippable artifacts, in
# the order Apple's guidance requires (staple the app BEFORE packaging it, so
# a copy dragged out of the DMG launches offline) — CLAUDE.md §7,
# docs/RELEASE.md §1:
#
#   1. zip the app  → notarytool submit --wait  → stapler staple the .app
#   2. re-zip the stapled app                    → build/release/Dimit-<v>.zip  (Sparkle release asset)
#   3. scripts/build_dmg.sh from the stapled app → notarytool submit --wait → stapler staple the .dmg
#
# One-time setup, by the account holder (never commit these values):
#   xcrun notarytool store-credentials Dimit \
#       --apple-id <apple-id-email> --team-id <TEAMID> --password <app-specific-password>
# The profile name is read from DIMIT_NOTARY_PROFILE (default "Dimit").
#
# Refuses ad-hoc builds up front rather than after a multi-minute wait.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

PROFILE=${DIMIT_NOTARY_PROFILE:-Dimit}
require_app "$APP"
VERSION=$(app_version "$APP")

if ! is_developer_id_signed "$APP"; then
    echo "$APP is not Developer-ID signed (ad-hoc build?) — build with DIMIT_SIGN_IDENTITY set first." >&2
    exit 1
fi
# Fail fast on missing credentials, before uploading anything.
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || { echo "no notarytool credentials under profile '$PROFILE' — see the header" >&2; exit 1; }

# 1. The app itself.
SUBMIT_ZIP="$OUT/Dimit-$VERSION-notarize.zip"
ditto -c -k --keepParent "$APP" "$SUBMIT_ZIP"
xcrun notarytool submit "$SUBMIT_ZIP" --keychain-profile "$PROFILE" --wait
rm -f "$SUBMIT_ZIP"
xcrun stapler staple "$APP"

# 2. The Sparkle zip, from the stapled app (replaces build.sh's unstapled one).
ditto -c -k --keepParent "$APP" "$OUT/Dimit-$VERSION.zip"

# 3. The DMG, from the stapled app.
scripts/build_dmg.sh "$APP"
DMG="$OUT/Dimit-$VERSION.dmg"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

spctl --assess --type execute --verbose=2 "$APP" 2>&1 | tail -1 || true
echo "notarized and stapled: $APP, $DMG; Sparkle zip refreshed: $OUT/Dimit-$VERSION.zip"
