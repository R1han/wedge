#!/bin/bash
# Run the Swift Testing suite. Under Command Line Tools (no Xcode) the testing
# framework needs explicit framework/rpath search paths; harmless when Xcode is present.
# Pass through any `swift test` args (e.g. --filter Name).
set -euo pipefail
D=/Library/Developer/CommandLineTools/Library/Developer
F="$D/Frameworks"
exec swift test \
  -Xswiftc -F -Xswiftc "$F" \
  -Xlinker -F -Xlinker "$F" \
  -Xlinker -rpath -Xlinker "$F" \
  -Xlinker -rpath -Xlinker "$D/usr/lib" \
  "$@"
