#!/bin/bash
# Runs the providers characterization suite (Tests/ProvidersTests.swift): the
# native API providers (DeepSeek, Meta, Z.ai) and the file tools they share.
#
#   scripts/test_providers.sh
#
# Harness style the repo used before the four-layer reorg: compile the source
# closure plus the test file directly with swiftc and the Swift Testing
# framework, then run the binary. No test target and no app launch needed;
# access control is disabled so tests can reach internal symbols.
#
# Add a file to the SOURCES list when a test needs it, keeping the list ordered
# so the compile error points at the next file to add.
set -euo pipefail
cd "$(dirname "$0")/.."
DEVELOPER_DIR_PATH="$(xcode-select -p)"
FRAMEWORKS="$DEVELOPER_DIR_PATH/Platforms/MacOSX.platform/Developer/Library/Frameworks"
MACROS="$DEVELOPER_DIR_PATH/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib"
mkdir -p build.noindex

SOURCES=(
  # Core/Support
  DroppyCode/Core/Support/JSONValue.swift
  DroppyCode/Core/Support/Coding.swift
  DroppyCode/Core/Support/Shell.swift
  DroppyCode/Core/Support/StdioProcess.swift
  DroppyCode/Core/Support/StdioFramer.swift
  DroppyCode/Core/Support/JSONRPC.swift
  DroppyCode/Core/Support/RecentCache.swift
  DroppyCode/Core/Support/CaptureRun.swift
  DroppyCode/Core/Support/Text.swift
  # Core/Models
  DroppyCode/Core/Models/Provider.swift
  DroppyCode/Core/Models/ProviderSettings.swift
  DroppyCode/Core/Models/Timeline.swift
  DroppyCode/Core/Models/FileChangeSummary.swift
  DroppyCode/Core/Models/Requests.swift
  DroppyCode/Core/Models/HydraDelegationStream.swift
  DroppyCode/Core/Models/Hydra.swift
  DroppyCode/Core/Models/Library.swift
  DroppyCode/Core/Models/MCP.swift
  DroppyCode/Core/Models/MCPCatalog.swift
  # Services/Providers
  DroppyCode/Services/Providers/ProviderSession.swift
  DroppyCode/Services/Providers/NativeFileTools.swift
  DroppyCode/Services/Providers/DeepSeekSession.swift
  DroppyCode/Services/Providers/DeepSeekAPI.swift
  DroppyCode/Services/Providers/DeepSeekKeychain.swift
  DroppyCode/Services/Providers/ZaiSession.swift
  DroppyCode/Services/Providers/ZaiAPI.swift
  DroppyCode/Services/Providers/ZaiKeychain.swift
  DroppyCode/Services/Providers/MetaSession.swift
  DroppyCode/Services/Providers/MetaAPI.swift
  DroppyCode/Services/Providers/MetaKeychain.swift
  DroppyCode/Services/Providers/ProviderRegistry.swift
  DroppyCode/Services/Providers/ProviderCredits.swift
  DroppyCode/Services/Providers/CommandCodeAPI.swift
  DroppyCode/Services/Providers/PlanLimits.swift
  DroppyCode/Services/Providers/UsageLimitSignal.swift
  DroppyCode/Services/Providers/CopilotSession.swift
  DroppyCode/Services/Providers/CodexSession.swift
  DroppyCode/Services/Providers/AntigravitySession.swift
  DroppyCode/Services/Providers/ACPSession.swift
  DroppyCode/Services/Providers/ClaudeSession.swift
  DroppyCode/Services/Providers/PiCLI.swift
  DroppyCode/Services/Providers/PiSession.swift
  # Services/MCP (ProviderRegistry and the sessions reference MCPHub)
  DroppyCode/Services/MCP/MCPHub.swift
  DroppyCode/Services/MCP/MCPProviderConfig.swift
  DroppyCode/Services/MCP/MCPSessionOverrides.swift
  DroppyCode/Services/MCP/MCPBridgeSource.swift
  DroppyCode/Services/MCP/MCPProxy.swift
  DroppyCode/Services/MCP/MCPOAuth.swift
  DroppyCode/Services/MCP/MCPKeychain.swift
  DroppyCode/Services/MCP/MCPProbe.swift
  DroppyCode/Services/MCP/MCPExternalSync.swift
  DroppyCode/Services/MCP/MCPStore.swift
  # Services/Store
  DroppyCode/Services/Store/TokenLedger.swift
  DroppyCode/Services/Store/Storage.swift
)

xcrun swiftc -swift-version 6 -O -parse-as-library -target arm64-apple-macos26.0 \
  -Xfrontend -disable-access-control \
  -F "$FRAMEWORKS" -framework Testing \
  -load-plugin-library "$MACROS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  "${SOURCES[@]}" Tests/ProvidersTests.swift Tests/ProvidersTestMain.swift \
  -o build.noindex/providers-tests

build.noindex/providers-tests "$@"
