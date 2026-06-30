# AgentKeep

AgentKeep is a small macOS menu bar app for long-running agentic coding sessions.

It lets you keep a Mac awake while the lid is closed, so a coding agent can keep working.

## What It Does

- Lives in the macOS menu bar, not in the Dock.
- Toggles Keep-Awake mode from the tray menu.
- Enables Keep-Awake with `pmset -a disablesleep 1`.
- Disables Keep-Awake with `pmset -a disablesleep 0`.
- Uses the standard macOS administrator prompt when `pmset` needs privileges.
- Starts automatically after login.
- Includes a `Launch at Login` toggle in the menu.
- Disables Keep-Awake before quitting, so closing AgentKeep does not leave the Mac in `SleepDisabled` mode.
- Warns before quitting if macOS cannot disable Keep-Awake.

## Install

Download the latest DMG from GitHub Releases, open it, and drag `AgentKeep.app` to Applications.

Open AgentKeep once from Applications. It will appear in the macOS menu bar and register itself as a Login Item.

If macOS asks for approval, allow AgentKeep in:

```text
System Settings > General > Login Items
```

## Usage

Click the AgentKeep menu bar icon.

- `Enable Keep-Awake`: prevents system sleep by setting `SleepDisabled` to `1`.
- `Disable Keep-Awake`: restores normal sleep behavior by setting `SleepDisabled` to `0`.
- `Launch at Login`: controls whether AgentKeep starts after login.
- `Quit AgentKeep`: first restores `pmset -a disablesleep 0`, then exits.

Force Quit or `kill -9` can prevent cleanup. Use the menu's quit action when possible.

## Build Locally

Requirements:

- macOS 13 or newer
- Xcode command line tools
- Swift 5.9 or newer

Run tests:

```sh
swift test
```

Build the app bundle:

```sh
./scripts/build-app.sh
open .build/AgentKeep.app
```

Build a local DMG and ZIP:

```sh
./scripts/package-release.sh
open .build/release-artifacts/AgentKeep-0.1.0-macOS.dmg
```

Local builds are ad-hoc signed by default. They are good for development, but public downloads should be Developer ID signed and notarized.

## GitHub Releases

GitHub Actions runs tests, builds a universal macOS app (`arm64` and `x86_64`), creates a DMG and ZIP, and attaches them to a GitHub Release.

Push a version tag to publish a release:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Pushes to `main` also build downloadable workflow artifacts, but only tags matching `v*` create GitHub Releases.

Notarized release builds require these GitHub repository secrets:

- `APPLE_CERTIFICATE_BASE64`: base64-encoded Developer ID Application `.p12`.
- `APPLE_CERTIFICATE_PASSWORD`: password for the `.p12`.
- `APPLE_ID`: Apple Developer account email for notarization.
- `APPLE_TEAM_ID`: Apple Developer Team ID.
- `APPLE_APP_SPECIFIC_PASSWORD`: app-specific password for notarization.
- `KEYCHAIN_PASSWORD`: temporary CI keychain password.
- `CODE_SIGN_IDENTITY`: optional Developer ID Application identity override.
