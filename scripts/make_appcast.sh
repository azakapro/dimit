#!/bin/bash
# Regenerates the Sparkle appcast for the site from the current release zip —
# ARCHITECTURE.md §8 / docs/RELEASE.md §1.
#
#   build/release/Dimit-<v>.zip  →  site/public/updates/Dimit-<v>.zip   (gitignored)
#                                   site/public/updates/appcast.xml     (tracked, EdDSA-signed)
#
# The zips are deployed with the site from the local build (docs/RELEASE.md)
# and never committed; .gitignore excludes them. No binary deltas: they cost a
# full unpack of every archive per run for a ~10 MB app, and the appcast
# would carry them into the repo and the deploy.
#
# The EdDSA private key is read from the login Keychain, where
# `generate_keys` put it (run once, never committed; export with
# `generate_keys -x` to move it to another Mac). The public half is
# SUPublicEDKey in Dimit/Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

FEED_DIR=site/public/updates
FEED_URL=https://dimit.uz/updates

# Sparkle's tools come from the resolved SPM package. Prefer the DerivedData
# build.sh uses (so the tools match the framework that was just shipped);
# fall back to the newest Xcode DerivedData for this project.
find_tools() {
    local candidates=("$OUT/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin")
    while IFS= read -r dir; do candidates+=("$dir/SourcePackages/artifacts/sparkle/Sparkle/bin"); done \
        < <(ls -td ~/Library/Developer/Xcode/DerivedData/Dimit-* 2>/dev/null)
    for c in "${candidates[@]}"; do [ -x "$c/generate_appcast" ] && { echo "$c"; return; }; done
    return 1
}
BIN=$(find_tools) || { echo "Sparkle tools not found — run scripts/build.sh first so SPM resolves the package" >&2; exit 1; }

require_app "$APP"
VERSION=$(app_version "$APP")
ZIP="$OUT/Dimit-$VERSION.zip"
[ -f "$ZIP" ] || { echo "missing $ZIP — run scripts/build.sh (and notarize.sh)" >&2; exit 1; }
# Sparkle updates must never be ad-hoc: Gatekeeper would refuse the
# installed update on the user's Mac, and CLAUDE.md §7 says so.
is_developer_id_signed "$APP" || { echo "$APP is not Developer-ID signed; an ad-hoc build must not go into the appcast" >&2; exit 1; }

mkdir -p "$FEED_DIR"
cp "$ZIP" "$FEED_DIR/"
"$BIN/generate_appcast" --download-url-prefix "$FEED_URL/" --maximum-versions 5 --maximum-deltas 0 "$FEED_DIR"
rm -rf "$FEED_DIR/old_updates"

# Capture, then print — never `grep | head` under pipefail (scripts/lib.sh).
SUMMARY=$(grep -E "sparkle:version|sparkle:edSignature" "$FEED_DIR/appcast.xml" || true)
echo "appcast: $FEED_DIR/appcast.xml"
printf '%s\n' "$SUMMARY" | sed -n '1,4p'
