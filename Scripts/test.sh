#!/usr/bin/env bash
# Runs the DiskSage test suite (Swift Testing).
#
# The tests use `import Testing`, which ships inside the toolchain. With only
# the Command Line Tools installed (no full Xcode), `swift test` doesn't add
# Testing.framework's search/runtime paths automatically, so we locate them and
# pass them through. With full Xcode these dirs simply won't match and are
# skipped — `swift test` already works there.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DEV="$(xcode-select -p 2>/dev/null || echo /Library/Developer/CommandLineTools)"

ARGS=()
FW="$DEV/Library/Developer/Frameworks"
if [ -d "$FW/Testing.framework" ]; then
    ARGS+=(-Xswiftc -F -Xswiftc "$FW" -Xlinker -F -Xlinker "$FW" -Xlinker -rpath -Xlinker "$FW")
fi
LIB="$DEV/Library/Developer/usr/lib"
if [ -f "$LIB/lib_TestingInterop.dylib" ]; then
    ARGS+=(-Xlinker -rpath -Xlinker "$LIB")
fi

echo "▸ swift test ${ARGS[*]:-}"
# ${ARGS[@]+...} keeps this safe under `set -u` on macOS's bash 3.2 when empty.
swift test ${ARGS[@]+"${ARGS[@]}"}
