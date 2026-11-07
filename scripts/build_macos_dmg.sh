#!/usr/bin/env bash
# Build the macOS desktop app and package it as a dmg. Ad-hoc signed
# (CODE_SIGN_IDENTITY=- in the Xcode project) but not notarized — no Apple
# Developer account — so the dmg ships under a "-beta" name: Gatekeeper
# will ask for a manual approval on first launch.
#
# Universal binary (x86_64 + arm64) by default via Xcode's standard ARCHS —
# one dmg covers both Intel and Apple Silicon Macs.
#
#   scripts/build_macos_dmg.sh             # build, then package
#   scripts/build_macos_dmg.sh --no-build  # package an existing build
#
# Output: build/macos/kalinka-<version>-macos-beta.dmg
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^version: *\([^+ ]*\).*/\1/p' pubspec.yaml)
[ -n "$VERSION" ] || { echo "could not read version from pubspec.yaml" >&2; exit 1; }

if [ "${1:-}" != "--no-build" ]; then
  scripts/build_release.sh macos
fi

APP="build/macos/Build/Products/Release/kalinka.app"
[ -d "$APP" ] || { echo "$APP missing — run without --no-build first" >&2; exit 1; }

STAGE="build/macos/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

OUT="build/macos/kalinka-${VERSION}-macos-beta.dmg"
rm -f "$OUT"
hdiutil create -volname Kalinka -srcfolder "$STAGE" -ov -format UDZO "$OUT"

echo "Built $OUT"
