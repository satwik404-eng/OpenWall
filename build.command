#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
destination="${1:-../OpenWall.app}"
mkdir -p "$destination/Contents/MacOS" "$destination/Contents/Resources" .build
arch_name="$(uname -m)"
xcrun swiftc -swift-version 5 -O -target "$arch_name-apple-macosx14.0" \
    -module-cache-path .build/module-cache \
    Sources/*.swift -o "$destination/Contents/MacOS/OpenWall" \
    -framework SwiftUI -framework AppKit -framework AVFoundation -framework AVKit \
    -framework IOKit -framework ServiceManagement -framework VideoToolbox -framework CoreImage
cp Resources/Info.plist "$destination/Contents/Info.plist"
cp THIRD-PARTY-NOTICES.md "$destination/Contents/Resources/THIRD-PARTY-NOTICES.md"
ditto ThirdParty "$destination/Contents/Resources/ThirdParty"
saver="$destination/Contents/Resources/OpenWall.saver"
mkdir -p "$saver/Contents/MacOS"
xcrun swiftc -swift-version 5 -O -emit-library -module-name OpenWallSaver \
    -target "$arch_name-apple-macosx14.0" -module-cache-path .build/module-cache \
    ScreenSaver/OpenWallSaver.swift -o "$saver/Contents/MacOS/OpenWallSaver" \
    -framework ScreenSaver -framework AppKit -framework AVFoundation -framework QuartzCore -framework IOKit
cp ScreenSaver/Info.plist "$saver/Contents/Info.plist"
xattr -dr com.apple.FinderInfo "$saver" 2>/dev/null || true
codesign --force --sign - "$saver"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$destination/Contents/Resources/AppIcon.icns"
fi
# Finder may attach folder metadata in cloud-synced locations; code signing
# rejects FinderInfo on an app bundle we just created.
xattr -dr com.apple.FinderInfo "$destination" 2>/dev/null || true
codesign --force --sign - "$destination"
echo "Built $destination"
