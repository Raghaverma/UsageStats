#!/usr/bin/env bash
set -euo pipefail

if xcrun --find xctest >/dev/null 2>&1; then
  echo "Swift test toolchain is ready: $(xcode-select -p)"
  exit 0
fi

if [ -d /Applications/Xcode.app/Contents/Developer ]; then
  cat <<'EOF'
The active developer directory is Command Line Tools, which does not include XCTest.
Run tests with:
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
Or switch globally with:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
EOF
  exit 1
fi

echo "XCTest is unavailable and Xcode.app was not found."
exit 1
