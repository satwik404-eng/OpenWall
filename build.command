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
    -framework IOKit -framework ServiceManagement
cp Resources/Info.plist "$destination/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
    cp Resources/AppIcon.icns "$destination/Contents/Resources/AppIcon.icns"
fi
# Finder may attach folder metadata in cloud-synced locations; code signing
# rejects FinderInfo on an app bundle we just created.
xattr -dr com.apple.FinderInfo "$destination" 2>/dev/null || true
codesign --force --sign - "$destination"
echo "Built $destination"
