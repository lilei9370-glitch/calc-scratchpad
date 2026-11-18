#!/bin/zsh
set -eu
cd -- "${0:A:h}"
app="${1:-$PWD/dist/计算便笺.app}"
identity="${CODE_SIGN_IDENTITY:--}"
build=$(mktemp -d "${TMPDIR:-/tmp}/scratchpad-build.XXXXXXXX")
trap 'rm -rf -- "$build"' EXIT
bundle="$build/计算便笺.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cat > "$bundle/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.leizi.scratchpad</string>
    <key>CFBundleName</key><string>计算便笺</string>
    <key>CFBundleExecutable</key><string>Scratchpad</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.3</string>
    <key>CFBundleVersion</key><string>6</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>local.leizi.scratchpad.quote</string>
            <key>CFBundleURLSchemes</key><array><string>leizi-scratchpad</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST
cp Vendor/math.js Vendor/mathjs-LICENSE Vendor/mathjs-NOTICE "$bundle/Contents/Resources/"
mkdir -p "$build/AppIcon.iconset"
xcrun swift AppIcon.swift "$build/AppIcon.iconset"
iconutil -c icns -o "$bundle/Contents/Resources/AppIcon.icns" "$build/AppIcon.iconset"
xcrun swiftc -parse-as-library -O -target arm64-apple-macos14.0 Scratchpad.swift -o "$bundle/Contents/MacOS/Scratchpad"
sign=(--force --sign "$identity")
if [[ "$identity" != "-" ]]; then sign+=(--options runtime --timestamp); fi
codesign "${sign[@]}" "$bundle"
codesign --verify --strict "$bundle"
mkdir -p "${app:h}"
ditto "$bundle" "$app"
print -r -- "$app"
