#!/bin/bash
# Builds build/ActivityLogger.app using the Xcode Command Line Tools (no Xcode needed).
set -euo pipefail
cd "$(dirname "$0")"

APP="build/ActivityLogger.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

EXTRA_FLAGS=()
# Workaround for a Command Line Tools 16 bug: a stale module.modulemap next to
# bridging.modulemap redefines 'SwiftBridging' and breaks every SwiftUI build.
# A VFS overlay hides the stale file from the compiler without touching the system.
STALE=/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap
if [[ -f "$STALE" && -f "$(dirname "$STALE")/bridging.modulemap" ]]; then
    mkdir -p build/tmp
    : > build/tmp/empty.modulemap
    cat > build/tmp/overlay.yaml <<EOF
{ "version": 0, "case-sensitive": "false", "roots": [
  { "type": "file", "name": "$STALE", "external-contents": "$PWD/build/tmp/empty.modulemap" } ] }
EOF
    EXTRA_FLAGS=(-vfsoverlay build/tmp/overlay.yaml -Xcc -ivfsoverlay -Xcc build/tmp/overlay.yaml)
fi

swiftc -O -parse-as-library -swift-version 5 \
    -target arm64-apple-macos13.0 \
    "${EXTRA_FLAGS[@]}" \
    Sources/*.swift \
    -o "$APP/Contents/MacOS/ActivityLogger"

cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"

echo "Built $APP"
echo "Install:  cp -R $APP /Applications/ && open /Applications/ActivityLogger.app"
