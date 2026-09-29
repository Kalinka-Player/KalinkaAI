#!/usr/bin/env bash
# Build the kalinka-kiosk Debian package: the app built for flutter-pi (direct
# DRM/KMS rendering, no X or Wayland), for the now-playing display on the
# server's own screen. Cross-builds on an x64 host; needs flutterpi_tool
# (flutter pub global activate flutterpi_tool).
#
#   scripts/build_kiosk_deb.sh             # build the bundle, then the .deb
#   scripts/build_kiosk_deb.sh --no-build  # package an existing bundle
#
# Output: build/deb/kalinka-kiosk_<version>_arm64.deb
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^version: *\([^+ ]*\).*/\1/p' pubspec.yaml)
[ -n "$VERSION" ] || { echo "could not read version from pubspec.yaml" >&2; exit 1; }

if ! GIT_DESCRIBE=$(git describe --tags --dirty 2>/dev/null); then
  DIRTY=""
  git diff --quiet HEAD 2>/dev/null || DIRTY="-dirty"
  GIT_DESCRIBE="v${VERSION}-g$(git rev-parse --short HEAD)${DIRTY}"
fi

BUNDLE=build/flutter-pi/aarch64-generic
if [ "${1:-}" != "--no-build" ]; then
  echo "Building flutter-pi bundle, version: $GIT_DESCRIBE"
  FLUTTERPI_TOOL=$(command -v flutterpi_tool || echo "$HOME/.pub-cache/bin/flutterpi_tool")
  # Generic arm64 engine: one package for the Pi 3, 4 and 5.
  "$FLUTTERPI_TOOL" build --arch=arm64 --release \
    --dart-define=GIT_DESCRIBE="$GIT_DESCRIBE"
fi
[ -x "$BUNDLE/flutter-pi" ] || { echo "$BUNDLE missing — run without --no-build first" >&2; exit 1; }

PKG="kalinka-kiosk_${VERSION}_arm64"
STAGE="build/deb/${PKG}"
LIB="$STAGE/usr/lib/kalinka-kiosk"
rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" "$LIB/bundle" "$STAGE/usr/lib/systemd/system"

# The bundle minus build leftovers (linux/ holds a CMake cache).
tar -C "$BUNDLE" --exclude=./linux --exclude=./.last_build_id -cf - . |
  tar -C "$LIB/bundle" -xf -
install -m 0755 packaging/kiosk/kalinka-kiosk-ctl "$LIB/"
install -m 0644 packaging/kiosk/systemd/*.service packaging/kiosk/systemd/*.path \
  "$STAGE/usr/lib/systemd/system/"

sed "s/@VERSION@/${VERSION}/" packaging/kiosk/debian/control > "$STAGE/DEBIAN/control"
for script in postinst prerm postrm; do
  install -m 0755 "packaging/kiosk/debian/$script" "$STAGE/DEBIAN/"
done

OUT="build/deb/${PKG}.deb"
dpkg-deb --root-owner-group --build "$STAGE" "$OUT"

echo "Built $OUT"
dpkg-deb --info "$OUT"
