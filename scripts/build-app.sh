#!/bin/bash
set -euo pipefail
native_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${FLOW_BUILD_DIR:-$native_dir/.build}"
output_dir="${FLOW_OUTPUT_DIR:-$native_dir/dist}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-${TMPDIR:-/tmp}/flowgoswift-swift-cache}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/flowgoswift-clang-cache}"
swift "$native_dir/scripts/build-icon.swift" "$native_dir"
swift build --package-path "$native_dir" --scratch-path "$build_dir" -c release --arch arm64 --disable-sandbox
bin_dir="$(swift build --package-path "$native_dir" --scratch-path "$build_dir" -c release --arch arm64 --disable-sandbox --show-bin-path)"
app_dir="$output_dir/FlowgoSwift.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$bin_dir/FlowgoSwift" "$app_dir/Contents/MacOS/FlowgoSwift.new"
mv -f "$app_dir/Contents/MacOS/FlowgoSwift.new" "$app_dir/Contents/MacOS/FlowgoSwift"
cp "$bin_dir/flow" "$output_dir/flow"
cp "$native_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$native_dir/Resources/AppIcon.icns" "$app_dir/Contents/Resources/AppIcon.icns"
cp "$native_dir/LICENSE" "$app_dir/Contents/Resources/LICENSE"
cp "$native_dir/README.md" "$app_dir/Contents/Resources/README.md"
ditto "$bin_dir/FlowgoSwift_FlowCore.bundle" "$app_dir/Contents/Resources/FlowgoSwift_FlowCore.bundle"
ditto "$bin_dir/FlowgoSwift_FlowgoSwift.bundle" "$app_dir/Contents/Resources/FlowgoSwift_FlowgoSwift.bundle"
ditto "$bin_dir/FlowgoSwift_FlowCore.bundle" "$output_dir/FlowgoSwift_FlowCore.bundle"
codesign --force --sign - "$app_dir"
codesign --force --sign - "$output_dir/flow"
architecture="$(lipo -archs "$app_dir/Contents/MacOS/FlowgoSwift")"
if [ "$architecture" != "arm64" ]; then
    echo "Unexpected architecture: $architecture" >&2
    exit 1
fi
codesign --verify --strict "$app_dir"
echo "Built $app_dir ($architecture)"
