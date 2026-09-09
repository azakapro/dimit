#!/bin/bash
# Shared by build.sh, build_dmg.sh and notarize.sh. Source it after `cd` to the
# repo root. One definition each of the output directory and of "what version
# is this app" — the built Info.plist is the only source of truth for the
# latter, so bumping project.yml between steps can't mislabel an artifact
# (C6 review).
OUT=build/release
APP="$OUT/Dimit.app"

app_version() { /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$1/Contents/Info.plist"; }
app_build()   { /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$1/Contents/Info.plist"; }

require_app() {
    [ -d "$1" ] || { echo "no app at $1 — run scripts/build.sh first" >&2; exit 1; }
}

# Capture-then-grep everywhere: under `pipefail`, `codesign | grep -q` fails
# whenever grep matches early and codesign takes SIGPIPE (C6 review — it
# turned an entitlement check into a false pass on this machine).
signature_info() { codesign -dvv "$1" 2>&1 || true; }

is_developer_id_signed() {
    grep -q "Authority=Developer ID Application" <<<"$(signature_info "$1")"
}

# Fails the caller if the app carries any entitlement (CLAUDE.md §7: none;
# notarytool rejects get-task-allow) or lacks the hardened runtime.
assert_release_signature() {
    local ent
    ent=$(codesign -d --entitlements - "$1" 2>/dev/null || true)
    if grep -qE "\[Key\]|<key>" <<<"$ent"; then
        echo "ERROR: $1 carries entitlements — CLAUDE.md §7 says none:" >&2
        grep -E "\[Key\]|<key>" <<<"$ent" >&2
        return 1
    fi
    echo "entitlements: none (as specified)"
    if grep -q "runtime" <<<"$(signature_info "$1")"; then
        echo "hardened runtime: on"
    else
        echo "ERROR: hardened runtime is OFF on $1" >&2
        return 1
    fi
}
