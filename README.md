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

Build and install a local package:

```sh
./scripts/build-package.sh
open .build/release-artifacts/AgentKeep-0.1.0-macOS.pkg
```

After installation, open AgentKeep once from Applications. It will appear in the macOS menu bar and register itself as a Login Item.

If macOS asks for approval, allow AgentKeep in:

```text
System Settings > General > Login Items
```
