#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir=${1:-"$project_dir/dist"}
build_dir="$project_dir/.build/app-release"
app="$output_dir/Span.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$project_dir/Resources/Info.plist")
dmg="$output_dir/Span-$version.dmg"
zip="$output_dir/Span-$version-macOS.zip"

mkdir -p "$output_dir" "$build_dir/module-cache" "$build_dir/clang-cache"
rm -rf "$app" "$dmg" "$zip"

export SWIFT_MODULECACHE_PATH="$build_dir/module-cache"
export CLANG_MODULE_CACHE_PATH="$build_dir/clang-cache"
core_sources="$project_dir/Sources/SummitCore/Attendee.swift $project_dir/Sources/SummitCore/AXClient.swift $project_dir/Sources/SummitCore/DirectoryScan.swift $project_dir/Sources/SummitCore/CSV.swift $project_dir/Sources/SummitCore/NetworkMatcher.swift"
app_sources="$project_dir/Sources/SummitNetworkApp/Brand.swift $project_dir/Sources/SummitNetworkApp/AppModel.swift $project_dir/Sources/SummitNetworkApp/ConnectionsFile.swift $project_dir/Sources/SummitNetworkApp/ContentView.swift $project_dir/Sources/SummitNetworkApp/SessionStore.swift $project_dir/Sources/SummitNetworkApp/SummitNetworkApp.swift"

build_arch() {
  architecture=$1
  swiftc -O -target "$architecture-apple-macosx13.0" \
    $core_sources $app_sources \
    -framework AppKit -framework ApplicationServices -framework SwiftUI -framework UniformTypeIdentifiers \
    -o "$build_dir/SummitNetwork-$architecture"
}

build_arch arm64
build_arch x86_64
lipo -create "$build_dir/SummitNetwork-arm64" "$build_dir/SummitNetwork-x86_64" -output "$build_dir/SummitNetwork"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$build_dir/SummitNetwork" "$app/Contents/MacOS/SummitNetwork"
cp "$project_dir/Resources/Info.plist" "$app/Contents/Info.plist"
# Use the supplied macOS icon unchanged; do not regenerate its representations.
cp "$project_dir/Assets/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
cp "$project_dir/Assets/Span-Icon.png" "$app/Contents/Resources/Span-Icon.png"
chmod +x "$app/Contents/MacOS/SummitNetwork"
xattr -cr "$app"

if [ -n "${SIGNING_IDENTITY:-}" ]; then
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$app"
else
  codesign --force --deep --sign - "$app"
fi
codesign --verify --deep --strict "$app"

stage=$(mktemp -d "${TMPDIR:-/tmp}/summit-network-dmg.XXXXXX")
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/Span.app"
ln -s /Applications "$stage/Applications"
if hdiutil create -volname "Span" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null; then
  if [ -n "${SIGNING_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$dmg"
    codesign --verify --strict "$dmg"
  fi
  echo "Built $dmg"
else
  if [ "${REQUIRE_DMG:-0}" = "1" ]; then exit 1; fi
  xattr -cr "$app"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
  echo "Disk images are unavailable in this environment; built $zip instead."
fi
