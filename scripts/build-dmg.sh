#!/bin/bash
set -euo pipefail
native_dir="$(cd "$(dirname "$0")/.." && pwd)"
release_dir="$native_dir/build"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$native_dir/Info.plist")"
FLOW_OUTPUT_DIR="$release_dir" "$native_dir/scripts/build-app.sh"
staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/flowgoswift-dmg.XXXXXX")"
mount_dir="$staging_dir/mount"
mounted=0
trap 'if [ "$mounted" = 1 ]; then hdiutil detach "$mount_dir"; fi; rm -rf "$staging_dir"' EXIT
mkdir -p "$staging_dir/contents/.background"
ditto "$release_dir/FlowgoSwift.app" "$staging_dir/contents/FlowgoSwift.app"
ln -s /Applications "$staging_dir/contents/Applications"
swift "$native_dir/scripts/dmg-background.swift" "$staging_dir/contents/.background/background.png"
if [ ! -x "$release_dir/dmg-tools/bin/python3" ]; then
    python3 -m venv "$release_dir/dmg-tools"
fi
if ! "$release_dir/dmg-tools/bin/python3" -c 'import ds_store, mac_alias' 2>/dev/null; then
    "$release_dir/dmg-tools/bin/python3" -m pip install 'ds-store==1.3.1' 'mac-alias==2.2.2'
fi
dmg_name="FlowgoSwift-v$version-arm64.dmg"
dmg_path="$release_dir/$dmg_name"
hdiutil create -volname "FlowgoSwift" -fs HFS+ -srcfolder "$staging_dir/contents" -format UDRW "$staging_dir/writable.dmg"
hdiutil attach "$staging_dir/writable.dmg" -mountpoint "$mount_dir" -nobrowse
mounted=1
"$release_dir/dmg-tools/bin/python3" "$native_dir/scripts/dmg-layout.py" "$mount_dir"
hdiutil detach "$mount_dir"
mounted=0
hdiutil convert "$staging_dir/writable.dmg" -format UDZO -o "$dmg_path" -ov
hdiutil verify "$dmg_path"
(cd "$release_dir" && shasum -a 256 "$dmg_name") > "$dmg_path.sha256"
echo "Built $dmg_path"
