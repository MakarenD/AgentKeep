# AgentKeep

AgentKeep is a small macOS menu bar app for long-running agentic coding sessions.

It lets you keep a Mac awake while the lid is closed, so a coding agent can keep working.

## What It Does

- Lives in the macOS menu bar, not in the Dock.
- Shows the number of detected local development servers next to the menu bar icon.
- Toggles Keep-Awake mode from the tray menu.
- Enables Keep-Awake with `pmset -a disablesleep 1`.
- Disables Keep-Awake with `pmset -a disablesleep 0`.
- Uses a narrowly scoped privileged helper to change `pmset` without repeated password prompts.
- Requests macOS administrator approval when the helper is first registered. macOS may ask again after an app update or permission change.
- Starts automatically after login.
- Includes a `Launch at Login` toggle in the menu.
- Shows currently running local development servers such as Node.js, PHP, Python, .NET, Java, Go, Ruby, Bun, Deno, and project-local localhost listeners.
- Lets you stop all detected local development servers from one menu action.
- Disables Keep-Awake before quitting, so closing AgentKeep does not leave the Mac in `SleepDisabled` mode.
- Warns before quitting if macOS cannot disable Keep-Awake.

## Usage

Click the AgentKeep menu bar icon.

- `Enable Keep-Awake`: prevents system sleep by setting `SleepDisabled` to `1`. On first use, allow the AgentKeep background item when macOS opens Login Items settings, then choose `Enable Keep-Awake` again.
- `Disable Keep-Awake`: restores normal sleep behavior by setting `SleepDisabled` to `0`.
- `Local Servers`: shows detected local development servers with their ports, runtime, project folder, and PID.
- `Stop All Local Servers`: asks for confirmation, then stops detected local development servers.
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
CODE_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-package.sh
open .build/release-artifacts/AgentKeep-0.1.0-macOS.pkg
```

The privileged helper fails closed in ad-hoc signed builds because they have no stable Team ID. Use an Apple Development certificate for local helper testing. Distributed builds require Developer ID Application signing for the app and helper, `PKG_SIGN_IDENTITY` set to a Developer ID Installer certificate, and notarization.

After installation, open AgentKeep once from Applications. It will appear in the macOS menu bar and register itself as a Login Item.

If macOS asks for approval, allow AgentKeep in:

```text
System Settings > General > Login Items
```
