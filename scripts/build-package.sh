#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT_DIR/.build/release-artifacts}"
APP_DIR="$ROOT_DIR/.build/AgentKeep.app"
PKG_ROOT="$ROOT_DIR/.build/pkg-root"

cd "$ROOT_DIR"

if [[ -z "$VERSION" ]]; then
  if git describe --tags --abbrev=0 >/dev/null 2>&1; then
    VERSION="$(git describe --tags --abbrev=0 | sed 's/^v//')"
  else
    VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/Packaging/Info.plist")"
  fi
fi

if [[ -z "$BUILD_NUMBER" ]]; then
  if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
    BUILD_NUMBER="$GITHUB_RUN_NUMBER"
  elif git rev-list --count HEAD >/dev/null 2>&1; then
    BUILD_NUMBER="$(git rev-list --count HEAD)"
  else
    BUILD_NUMBER="1"
  fi
fi

rm -rf "$ARTIFACTS_DIR" "$PKG_ROOT"
mkdir -p "$ARTIFACTS_DIR" "$PKG_ROOT/Applications"

VERSION="$VERSION" BUNDLE_VERSION="$BUILD_NUMBER" "$ROOT_DIR/scripts/build-app.sh"

PKG_PATH="$ARTIFACTS_DIR/AgentKeep-$VERSION-macOS.pkg"

ditto --norsrc --noextattr "$APP_DIR" "$PKG_ROOT/Applications/AgentKeep.app"
xattr -cr "$PKG_ROOT/Applications/AgentKeep.app" 2>/dev/null || true

pkgbuild_args=(
  --root "$PKG_ROOT"
  --identifier "com.agentkeep.AgentKeep"
  --version "$VERSION"
  --install-location "/"
  --filter "/\\._.*"
  --filter "^\\._.*"
)

COPYFILE_DISABLE=1 pkgbuild "${pkgbuild_args[@]}" "$PKG_PATH"

echo "Package artifact:"
echo "$PKG_PATH"
