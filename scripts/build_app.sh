#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
output_dir=${1:-"$project_dir/dist"}
build_dir="$project_dir/.build/app-release"
app="$output_dir/Summit Network.app"
dmg="$output_dir/Summit-Network-0.2.0.dmg"
zip="$output_dir/Summit-Network-0.2.0-macOS.zip"

mkdir -p "$output_dir" "$build_dir/module-cache" "$build_dir/clang-cache"
rm -rf "$app" "$dmg" "$zip"

export SWIFT_MODULECACHE_PATH="$build_dir/module-cache"
export CLANG_MODULE_CACHE_PATH="$build_dir/clang-cache"
core_sources="$project_dir/Sources/SummitCore/Attendee.swift $project_dir/Sources/SummitCore/AXClient.swift $project_dir/Sources/SummitCore/CSV.swift $project_dir/Sources/SummitCore/NetworkMatcher.swift"
app_sources="$project_dir/Sources/SummitNetworkApp/AppModel.swift $project_dir/Sources/SummitNetworkApp/ConnectionsFile.swift $project_dir/Sources/SummitNetworkApp/ContentView.swift $project_dir/Sources/SummitNetworkApp/SessionStore.swift $project_dir/Sources/SummitNetworkApp/SummitNetworkApp.swift"

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

iconset="$build_dir/AppIcon.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
for specification in "16 icon_16x16.png" "32 icon_16x16@2x.png" "32 icon_32x32.png" "64 icon_32x32@2x.png" "128 icon_128x128.png" "256 icon_128x128@2x.png" "256 icon_256x256.png" "512 icon_256x256@2x.png" "512 icon_512x512.png" "1024 icon_512x512@2x.png"; do
  size=${specification%% *}
  filename=${specification#* }
  sips -z "$size" "$size" "$project_dir/Assets/AppIcon-1024.png" --out "$iconset/$filename" >/dev/null
done
python3 "$project_dir/scripts/make_icns.py" "$iconset" "$build_dir/AppIcon.icns"

mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$build_dir/SummitNetwork" "$app/Contents/MacOS/SummitNetwork"
cp "$project_dir/Resources/Info.plist" "$app/Contents/Info.plist"
cp "$build_dir/AppIcon.icns" "$app/Contents/Resources/AppIcon.icns"
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
ditto "$app" "$stage/Summit Network.app"
ln -s /Applications "$stage/Applications"
if hdiutil create -volname "Summit Network" -srcfolder "$stage" -ov -format UDZO "$dmg" >/dev/null; then
  echo "Built $dmg"
else
  if [ "${REQUIRE_DMG:-0}" = "1" ]; then exit 1; fi
  xattr -cr "$app"
  ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
  echo "Disk images are unavailable in this environment; built $zip instead."
fi
