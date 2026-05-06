<p align="center">
  <img src="icon.png" width="128" height="128" alt="OC-Notch icon" />
</p>

<h1 align="center">OC-Notch</h1>

<p align="center">
  <strong>Your AI agent lives in the notch now.</strong><br/>
  A Dynamic Island–inspired companion for <a href="https://github.com/sst/opencode">OpenCode</a> that turns your MacBook's dead pixel real estate into a living, breathing command center for AI coding sessions.
</p>

<p align="center">
  <a href="../../releases"><img src="https://img.shields.io/github/v/release/Jay-Qiu/OC-notch?style=flat-square&color=00c8ff" alt="Release" /></a>
  <img src="https://img.shields.io/badge/platform-macOS_14%2B-000?style=flat-square&logo=apple&logoColor=white" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/swift-6-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift 6" />
  <img src="https://img.shields.io/badge/license-MIT-blue?style=flat-square" alt="MIT License" />
</p>

<!-- <p align="center">
  <img src="assets/demo.gif" width="720" alt="OC-Notch demo" />
</p> -->

---

## The Problem

You're deep in flow. Your AI agent is running — writing code, refactoring modules, spinning up tests. Then it needs permission to run a shell command. Or it finishes a task. Or it has a question.

**You don't notice.** It's sitting there, blocked, waiting in a terminal tab you haven't looked at in 10 minutes. Time wasted. Flow broken.

## The Fix

OC-Notch hugs your MacBook's notch and watches your OpenCode sessions in real-time. Permissions pop up instantly. Completions celebrate. Questions get answered. All without leaving your editor.

**Zero context switches. Zero missed prompts. Zero wasted minutes.**

---

## ✨ Features

### 🎮 Pixel Avatar Companion
A procedurally generated pixel-art character lives next to your notch. It **breathes** when idle, **thinks** when your agent is working, **alerts** when permissions are needed, and **dances** when tasks complete. It's your agent's face.

### ⚡ Instant Permission Handling
Agent needs to run `rm -rf node_modules`? The notch expands with a Dynamic Island–style animation showing exactly what's requested. **⌘Y** to allow, **⌘A** for always, **⌘N** to reject. Sub-second response times — your agent never waits.

### ❓ Interactive Question Prompts
When your agent asks questions (single-select, multi-select, or free-text), they surface directly in the notch. Answer with keyboard shortcuts or click through options. Multi-step question flows with back/forward navigation.

### 🎉 Task Completion Notifications
See the moment your agent finishes — with a summary of what changed, files modified, lines added/removed. One-click **Open** button jumps straight to the terminal session.

### 📊 Session Dashboard
Click the notch to see all active OpenCode sessions at a glance. Session status, project directories, activity indicators — everything in a compact dropdown.

### 🎨 Dynamic Island Design Language
Inspired by iPhone's Dynamic Island: fluid spring animations, blur transitions, dark pill UI that melts into the notch hardware. Feels native because it is.

---

## Quick Start

### Install (Recommended)

1. Download the latest `.zip` from [**Releases**](../../releases)
2. Drag **OC-Notch.app** to `/Applications`
3. Open it — signed and notarized by Apple, no Gatekeeper hassle

### Build from Source

```bash
brew install xcodegen
cd OC-Notch
xcodegen generate
open OC-Notch.xcodeproj
# ⌘R to build & run
```

### Use It

1. Start [OpenCode](https://github.com/sst/opencode) in any terminal
2. Launch OC-Notch — it auto-discovers running instances via process scanning
3. Hover the notch to peek at status, click to expand the dashboard
4. Handle permissions & questions directly from the notch with keyboard shortcuts

---

## Keyboard Shortcuts

| Action | Shortcut |
|---|---|
| Allow permission (once) | `⌘Y` |
| Allow permission (always) | `⌘A` |
| Reject permission | `⌘N` |
| Select option 1–9 | `⌘1` – `⌘9` |
| Submit multi-select | `⌘↵` |

---

## How It Works

```
┌─────────────────────────────────────────────┐
│                  MacBook Notch               │
│   [Pixel Avatar]  ▓▓▓▓▓▓▓▓  [Session Count] │
│                                              │
│   Hover → peek  •  Click → expand dropdown   │
│                                              │
│   ┌──────────────────────────────────────┐   │
│   │  Permission / Question / Completion  │   │
│   │  (expands with spring animation)     │   │
│   └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘

OpenCode Process ──→ SSE Stream ──→ OC-Notch
                ──→ HTTP API   ──→ (permissions, questions)
                ──→ SQLite DB  ──→ (session history)
```

OC-Notch discovers OpenCode instances by scanning running processes, connects via **Server-Sent Events** for real-time updates, reads session data from **SQLite**, and responds to permissions/questions through the **HTTP API**. All local. No cloud. No telemetry.

### Authenticated OpenCode servers (optional)

If you run OpenCode with `OPENCODE_SERVER_PASSWORD` set, OC-Notch will pick it up and send `Authorization: Bearer …` on every request. Because macOS GUI apps launched from the Dock don't inherit `~/.zshrc`, set the var so launchd sees it:

```bash
launchctl setenv OPENCODE_SERVER_PASSWORD <your-password>
```

Then relaunch OC-Notch. To unset: `launchctl unsetenv OPENCODE_SERVER_PASSWORD`.

---

## Tech Stack

| | |
|---|---|
| **Language** | Swift 6 with strict concurrency |
| **UI** | SwiftUI + SpriteKit (avatar) |
| **Window** | AppKit `NSPanel` overlay around the hardware notch |
| **Networking** | Native `URLSession` SSE client |
| **Storage** | Direct SQLite reader (no ORM overhead) |
| **Build** | XcodeGen + Makefile release pipeline |
| **Signing** | Apple notarized & stapled |

---

## Release (Maintainers)

```bash
# 1. Copy the local config template and fill in your Apple Developer signing values
cp local.mk.example local.mk
# Edit local.mk with your TEAM_ID, DEVELOPER_NAME, etc.

# 2. Store notarization credentials in Keychain (one-time, see local.mk.example)

# 3. Full pipeline: clean → build → sign → notarize → staple → zip
make release
```

---

## Contributing

PRs welcome. The codebase is organized by feature:

```
OC-Notch/Sources/
├── App/           # App delegate, entry point
├── Avatar/        # SpriteKit pixel avatar + procedural generation
├── Models/        # Data models (sessions, permissions, events)
├── Monitor/       # SSE client, SQLite reader, process scanner
├── Panel/         # NSPanel overlay (notch window management)
├── Utilities/     # Terminal launcher, screen extensions
└── Views/         # SwiftUI views (notch shell, dropdowns, prompts)
```

---

## Acknowledgments

- [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit) — blur transition design inspiration
- [OpenCode](https://github.com/sst/opencode) — the AI coding agent this project is built for

---

## License

[MIT](LICENSE) — do whatever you want with it.
