#!/bin/bash
# Packages build/release/Dimit.app into build/release/Dimit-<version>.dmg with an
# Applications symlink, using hdiutil.
#
# docs/PLAN.md's C6 scope named create-dmg. It was not used, deliberately: it
# arranges the window through Finder via AppleScript, which needs an Automation
# permission the first time and hangs an unattended run without it, and it is
# a Homebrew dependency for what is purely cosmetics (icon positions, a
# background image). hdiutil is built in, prompts for nothing, and produces the
# same installable image. If a designed background is wanted later, add it
# here with a .DS_Store from a hand-arranged volume — not a new tool.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=${1:-build/release/Dimit.app}
[ -d "$APP" ] || { echo "no app at $APP — run scripts/build.sh first" >&2; exit 1; }
VERSION=$(defaults read "$PWD/$APP/Contents/Info.plist" CFBundleShortVersionString)
OUT=build/release
DMG="$OUT/Dimit-$VERSION.dmg"
STAGE="$OUT/dmgroot"

rm -rf "$STAGE" "$DMG"; mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Dimit.app"
ln -s /Applications "$STAGE/Applications"

hdiutil create -volname "Dimit $VERSION" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"

# Verify the image mounts and carries exactly what we put in it.
MOUNT=$(hdiutil attach -readonly -nobrowse -noautoopen "$DMG" | awk -F'\t' '/\/Volumes\//{print $NF}')
ls "$MOUNT" | tr '\n' ' '; echo
codesign --verify --deep --strict "$MOUNT/Dimit.app" && echo "signature intact inside the image"
hdiutil detach "$MOUNT" -quiet
echo "built: $DMG ($(du -h "$DMG" | cut -f1))"
