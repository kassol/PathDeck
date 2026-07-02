# PathDeck

A Finder-first file workbench for macOS — browse like Finder, and grow a real terminal in place when you need one.

[![CI](https://github.com/kassol/PathDeck/actions/workflows/ci.yml/badge.svg)](https://github.com/kassol/PathDeck/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/platform-macOS%2026.5%2B%20(Apple%20Silicon)-lightgrey)

> **Status: under active development.** No binary releases yet — build from source (see below). Interfaces and behavior change between sprints.

## What is PathDeck?

Most file managers make you leave for a terminal; most terminals make you leave for a file manager. PathDeck keeps both in one window and keeps them in sync:

1. **A Finder-like file workbench** — browse, preview, search, and navigate with the file-first mental model you already have.
2. **A real embedded terminal** — powered by [libghostty](https://github.com/ghostty-org/ghostty), not a fake shell wrapper. Real PTY, real scrollback, real performance.
3. **A context bridge between the two** — `cd` in the terminal and the file list follows; navigate the file list and new terminals open right there.

## Features

- **Native window tabs** — every workspace is a real `NSWindow` tab: drag out, merge, Mission Control, `⌘1..9` all work as macOS intends
- **In-place folder expansion** — expand directories inline without losing your place
- **Multiple terminal tabs per workspace** — with drag-to-reorder, horizontal or vertical tab bars
- **Bidirectional cwd sync** — the file view and terminal share working-directory context both ways
- **6 built-in terminal themes** — with hot reload: theme, font size, cursor, and copy-on-select apply to live terminals without losing scrollback
- **Live file-system awareness** — FSEvents keeps the list fresh as files change under you
- **System integration** — `pathdeck://` URL scheme, Finder Services, "Open With", and a CLI entry point
- **Localized** — English and Simplified Chinese

## Requirements

- macOS 26.5 or later
- Apple Silicon (arm64)
- Xcode 26.5+ (to build)

## Build from source

```bash
git clone https://github.com/kassol/PathDeck.git
cd PathDeck
open PathDeck.xcodeproj   # then ⌘R in Xcode
```

Or from the command line:

```bash
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck -configuration Debug build
```

## Non-goals

PathDeck stays a file workbench. It is not a coding IDE, not cross-platform, not Electron, and it deliberately avoids exposing Git/branch mental models to the user.

## Contributing

Bug reports and feature requests are welcome — please [open an issue](https://github.com/kassol/PathDeck/issues). If you'd like to contribute code, read [CONTRIBUTING.md](CONTRIBUTING.md) first and open an issue before starting a PR.

## Acknowledgments

- [Ghostty](https://github.com/ghostty-org/ghostty) by Mitchell Hashimoto and contributors — PathDeck embeds libghostty for its terminal (MIT, see [vendor/GHOSTTY-LICENSE](vendor/GHOSTTY-LICENSE))

## License

[MIT](LICENSE)
