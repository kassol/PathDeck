# Contributing to PathDeck

Thanks for your interest. PathDeck is a personal project under active development, so the contribution surface is deliberately small.

## Reporting bugs and requesting features

Open an issue using the provided templates. For bugs, include your macOS version, the commit you built from, and reproduction steps — the templates will prompt you.

## Contributing code

**Open an issue and get agreement before writing a PR.** The roadmap moves in sprints and unsolicited PRs may not fit the current direction; a short discussion first saves everyone time.

## Building

- macOS 26.5+, Apple Silicon, Xcode 26.5+

```bash
# One-time: fetch the prebuilt libghostty binary (not in git)
./scripts/fetch-ghostty.sh

# Build
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck -configuration Debug build

# Unit tests (skips UI tests)
xcodebuild -project PathDeck.xcodeproj -scheme PathDeck \
  -only-testing:PathDeckTests -destination 'platform=macOS,arch=arm64' test
```

If tests fail to launch from the command line, enable Developer Mode once (`sudo /usr/sbin/DevToolsSecurity -enable`) or run them in Xcode with ⌘U.

## Repository conventions

- Internal engineering docs (`AGENTS.md`, `docs/`) are written in Chinese; they are the source of truth for architecture and per-module conventions. Start with the root `AGENTS.md`.
- New code paths need unit tests (use temporary directories for file-system operations). UI tests are not part of the CI gate.
- Commit messages are in English.
