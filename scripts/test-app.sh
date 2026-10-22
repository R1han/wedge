#!/bin/bash
# Generate the Xcode project and run the app unit tests (WedgeTests, hosted by Wedge.app).
# Pass through any extra `xcodebuild` args (e.g. -only-testing:WedgeTests/Name).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Wedge.xcodeproj -scheme Wedge -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData test "$@"
