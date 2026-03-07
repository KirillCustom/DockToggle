<p align="center">
  <img src=".github/icon.png" width="128" height="128" alt="DockToggle icon">
</p>

<h1 align="center">DockToggle</h1>

<p align="center">
  A macOS menu bar app that adds Windows-like Dock toggle behavior —<br>
  click an active app's Dock icon to minimize it, click again to restore.
</p>

## Features

- **Dock click toggle** — clicking an active app's Dock icon minimizes (or hides) its windows; clicking again restores them
- **Three toggle modes** — "Minimize windows" (all), "Minimize active window" (focused only), or "Hide application" (whole-app)
- **Auto-restore** — clicking an inactive app with minimized windows automatically restores them
- **Auto-update** — built-in update checks via Sparkle
- **Excluded apps** — per-app opt-out with a searchable picker
- **Fullscreen safety** — never intercepts clicks on fullscreen apps
- **Launch at login** — native macOS login item support
- **Menu bar only** — runs entirely in the menu bar with no Dock icon
- **Accessibility status** — menu bar icon reflects whether permissions are granted
- **Localized** — English and Russian

## Requirements

- macOS 15.0 (Sequoia) or later

## Installation

1. Download the latest `DockToggle.dmg` from [Releases](../../releases)
2. Open the DMG and drag **DockToggle** to your Applications folder
3. Launch DockToggle — the onboarding wizard will guide you through setup

## Usage

DockToggle lives in your menu bar. Once enabled:

- **Click** an active app's Dock icon → its windows minimize (all or just the focused one, depending on mode)
- **Click** it again → windows restore
- **Click** an inactive app with minimized windows → windows restore and the app activates

### Settings

Open Settings from the menu bar icon to configure:

- **Enable / Disable** — master toggle (also available directly from the menu bar)
- **Toggle Mode** — minimize all windows, minimize active window only, or hide the entire application
- **Launch at Login** — start DockToggle automatically when you log in
- **Excluded Apps** — select apps that should keep default Dock behavior

## Permissions

DockToggle requires **Accessibility** permission to function. This is needed to:

1. Intercept mouse clicks on the Dock (via a system-level event tap)
2. Read Dock item positions and control app windows (via the Accessibility API)

On first launch, the onboarding wizard will prompt you to grant access. You can also grant it manually:

**System Settings → Privacy & Security → Accessibility → DockToggle**

No other permissions are required. DockToggle only accesses the network to check for updates.

## Building from Source

1. Clone the repository
2. Open `DockToggle.xcodeproj` in Xcode 16+
3. Build and run (⌘R)

The project uses SwiftUI and AppKit with [Sparkle](https://sparkle-project.org) for auto-updates (via SPM).

## License

MIT License — see [LICENSE](LICENSE) for details.
