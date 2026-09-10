#!/bin/bash
# Generates docs/appcast.xml for GitHub Pages. The DMG and Sparkle zip are
# GitHub Release assets, with immutable version-tag URLs; no binaries go in
# docs/. Publish both assets before committing the feed (docs/RELEASE.md).
#
# The EdDSA private key stays in the login Keychain. Sparkle's tools come
# from the already resolved SPM package; this script makes no network calls.
# Generate in isolation, validate, then replace the feed atomically: failure
# leaves the tracked feed intact and stale local archives cannot enter it.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib.sh

FEED=docs/appcast.xml
RELEASES_URL=https://github.com/azakapro/dimit/releases

require_app "$APP"
VERSION=$(app_version "$APP")
BUILD=$(app_build "$APP")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
    || { echo "invalid release version: $VERSION" >&2; exit 1; }
[[ "$BUILD" =~ ^[0-9]+$ ]] \
    || { echo "invalid build number: $BUILD" >&2; exit 1; }
ZIP="$OUT/Dimit-$VERSION.zip"
[ -f "$ZIP" ] || { echo "missing $ZIP — run scripts/build.sh and scripts/notarize.sh" >&2; exit 1; }
# Keep the signed-only gate: an ad-hoc update would fail on the user's Mac.
is_developer_id_signed "$APP" \
    || { echo "$APP is not Developer-ID signed; an ad-hoc build must not go into the appcast" >&2; exit 1; }
codesign --verify --deep --strict "$APP"
assert_release_signature "$APP" developer-id

find_tools() {
    local c
    local candidates=("$OUT/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin")
    while IFS= read -r dir; do candidates+=("$dir/SourcePackages/artifacts/sparkle/Sparkle/bin"); done \
        < <(ls -td ~/Library/Developer/Xcode/DerivedData/Dimit-* 2>/dev/null)
    for c in "${candidates[@]}"; do
        if [ -x "$c/generate_appcast" ] && [ -x "$c/sign_update" ]; then echo "$c"; return; fi
    done
    return 1
}
BIN=$(find_tools) || { echo "Sparkle tools not found — run scripts/build.sh first so SPM resolves the package" >&2; exit 1; }

# Use the feed's filesystem so the final rename is atomic. The trap removes
# all extracted content and archives on success, failure or interruption.
mkdir -p docs
STAGE=$(mktemp -d docs/.appcast.XXXXXX)
trap 'rm -rf "$STAGE"' EXIT
mkdir "$STAGE/archives" "$STAGE/unpacked"
cp "$ZIP" "$STAGE/archives/"
STAGED_ZIP="$STAGE/archives/Dimit-$VERSION.zip"
ditto -x -k "$STAGED_ZIP" "$STAGE/unpacked"
ARCHIVED_APP="$STAGE/unpacked/Dimit.app"
require_app "$ARCHIVED_APP"
is_developer_id_signed "$ARCHIVED_APP" \
    || { echo "archive is not Developer-ID signed" >&2; exit 1; }
codesign --verify --deep --strict "$ARCHIVED_APP"
# Compare every packaged file, including Info.plist and signatures. A zip
# from a different build must not be published using the current app's tag.
diff -qr "$APP" "$ARCHIVED_APP" \
    || { echo "archive differs from $APP — rerun scripts/notarize.sh to refresh it" >&2; exit 1; }

# Sparkle preserves historical feed entries without their local archives.
# Copy only the feed and current zip: never mix archives from previous tags.
if [ -f "$FEED" ]; then cp "$FEED" "$STAGE/archives/appcast.xml"; fi
"$BIN/generate_appcast" \
    --download-url-prefix "$RELEASES_URL/download/v$VERSION/" \
    --link "$RELEASES_URL/tag/v$VERSION" \
    --maximum-versions 5 --maximum-deltas 0 "$STAGE/archives"

# Validate all retained enclosures, the new item's identity and exact zip
# length, and monotonic builds. A mismatched Keychain key can make Sparkle
# emit an unsigned enclosure with only a warning; reject that explicitly.
SIGNATURE=$(python3 - "$FEED" "$STAGE/archives/appcast.xml" "$STAGED_ZIP" "$VERSION" "$BUILD" <<'PY'
import base64
import os
import re
import sys
import xml.etree.ElementTree as ET

previous_path, generated_path, zip_path, version, build = sys.argv[1:]
sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
release_prefix = "https://github.com/azakapro/dimit/releases/download/"

def read_items(path):
    root = ET.parse(path).getroot()
    channels = root.findall("channel")
    if root.tag != "rss" or len(channels) != 1:
        raise ValueError(f"{path}: expected one RSS channel")
    items = {}
    for item in channels[0].findall("item"):
        enclosures = item.findall("enclosure")
        if len(enclosures) != 1 or item.find(sparkle + "deltas") is not None:
            raise ValueError(f"{path}: expected one full archive and no deltas")
        enclosure = enclosures[0]
        item_build = item.findtext(sparkle + "version") or enclosure.get(sparkle + "version", "")
        item_version = item.findtext(sparkle + "shortVersionString") or enclosure.get(sparkle + "shortVersionString", "")
        if not re.fullmatch(r"[0-9]+", item_build) or not re.fullmatch(r"[0-9]+\.[0-9]+(?:\.[0-9]+)?", item_version):
            raise ValueError(f"{path}: missing or invalid version/build")
        expected_url = f"{release_prefix}v{item_version}/Dimit-{item_version}.zip"
        if enclosure.get("url") != expected_url:
            raise ValueError(f"{path}: archive URL must be {expected_url}")
        signature = enclosure.get(sparkle + "edSignature", "")
        if len(base64.b64decode(signature, validate=True)) != 64:
            raise ValueError(f"{path}: missing or invalid EdDSA signature")
        length = int(enclosure.get("length", "0"))
        if length <= 0 or item_build in items:
            raise ValueError(f"{path}: invalid archive length or duplicate build")
        if any(value[0] == item_version for value in items.values()):
            raise ValueError(f"{path}: a release tag cannot identify multiple builds")
        items[item_build] = (item_version, length, signature)
    return items

try:
    previous = read_items(previous_path) if os.path.isfile(previous_path) else {}
    generated = read_items(generated_path)
    current = generated.get(build)
    if current is None or current[0] != version or current[1] != os.path.getsize(zip_path):
        raise ValueError("generated feed does not describe the current archive")
    for old_build, old in previous.items():
        if old_build == build:
            if current != old:
                raise ValueError("a published build or release asset cannot be replaced; bump the version and build")
        elif int(old_build) >= int(build) or old[0] == version:
            raise ValueError("use a new release version and a strictly increasing build number")
        if old_build in generated and generated[old_build] != old:
            raise ValueError("generation changed a historical release enclosure")
    if set(generated) - set(previous) != ({build} - set(previous)):
        raise ValueError("generated feed contains an unexpected release")
    print(current[2])
except (ValueError, ET.ParseError, OSError) as error:
    sys.exit(f"appcast validation failed: {error}")
PY
)
"$BIN/sign_update" --verify "$STAGED_ZIP" "$SIGNATURE"
mv "$STAGE/archives/appcast.xml" "$FEED"
echo "appcast: $FEED (v$VERSION, build $BUILD)"
echo "Publish the matching DMG and zip to $RELEASES_URL/tag/v$VERSION before committing the feed."
