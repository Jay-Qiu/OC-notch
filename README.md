# OC-Notch

A macOS notch companion for [OpenCode](https://github.com/nicepkg/OpenCode). Lives in your MacBook's notch and gives you real-time visibility into your AI coding sessions — task completions, permission requests, session counts — without leaving your editor.

## Features

- **Notch overlay** — seamlessly integrates with the MacBook notch area
- **Session monitoring** — tracks active OpenCode sessions via SSE + SQLite
- **Permission prompts** — surfaces permission requests from OpenCode so you never miss them
- **Task completion alerts** — know instantly when your AI agent finishes work
- **Pixel avatar** — animated companion that reacts to session state

## Requirements

- macOS 14.0+
- MacBook with notch (works on any Mac, but designed for notch displays)
- [OpenCode](https://github.com/nicepkg/OpenCode) running locally

## Installation

### Download (Recommended)

1. Go to [Releases](../../releases)
2. Download the latest `.zip`
3. Unzip and drag **OC-Notch.app** to `/Applications`
4. Double-click to open — the app is signed and notarized by Apple

### Build from source

```bash
# Requires Xcode 16+ and XcodeGen
brew install xcodegen
cd OC-Notch
xcodegen generate
open OC-Notch.xcodeproj
# Build & Run (⌘R)
```

### Release (maintainers)

```bash
# One-time setup: store notarization credentials in Keychain
xcrun notarytool store-credentials "OC-Notch-Notarize" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "literal:REDACTED_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"

# Full pipeline: clean → build → sign → notarize → staple → zip
make release
```

## Usage

1. Start OpenCode in your terminal
2. Launch OC-Notch — it auto-detects running OpenCode processes
3. Hover over the notch to see session status
4. Click to expand the dropdown with session details

## Tech Stack

- Swift 6 / SwiftUI
- AppKit (NSPanel overlay, no main window)
- SSE client for real-time OpenCode events
- SQLite reader for session history
- XcodeGen for project generation

## License

MIT
