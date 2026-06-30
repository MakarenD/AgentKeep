#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-}"
BUILD_NUMBER="${BUILD_NUMBER:-}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-$ROOT_DIR/.build/release-artifacts}"
APP_DIR="$ROOT_DIR/.build/AgentKeep.app"
DMG_ROOT="$ROOT_DIR/.build/dmg-root"
NOTARIZE="${NOTARIZE:-0}"
REQUIRE_NOTARIZATION="${REQUIRE_NOTARIZATION:-0}"

cd "$ROOT_DIR"

if [[ -z "$VERSION" ]]; then
  if [[ "${GITHUB_REF_TYPE:-}" == "tag" && -n "${GITHUB_REF_NAME:-}" ]]; then
    VERSION="${GITHUB_REF_NAME#v}"
  elif [[ -n "${CI_COMMIT_TAG:-}" ]]; then
    VERSION="${CI_COMMIT_TAG#v}"
  elif git describe --tags --abbrev=0 >/dev/null 2>&1; then
    VERSION="$(git describe --tags --abbrev=0 | sed 's/^v//')"
  else
    VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/Packaging/Info.plist")"
  fi
fi

if [[ -z "$BUILD_NUMBER" ]]; then
  if [[ -n "${GITHUB_RUN_NUMBER:-}" ]]; then
    BUILD_NUMBER="$GITHUB_RUN_NUMBER"
  elif [[ -n "${CI_PIPELINE_IID:-}" ]]; then
    BUILD_NUMBER="$CI_PIPELINE_IID"
  elif git rev-list --count HEAD >/dev/null 2>&1; then
    BUILD_NUMBER="$(git rev-list --count HEAD)"
  else
    BUILD_NUMBER="1"
  fi
fi

if [[ "$REQUIRE_NOTARIZATION" == "1" ]]; then
  missing=()

  [[ -n "${CODE_SIGN_IDENTITY:-}" ]] || missing+=("CODE_SIGN_IDENTITY")
  [[ -n "${APPLE_ID:-}" ]] || missing+=("APPLE_ID")
  [[ -n "${APPLE_TEAM_ID:-}" ]] || missing+=("APPLE_TEAM_ID")
  [[ -n "${APPLE_APP_SPECIFIC_PASSWORD:-}" ]] || missing+=("APPLE_APP_SPECIFIC_PASSWORD")

  if (( ${#missing[@]} > 0 )); then
    printf 'Missing required release signing/notarization variables: %s\n' "${missing[*]}" >&2
    exit 1
  fi

  NOTARIZE="1"
fi

rm -rf "$ARTIFACTS_DIR" "$DMG_ROOT"
mkdir -p "$ARTIFACTS_DIR" "$DMG_ROOT"

VERSION="$VERSION" BUNDLE_VERSION="$BUILD_NUMBER" "$ROOT_DIR/scripts/build-app.sh"

ZIP_PATH="$ARTIFACTS_DIR/AgentKeep-$VERSION-macOS.zip"
DMG_PATH="$ARTIFACTS_DIR/AgentKeep-$VERSION-macOS.dmg"
CHECKSUM_PATH="$ARTIFACTS_DIR/AgentKeep-$VERSION-checksums.txt"

ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

cp -R "$APP_DIR" "$DMG_ROOT/AgentKeep.app"
ln -s /Applications "$DMG_ROOT/Applications"

cat > "$DMG_ROOT/Install AgentKeep.txt" <<INSTALL
Install:
1. Drag AgentKeep.app to Applications.
2. Open AgentKeep once from Applications.
3. AgentKeep registers itself to launch at login and appears in the macOS menu bar.

If macOS asks for approval, allow AgentKeep in System Settings > General > Login Items.
INSTALL

hdiutil create \
  -volname "AgentKeep $VERSION" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$NOTARIZE" == "1" ]]; then
  xcrun notarytool submit "$DMG_PATH" \
    --apple-id "$APPLE_ID" \
    --team-id "$APPLE_TEAM_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" \
    --wait

  xcrun stapler staple "$DMG_PATH"
fi

shasum -a 256 "$ZIP_PATH" "$DMG_PATH" > "$CHECKSUM_PATH"

echo "Release artifacts:"
echo "$DMG_PATH"
echo "$ZIP_PATH"
echo "$CHECKSUM_PATH"
