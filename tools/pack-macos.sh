#!/usr/bin/env bash
# pack-macos.sh — wrap a compiled Positron program into a double-clickable
# macOS .app bundle, optionally bundling a `node` runtime and web assets so the
# app is self-contained.
#
# Usage:
#   pack-macos.sh --bin PATH --name "App Name" [options]
#
#   --bin PATH            the compiled Tachyon executable (required)
#   --name NAME           app display name (required)
#   --id ID               bundle identifier (default: com.positron.<slug>)
#   --resources PATH      copy PATH into Contents/Resources (repeatable);
#                         the app runs with its working dir set to Resources,
#                         so a bundled `server.js`, `web/`, etc. resolve as-is
#   --node                bundle the current `node` into Resources/bin (so the
#                         app can run Node without a system install)
#   --icon FILE.icns      app icon
#   --out DIR             output directory (default: current directory)
#
# The generated launcher puts Resources/bin on PATH and cd's into Resources
# before exec'ing the program, so bundled `node` and relative asset paths work
# the same as during development.
set -euo pipefail

BIN="" NAME="" ID="" ICON="" OUT="."
NODE=0
RESOURCES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --bin) BIN="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --id) ID="$2"; shift 2;;
    --resources) RESOURCES+=("$2"); shift 2;;
    --node) NODE=1; shift;;
    --icon) ICON="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    *) echo "unknown option: $1" >&2; exit 1;;
  esac
done

[ -n "$BIN" ]  || { echo "--bin is required" >&2; exit 1; }
[ -n "$NAME" ] || { echo "--name is required" >&2; exit 1; }
[ -f "$BIN" ]  || { echo "binary not found: $BIN" >&2; exit 1; }

slug="$(echo "$NAME" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"
[ -n "$ID" ] || ID="com.positron.$slug"

APP="$OUT/$NAME.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
echo "==> building $APP"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

# real executable + a launcher that fixes up PATH and working dir
cp "$BIN" "$MACOS/$NAME-bin"
chmod +x "$MACOS/$NAME-bin"

cat > "$MACOS/$NAME" <<LAUNCH
#!/bin/bash
DIR="\$(cd "\$(dirname "\$0")" && pwd)"
export PATH="\$DIR/../Resources/bin:\$PATH"
cd "\$DIR/../Resources" 2>/dev/null || true
exec "\$DIR/$NAME-bin" "\$@"
LAUNCH
chmod +x "$MACOS/$NAME"

# resources
for r in "${RESOURCES[@]:-}"; do
  [ -n "$r" ] || continue
  echo "   + resource $r"
  cp -R "$r" "$RES/"
done

# bundled node
if [ "$NODE" = "1" ]; then
  NODEBIN="$(command -v node || true)"
  [ -n "$NODEBIN" ] || { echo "--node given but no node on PATH" >&2; exit 1; }
  mkdir -p "$RES/bin"
  cp "$NODEBIN" "$RES/bin/node"
  echo "   + bundled node ($("$NODEBIN" --version))"
fi

# icon
ICONKEY=""
if [ -n "$ICON" ]; then
  cp "$ICON" "$RES/AppIcon.icns"
  ICONKEY="  <key>CFBundleIconFile</key>
  <string>AppIcon</string>"
fi

# Info.plist — allow http to localhost (ATS) so a local server loads in the app
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>$NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$NAME</string>
  <key>CFBundleExecutable</key>
  <string>$NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$ID</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>LSMinimumSystemVersion</key>
  <string>10.13</string>
$ICONKEY
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
  </dict>
</dict>
</plist>
PLIST

echo "==> done: $APP"
