#!/bin/bash
# Notarizes and staples a Developer-ID-signed artifact (.dmg or .zip of the app),
# then staples the .app inside build/release/ so a re-zipped copy for Sparkle
# carries the ticket too. CLAUDE.md §7: notarytool submit --wait, then stapler.
#
# One-time setup, done by the account holder (never commit these values):
#   xcrun notarytool store-credentials Dimit \
#       --apple-id <apple-id-email> --team-id <TEAMID> --password <app-specific-password>
# The profile name is read from DIMIT_NOTARY_PROFILE (default "Dimit").
#
# Ad-hoc builds cannot be notarized; this script refuses them rather than
# submitting something Apple will reject after a wait.
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE=${DIMIT_NOTARY_PROFILE:-Dimit}
VERSION=$(sed -n 's/.*MARKETING_VERSION: "\(.*\)".*/\1/p' project.yml | head -1)
OUT=build/release
APP="$OUT/Dimit.app"
TARGETS=("$@")
[ ${#TARGETS[@]} -gt 0 ] || TARGETS=("$OUT/Dimit-$VERSION.dmg")

if ! codesign -dv "$APP" 2>&1 | grep -q "Authority=Developer ID Application"; then
    echo "$APP is not Developer-ID signed (ad-hoc build?) — nothing to notarize. Build with DIMIT_SIGN_IDENTITY set." >&2
    exit 1
fi

for target in "${TARGETS[@]}"; do
    [ -f "$target" ] || { echo "missing: $target" >&2; exit 1; }
    echo "submitting $target"
    xcrun notarytool submit "$target" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$target"
done

# Staple the app bundle itself and refresh the Sparkle zip from the stapled app.
xcrun stapler staple "$APP"
ditto -c -k --keepParent "$APP" "$OUT/Dimit-$VERSION.zip"
spctl --assess --type execute --verbose=2 "$APP" 2>&1 | tail -1
echo "notarized and stapled: ${TARGETS[*]} and $APP (zip refreshed)"
