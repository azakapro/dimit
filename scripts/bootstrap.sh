#!/bin/bash
# One-time (and re-run-safe) environment setup. Run this before opening the
# project for the first time, or after pulling a change to project.yml.
#
# Flagged explicitly here rather than left implicit, per code review on C1:
# CLAUDE.md §12 says "ask before adding any dependency" and XcodeGen
# (github.com/yonaskolb/XcodeGen) is a dev-time addition that wasn't named
# anywhere before this script. It generates Dimit.xcodeproj from project.yml
# so nobody has to hand-edit a .pbxproj (genuinely bad practice — that
# format is not designed for humans or for merging) and so two people (or a
# person and Claude Code) working in parallel never get a merge conflict in
# a generated file. It ships as a single, tiny, MIT-licensed CLI binary and
# never touches the built app — this script is the only place it's needed.
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "Installing XcodeGen (dev-time only; generates Dimit.xcodeproj, never ships in the app)..."
    if ! command -v brew >/dev/null 2>&1; then
        echo "Homebrew not found. Install it from https://brew.sh, or install XcodeGen some other way, then re-run this script." >&2
        exit 1
    fi
    brew install xcodegen
fi

xcodegen generate
echo "Done. Open Dimit.xcodeproj, or run: xcodebuild -project Dimit.xcodeproj -scheme Dimit build"
