#!/bin/bash
# Runs NX Builder's headless checks (Tests/main.swift) against ~/nxnative. No window opens.
# NXB_DRAW=<folder> also draws the cards there as PNG files; -appLanguage english|norwegian picks the language.
set -euo pipefail
cd "$(dirname "$0")"
/bin/mkdir -p build
SOURCES=()
for f in Sources/*.swift; do [[ "$f" == Sources/App.swift ]] || SOURCES+=("$f"); done
/usr/bin/swiftc -swift-version 6 -target arm64-apple-macos15.0 "${SOURCES[@]}" Tests/main.swift -o build/tests
build/tests "$@"
