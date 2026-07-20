#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DIR="$ROOT_DIR/.build/AgentKeep.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
LAUNCH_DAEMONS_DIR="$CONTENTS_DIR/Library/LaunchDaemons"
VERSION="${VERSION:-}"
BUNDLE_VERSION="${BUNDLE_VERSION:-}"
AD_HOC_CODESIGN="${AD_HOC_CODESIGN:-1}"
UNIVERSAL_BUILD="${UNIVERSAL_BUILD:-1}"
SWIFT_BUILD_ARCHS="${SWIFT_BUILD_ARCHS:-}"

cd "$ROOT_DIR"

if [[ -z "$VERSION" ]]; then
  if git describe --tags --abbrev=0 >/dev/null 2>&1; then
    VERSION="$(git describe --tags --abbrev=0 | sed 's/^v//')"
  else
    VERSION="$(plutil -extract CFBundleShortVersionString raw "$ROOT_DIR/Packaging/Info.plist")"
  fi
fi

if [[ -z "$BUNDLE_VERSION" ]]; then
  if git rev-list --count HEAD >/dev/null 2>&1; then
    BUNDLE_VERSION="$(git rev-list --count HEAD)"
  else
    BUNDLE_VERSION="1"
  fi
fi

swift_build_args=(-c "$CONFIGURATION")

if [[ -n "$SWIFT_BUILD_ARCHS" ]]; then
  for arch in $SWIFT_BUILD_ARCHS; do
    swift_build_args+=(--arch "$arch")
  done
elif [[ "$UNIVERSAL_BUILD" == "1" ]]; then
  swift_build_args+=(--arch arm64 --arch x86_64)
fi

swift build "${swift_build_args[@]}"
BIN_PATH="$(swift build "${swift_build_args[@]}" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$LAUNCH_DAEMONS_DIR"

cp "$BIN_PATH/AgentKeep" "$MACOS_DIR/AgentKeep"
cp "$BIN_PATH/AgentKeepPrivilegedHelper" "$MACOS_DIR/AgentKeepPrivilegedHelper"
cp "$ROOT_DIR/Packaging/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$ROOT_DIR/Packaging/com.agentkeep.AgentKeep.PrivilegedHelper.plist" "$LAUNCH_DAEMONS_DIR/"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$CONTENTS_DIR/Info.plist"
plutil -replace CFBundleVersion -string "$BUNDLE_VERSION" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/AgentKeep" "$MACOS_DIR/AgentKeepPrivilegedHelper"

if [[ -n "${CODE_SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp \
    --identifier "com.agentkeep.AgentKeep.PrivilegedHelper" \
    --sign "$CODE_SIGN_IDENTITY" \
    "$MACOS_DIR/AgentKeepPrivilegedHelper"
  codesign --force --options runtime --timestamp --sign "$CODE_SIGN_IDENTITY" "$APP_DIR"
elif [[ "$AD_HOC_CODESIGN" == "1" ]]; then
  codesign --force --options runtime \
    --identifier "com.agentkeep.AgentKeep.PrivilegedHelper" \
    --sign - \
    "$MACOS_DIR/AgentKeepPrivilegedHelper"
  codesign --force --options runtime --sign - "$APP_DIR"
fi

if codesign --verify --deep --strict "$APP_DIR" >/dev/null 2>&1; then
  echo "Code signature verified."
else
  echo "Warning: code signature verification failed or app is unsigned." >&2
fi

echo "Built $APP_DIR"
echo "Run with: open \"$APP_DIR\""
