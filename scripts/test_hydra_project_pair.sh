#!/bin/bash
# Builds and runs Tests/HydraProjectPairTests.swift against the model sources it needs.
# Same shape as scripts/test_composer.sh: swiftc with the Testing framework from Xcode.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVELOPER_DIR_PATH="$(xcode-select -p)"
FRAMEWORKS="$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform/Developer/Library/Frameworks"
MACROS="$DEVELOPER_DIR_PATH/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
mkdir -p build.noindex
xcrun swiftc -parse-as-library -F "$FRAMEWORKS" -framework Testing \
  -load-plugin-library "$MACROS" -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  DroppyCode/Models/Hydra.swift DroppyCode/Models/Provider.swift \
  DroppyCode/Support/Coding.swift DroppyCode/Support/JSONValue.swift DroppyCode/Support/Text.swift \
  DroppyCode/Models/Timeline.swift DroppyCode/Models/FileChangeSummary.swift DroppyCode/Git/DiffParser.swift \
  Tests/HydraProjectPairTests.swift -o build.noindex/hydra-project-pair-tests
build.noindex/hydra-project-pair-tests
