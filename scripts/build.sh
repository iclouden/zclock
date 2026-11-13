#!/bin/zsh
set -euo pipefail

repo_dir="${0:A:h:h}"
app_path="${1:-$repo_dir/dist/ZClock.app}"
contents="$app_path/Contents"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"

mkdir -p "$contents/MacOS" "$contents/Resources"
clang -fobjc-arc -O2 -isysroot "$sdk_path" -mmacosx-version-min=13.0 \
  -framework AppKit -framework ServiceManagement \
  "$repo_dir/Sources/ZClock/main.m" \
  -o "$contents/MacOS/ZClock"
cp "$repo_dir/Resources/Info.plist" "$contents/Info.plist"
cp "$repo_dir/Resources/ZClock.icns" "$contents/Resources/ZClock.icns"
codesign --force --sign - "$app_path"
print -r -- "$app_path"
