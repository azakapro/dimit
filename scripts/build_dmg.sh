#!/bin/bash
# Packages a Dimit.app (default: build/release/Dimit.app) into
# <same directory>/Dimit-<version>.dmg with an Applications symlink, via hdiutil.
#
# docs/PLAN.md's C6 scope named create-dmg. Not used, on purpose: it is a
# Homebrew dependency whose only contribution over hdiutil is cosmetics — a
# background image and icon positions — and CLAUDE.md §12 says every
# dependency has to earn its place. (Its default path also drives Finder via
# AppleScript, which needs an Automation permission; it has --skip-jenkins /
# --sandbox-safe flags to avoid that, so that alone would not have ruled it
# out.) If a designed window is wanted later, the honest route is a .DS_Store
# captured from a hand-arranged volume, added here — still no new tool.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

SRC_APP=${1:-$APP}
require_app "$SRC_APP"
VERSION=$(app_version "$SRC_APP")
DIR=$(dirname "$SRC_APP")
DMG="$DIR/Dimit-$VERSION.dmg"
STAGE="$DIR/dmgroot"

rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$SRC_APP" "$STAGE/Dimit.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Dimit $VERSION" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

# Mount and check the image carries exactly what went in, with its signature
# intact. The trap guarantees the volume is detached even when a check
# fails, so a failed run never leaves a ghost volume for the next one to
# trip over (C6 review).
# Attach first and arm the trap on the raw attach output before parsing it,
# so a parse failure can never strand the volume.
ATTACH=$(hdiutil attach -readonly -nobrowse -noautoopen -plist "$DMG")
trap 'hdiutil detach "$(sed -n "s|.*<string>\(/Volumes/[^<]*\)</string>.*|\1|p" <<<"$ATTACH" | head -1)" -quiet 2>/dev/null || true' EXIT
MOUNT=$(python3 -c 'import plistlib,sys; d=plistlib.loads(sys.stdin.buffer.read()); print(next(e["mount-point"] for e in d["system-entities"] if "mount-point" in e))' <<<"$ATTACH")
[ -n "$MOUNT" ] || { echo "ERROR: could not mount $DMG" >&2; exit 1; }

[ -d "$MOUNT/Dimit.app" ] || { echo "ERROR: Dimit.app missing from the image" >&2; exit 1; }
[ -L "$MOUNT/Applications" ] || { echo "ERROR: Applications link missing from the image" >&2; exit 1; }
if ! codesign --verify --deep --strict "$MOUNT/Dimit.app"; then
    echo "ERROR: signature broken inside the image" >&2; exit 1
fi
echo "image contents: Dimit.app ($VERSION, $(app_build "$MOUNT/Dimit.app")) + Applications link, signature intact"
echo "built: $DMG ($(du -h "$DMG" | cut -f1))"
