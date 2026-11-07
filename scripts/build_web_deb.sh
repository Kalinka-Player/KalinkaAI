#!/usr/bin/env bash
# Build the architecture-independent kalinka-web Debian package: the Flutter
# web bundle, dropped where kalinka-server serves it (/usr/share/kalinka-web).
# Install alongside the server, then open http://<host>:<server-port>.
#
#   scripts/build_web_deb.sh             # build build/web, then the .deb
#   scripts/build_web_deb.sh --no-build  # package an existing build/web
#
# Output: build/deb/kalinka-web_<version>_all.deb
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(sed -n 's/^version: *\([^+ ]*\).*/\1/p' pubspec.yaml)
[ -n "$VERSION" ] || { echo "could not read version from pubspec.yaml" >&2; exit 1; }

# git-describe for the in-app version footer (same stamping as build_release.sh).
if ! GIT_DESCRIBE=$(git describe --tags --dirty 2>/dev/null); then
  DIRTY=""
  git diff --quiet HEAD 2>/dev/null || DIRTY="-dirty"
  GIT_DESCRIBE="v${VERSION}-g$(git rev-parse --short HEAD)${DIRTY}"
fi

if [ "${1:-}" != "--no-build" ]; then
  echo "Building web bundle, version: $GIT_DESCRIBE"
  # --wasm compiles the Dart app to WebAssembly with a JS fallback bundled
  # alongside it; the loader picks whichever the browser supports. Still
  # renders with CanvasKit (index.html pins that), so this doesn't need the
  # COOP/COEP headers the skwasm renderer would.
  flutter build web --release --wasm --dart-define=GIT_DESCRIBE="$GIT_DESCRIBE"
fi
[ -d build/web ] || { echo "build/web missing — run without --no-build first" >&2; exit 1; }
# The supervisor serves the setup hotspot's activation page from this package.
for f in activate.html activate.css; do
  [ -f "build/web/$f" ] || { echo "build/web/$f missing — rebuild build/web" >&2; exit 1; }
done

PKG="kalinka-web_${VERSION}_all"
STAGE="build/deb/${PKG}"
rm -rf "$STAGE"
mkdir -p "$STAGE/DEBIAN" "$STAGE/usr/share/kalinka-web"

cp -r build/web/. "$STAGE/usr/share/kalinka-web/"
sed "s/@VERSION@/${VERSION}/" packaging/web/debian/control > "$STAGE/DEBIAN/control"

OUT="build/deb/${PKG}.deb"
# --root-owner-group so bundle files are owned by root:root without fakeroot.
dpkg-deb --root-owner-group --build "$STAGE" "$OUT"

echo "Built $OUT"
dpkg-deb --info "$OUT"
