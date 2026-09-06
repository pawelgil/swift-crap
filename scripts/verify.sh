#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift build --build-tests
swift test --skip-build
SWIFT_CRAP_BINARY="$(swift build --show-bin-path)/swift-crap" node --test Tests/E2ETests/*.test.mjs
swift build -c release
