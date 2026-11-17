#!/bin/zsh
# Builds "Touchy.app" (no Xcode required, only Command Line Tools).
#   ./build.sh           -> build + sign in /tmp/TouchyBuild
#   ./build.sh install   -> build, sign, install to /Applications, reset stale TCC hash, and launch
set -euo pipefail
cd "$(dirname "$0")"

NAME="Touchy.app"
LEGACY_NAME="ProArt Touch.app"
BUNDLE_ID="com.beratclxn.touchy"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

# Never keep a .app bundle inside the iCloud-synced Desktop folder, because iCloud attaches
# com.apple.FinderInfo extended attributes that invalidate the code signature and confuse TCC/LaunchServices.
for candidate in "$NAME" "$LEGACY_NAME"; do
  if [[ -d "build/$candidate" ]]; then
    "$LSREGISTER" -u "$(pwd)/build/$candidate" 2>/dev/null || true
    rm -rf "build/$candidate"
  fi
done

STAGE="/tmp/TouchyBuild"
APP="$STAGE/$NAME"
rm -rf "$STAGE"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" build/ModuleCache

ARCH="$(uname -m)"
echo "▶︎ Compiling ($ARCH)…"
xcrun swiftc -O -swift-version 5 \
  -module-cache-path build/ModuleCache \
  -target "$ARCH-apple-macos13.0" \
  -framework AppKit -framework SwiftUI -framework IOKit -framework ApplicationServices -framework ServiceManagement \
  Sources/*.swift \
  -o "$APP/Contents/MacOS/Touchy"

cp Info.plist "$APP/Contents/Info.plist"
if [[ -f AppIcon.icns ]]; then
  cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

echo "▶︎ Signing (ad-hoc)…"
xattr -cr "$APP"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
codesign --verify --strict "$APP"

echo "✅ Built: $APP"

if [[ "${1:-}" == "install" ]]; then
  echo "▶︎ Installing to /Applications…"
  pkill -x ProArtTouch 2>/dev/null || true
  pkill -x Touchy 2>/dev/null || true
  if [[ -d "/Applications/$LEGACY_NAME" ]]; then
    "$LSREGISTER" -u "/Applications/$LEGACY_NAME" 2>/dev/null || true
    rm -rf "/Applications/$LEGACY_NAME"
  fi
  rm -rf "/Applications/$NAME"
  ditto --noextattr "$APP" "/Applications/$NAME"
  xattr -cr "/Applications/$NAME" 2>/dev/null || true
  codesign --verify --strict "/Applications/$NAME"
  "$LSREGISTER" -f "/Applications/$NAME" 2>/dev/null || true
  # Clear stale CDHash from TCC so macOS Accessibility matches the newly built binary
  tccutil reset All "$BUNDLE_ID" 2>/dev/null || true
  open "/Applications/$NAME"
  echo "✅ Installed and launched: /Applications/$NAME"
else
  echo "   To install: ./build.sh install"
fi
