#!/bin/sh
set -eu

swift build -c release
app="$(pwd)/WordSelection.app"
work="$(mktemp -d "$(pwd)/.WordSelection-build.XXXXXX")"
trap 'rm -rf "$work"' EXIT
newapp="$work/WordSelection.app"
mkdir -p "$work/AppIcon.iconset" "$newapp/Contents/MacOS" "$newapp/Contents/Resources"
swift Assets/generate-icon.swift "$work/AppIcon.iconset"
iconutil -c icns "$work/AppIcon.iconset" -o "$newapp/Contents/Resources/WordSelection.icns"
cp .build/release/WordSelection "$newapp/Contents/MacOS/WordSelection"
cp Info.plist "$newapp/Contents/Info.plist"
codesign --force --sign - "$newapp"
if [ -d "$app" ]; then
    mv "$app" "$work/previous.app"
fi
mv "$newapp" "$app"
printf 'Built %s\n' "$app"
