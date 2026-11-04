#!/bin/bash
# Draws NX Builder's pages into PNG files in the folder given (default build/snapshots) without opening a window.
#   NXB_GAME=<game folder> picks the game the Build page shows; NXB_LIGHT=1 draws the light appearance;
#   -appLanguage en|nb|de|fr|es|pt-BR|ja|zh-Hans picks the language.
set -euo pipefail
cd "$(dirname "$0")"
OUT="build/snapshots"
if [[ $# -gt 0 && "$1" != -* ]]; then OUT="$1"; shift; fi
/bin/mkdir -p "${OUT}"
SOURCES=()
for f in Sources/*.swift; do [[ "$f" == Sources/App.swift ]] || SOURCES+=("$f"); done
/usr/bin/swiftc -swift-version 6 -target arm64-apple-macos15.0 "${SOURCES[@]}" Tools/Snapshot/main.swift -o build/snapshot
build/snapshot "${OUT}" "$@"
