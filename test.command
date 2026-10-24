#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build
xcrun swiftc -swift-version 5 -target "$(uname -m)-apple-macosx14.0" \
    -module-cache-path .build/module-cache \
    Sources/Library.swift Sources/Engine.swift Sources/MotionCatalog.swift Sources/MotionArtwork.swift Sources/StoppedWallpaperStore.swift Sources/FullScreenDetector.swift Sources/Playlist.swift Sources/LockScreenMedia.swift Sources/NativeLockScreen.swift Sources/LockScreenSync.swift Tests/IntegrationTests.swift \
    -o .build/integration-tests -framework SwiftUI -framework AppKit \
    -framework AVFoundation -framework IOKit -framework ServiceManagement -framework VideoToolbox -framework CoreImage
test_directory="$(mktemp -d /tmp/openwall-test.XXXXXX)"
OPENWALL_DATA_DIR="$test_directory" .build/integration-tests
echo "Test fixtures saved to $test_directory"
