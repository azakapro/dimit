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
    # $2 is the signing mode, and the hardened-runtime expectation flips
    # with it. Developer ID: ON, per CLAUDE.md §7. Ad-hoc: OFF — with it on,
    # library validation refuses the separately-signed Sparkle.framework
    # and the app dies before main() ("different Team IDs"; build.sh has
    # the full story). An earlier version of this check demanded ON in
    # both modes, which is exactly what let a dead-on-arrival beta pass.
    local runtime_on=0
    grep -q "runtime" <<<"$(signature_info "$1")" && runtime_on=1
    case "${2:-}" in
        developer-id)
            if [ "$runtime_on" = 1 ]; then
                echo "hardened runtime: on"
            else
                echo "ERROR: hardened runtime is OFF on $1 — a Developer ID build must have it (CLAUDE.md §7)" >&2
                return 1
            fi ;;
        adhoc)
            if [ "$runtime_on" = 0 ]; then
                echo "hardened runtime: off (ad-hoc build — on, it cannot load Sparkle.framework; see build.sh)"
            else
                echo "ERROR: hardened runtime is ON in an ad-hoc build — this app will die at launch with 'different Team IDs' (see build.sh)" >&2
                return 1
            fi ;;
        *)
            echo "assert_release_signature: pass the signing mode as \$2 (developer-id | adhoc)" >&2
            return 1 ;;
    esac
}
