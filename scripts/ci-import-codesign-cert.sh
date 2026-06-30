#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${APPLE_CERTIFICATE_BASE64:-}" ]]; then
  if [[ "${REQUIRE_NOTARIZATION:-0}" == "1" ]]; then
    echo "APPLE_CERTIFICATE_BASE64 is required for notarized releases." >&2
    exit 1
  fi

  echo "APPLE_CERTIFICATE_BASE64 is not set; skipping certificate import."
  return 0 2>/dev/null || exit 0
fi

if [[ -z "${APPLE_CERTIFICATE_PASSWORD:-}" ]]; then
  echo "APPLE_CERTIFICATE_PASSWORD is required when APPLE_CERTIFICATE_BASE64 is set." >&2
  exit 1
fi

KEYCHAIN_PASSWORD="${KEYCHAIN_PASSWORD:-agentkeep-ci-keychain}"
KEYCHAIN_NAME="${KEYCHAIN_NAME:-agentkeep-build.keychain-db}"
KEYCHAIN_PATH="$HOME/Library/Keychains/$KEYCHAIN_NAME"
CERTIFICATE_PATH="${TMPDIR:-/tmp}/agentkeep-codesign-certificate.p12"

if base64 --help 2>&1 | grep -q -- '--decode'; then
  echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > "$CERTIFICATE_PATH"
else
  echo "$APPLE_CERTIFICATE_BASE64" | base64 -D > "$CERTIFICATE_PATH"
fi

security delete-keychain "$KEYCHAIN_PATH" >/dev/null 2>&1 || true
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
security import "$CERTIFICATE_PATH" \
  -P "$APPLE_CERTIFICATE_PASSWORD" \
  -A \
  -t cert \
  -f pkcs12 \
  -k "$KEYCHAIN_PATH"

current_keychains="$(security list-keychains -d user | tr -d '"')"
security list-keychains -d user -s "$KEYCHAIN_PATH" $current_keychains
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

if [[ -z "${CODE_SIGN_IDENTITY:-}" ]]; then
  CODE_SIGN_IDENTITY="$(
    security find-identity -v -p codesigning "$KEYCHAIN_PATH" |
      awk -F '"' '/Developer ID Application/ { print $2; exit }'
  )"
  export CODE_SIGN_IDENTITY
fi

if [[ -z "${CODE_SIGN_IDENTITY:-}" ]]; then
  echo "Could not find a Developer ID Application identity in the imported certificate." >&2
  exit 1
fi

echo "Using code signing identity: $CODE_SIGN_IDENTITY"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY" >> "$GITHUB_ENV"
fi
