#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
build_dir="$project_dir/.build/workflow-checks"
mkdir -p "$build_dir/module-cache" "$build_dir/clang-cache"
export SWIFT_MODULECACHE_PATH="$build_dir/module-cache"
export CLANG_MODULE_CACHE_PATH="$build_dir/clang-cache"
swiftc -target arm64-apple-macosx13.0 \
  Sources/SummitCore/*.swift \
  Sources/SummitNetworkApp/AppModel.swift \
  Sources/SummitNetworkApp/ConnectionsFile.swift \
  Sources/SummitNetworkApp/SessionStore.swift \
  Tests/AppWorkflowChecks.swift \
  Tests/DirectoryScanChecks.swift \
  -framework AppKit -framework ApplicationServices \
  -o "$build_dir/AppWorkflowChecks"
"$build_dir/AppWorkflowChecks"
