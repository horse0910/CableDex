#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_DIR/build"
APP_DIR="$BUILD_DIR/CableDeX.app"
mkdir -p "$BUILD_DIR"
for TOOL_NAME in adb scrcpy scrcpy-server; do
  case "$TOOL_NAME" in
    adb) EXPECTED_HASH=1811e253b21b12cbfda7201ebaf86c10e7ddcb5c606a7a81f7c82b4c429c2d3b ;;
    scrcpy) EXPECTED_HASH=f4c205df0320209fe8fc836b8fb8bbe669703d9fab586e6038da45495945a17e ;;
    scrcpy-server) EXPECTED_HASH=764eb6f79811d5211fe9df341120882ba9994c7a61b897d7bf3fb662e53bc536 ;;
  esac
  ACTUAL_HASH="$(/usr/bin/shasum -a 256 "$PROJECT_DIR/Vendor/$TOOL_NAME")"
  ACTUAL_HASH="${ACTUAL_HASH%% *}"
  MANIFEST_HASH="$(/usr/bin/plutil -extract "files.$TOOL_NAME" raw -o - "$PROJECT_DIR/Resources/ToolManifest.json")"
  if [[ "$ACTUAL_HASH" != "$EXPECTED_HASH" || "$MANIFEST_HASH" != "$EXPECTED_HASH" ]]; then
    echo "Integrity check failed for $TOOL_NAME. Refusing to package." >&2; exit 1
  fi
done

# A fixed project-local output; never touches Applications, shell profiles, or global tools.
if [[ -L "$APP_DIR" ]]; then echo "Refusing to replace a symlink: $APP_DIR" >&2; exit 1; fi
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources/Tools"
/usr/bin/swiftc -O -swift-version 5 -target arm64-apple-macos13.0 \
  -module-cache-path "$BUILD_DIR/module-cache" \
  -framework AppKit -framework CryptoKit \
  "$PROJECT_DIR/Sources/Core.swift" "$PROJECT_DIR/Sources/Bridge.swift" \
  "$PROJECT_DIR/Sources/Transfers.swift" "$PROJECT_DIR/Sources/PhoneFileBrowser.swift" \
  "$PROJECT_DIR/Sources/SessionController.swift" "$PROJECT_DIR/Sources/App.swift" \
  -o "$APP_DIR/Contents/MacOS/CableDeX"
cp "$PROJECT_DIR"/Vendor/{adb,scrcpy,scrcpy-server,scrcpy.png,disconnected.png,LICENSE,scrcpy.1,SDL-LICENSE.txt,FFmpeg-COPYING.LGPLv2.1} "$APP_DIR/Contents/Resources/Tools/"
/bin/chmod 755 "$APP_DIR/Contents/Resources/Tools/adb" "$APP_DIR/Contents/Resources/Tools/scrcpy"
cp "$PROJECT_DIR/Resources/ToolManifest.json" "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/"
cp "$PROJECT_DIR/LICENSE" "$APP_DIR/Contents/Resources/CableDeX-LICENSE.txt"
if [[ -f "$PROJECT_DIR/THIRD_PARTY.md" ]]; then cp "$PROJECT_DIR/THIRD_PARTY.md" "$APP_DIR/Contents/Resources/"; fi
cp "$PROJECT_DIR/README.md" "$PROJECT_DIR/VALIDATION.md" "$PROJECT_DIR/SAFETY.md" "$APP_DIR/Contents/Resources/"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>CableDeX</string>
<key>CFBundleDisplayName</key><string>CableDeX</string>
<key>CFBundleIdentifier</key><string>com.cabledex.mac</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleExecutable</key><string>CableDeX</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
# The UI targets macOS 13; the bundled tools target macOS 11 or earlier.
/usr/bin/codesign --force --options runtime --timestamp=none --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
/usr/bin/ditto -c -k --keepParent "$APP_DIR" "$BUILD_DIR/CableDeX-AppleSilicon.zip"
(
  cd "$BUILD_DIR"
  /usr/bin/shasum -a 256 CableDeX-AppleSilicon.zip > SHA256SUMS.txt
)
printf 'Built %s\n' "$APP_DIR"
