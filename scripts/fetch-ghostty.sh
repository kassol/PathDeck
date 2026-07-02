#!/bin/bash
# Fetches the prebuilt GhosttyKit.xcframework into vendor/.
# The binary is intentionally not in git (see AGENTS.md); it is stored as a
# release asset on the deps/ghostty-* prerelease tag.
set -euo pipefail

TAG="deps/ghostty-20260613"
ASSET="GhosttyKit.xcframework.zip"
URL="https://github.com/kassol/PathDeck/releases/download/${TAG}/${ASSET}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/vendor"

if [ -d "${DEST}/GhosttyKit.xcframework" ]; then
  echo "vendor/GhosttyKit.xcframework already present — delete it to re-fetch."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "Downloading ${URL}"
curl -fL --retry 3 -o "${TMP}/${ASSET}" "${URL}"
ditto -x -k "${TMP}/${ASSET}" "${DEST}"

echo "Fetched vendor/GhosttyKit.xcframework (${TAG})."
