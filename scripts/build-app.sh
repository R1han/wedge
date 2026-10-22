#!/bin/bash
# Generate the Xcode project from project.yml and build the Wedge menu-bar app.
# The app lands in build/DerivedData/Build/Products/Debug/Wedge.app (path printed at the end).
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
xcodebuild -project Wedge.xcodeproj -scheme Wedge -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData build
echo "Built: $PWD/build/DerivedData/Build/Products/Debug/Wedge.app"
