#!/usr/bin/env bash
# pack-linux.sh — wrap a compiled Positron program into a portable Linux app:
# an AppDir (optionally bundling `node` and web assets), turned into a
# single-file .AppImage if `appimagetool` is available, otherwise a .tar.gz.
# Run this on Linux (that's where you build the binary).
#
# Usage:
#   pack-linux.sh --bin PATH --name "App Name" [options]
#
#   --bin PATH        the compiled Tachyon executable (required)
#   --name NAME       app display name (required)
#   --resources PATH  copy PATH into the AppDir (repeatable); the app runs with
#                     its working dir set there, so bundled assets resolve as-is
#   --node            bundle the current `node` into the AppDir (self-contained)
#   --icon FILE.png   app icon (a placeholder is generated if omitted)
#   --categories STR  .desktop Categories (default: Utility;)
#   --out DIR         output directory (default: current directory)
#
# The generated AppRun puts the bundled node on PATH and cd's into the payload
# dir before exec'ing the program, matching development behavior.
set -euo pipefail

BIN="" NAME="" ICON="" OUT="." CATEGORIES="Utility;"
NODE=0
RESOURCES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --bin) BIN="$2"; shift 2;;
    --name) NAME="$2"; shift 2;;
    --resources) RESOURCES+=("$2"); shift 2;;
    --node) NODE=1; shift;;
    --icon) ICON="$2"; shift 2;;
    --categories) CATEGORIES="$2"; shift 2;;
    --out) OUT="$2"; shift 2;;
    *) echo "unknown option: $1" >&2; exit 1;;
  esac
done

[ -n "$BIN" ]  || { echo "--bin is required" >&2; exit 1; }
[ -n "$NAME" ] || { echo "--name is required" >&2; exit 1; }
[ -f "$BIN" ]  || { echo "binary not found: $BIN" >&2; exit 1; }

slug="$(echo "$NAME" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')"
APPDIR="$OUT/$slug.AppDir"
echo "==> building $APPDIR"
rm -rf "$APPDIR"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/payload"

# real executable + resources live in payload/; AppRun sets cwd there
cp "$BIN" "$APPDIR/usr/bin/$slug"
chmod +x "$APPDIR/usr/bin/$slug"

for r in "${RESOURCES[@]:-}"; do
  [ -n "$r" ] || continue
  echo "   + resource $r"
  cp -R "$r" "$APPDIR/payload/"
done

if [ "$NODE" = "1" ]; then
  NODEBIN="$(command -v node || true)"
  [ -n "$NODEBIN" ] || { echo "--node given but no node on PATH" >&2; exit 1; }
  mkdir -p "$APPDIR/payload/bin"
  cp "$NODEBIN" "$APPDIR/payload/bin/node"
  echo "   + bundled node ($("$NODEBIN" --version))"
fi

# icon (256x256 png). Generate a 1x1 placeholder if none given.
if [ -n "$ICON" ]; then
  cp "$ICON" "$APPDIR/$slug.png"
else
  # minimal valid 1x1 PNG
  printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc```\x00\x00\x00\x04\x00\x01\xf6\x178U\x00\x00\x00\x00IEND\xaeB`\x82' \
    > "$APPDIR/$slug.png"
fi
cp "$APPDIR/$slug.png" "$APPDIR/.DirIcon"

# .desktop entry
cat > "$APPDIR/$slug.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=$NAME
Exec=$slug
Icon=$slug
Categories=$CATEGORIES
Terminal=false
DESKTOP

# AppRun launcher
cat > "$APPDIR/AppRun" <<APPRUN
#!/bin/bash
HERE="\$(dirname "\$(readlink -f "\$0")")"
export PATH="\$HERE/payload/bin:\$PATH"
cd "\$HERE/payload" 2>/dev/null || true
exec "\$HERE/usr/bin/$slug" "\$@"
APPRUN
chmod +x "$APPDIR/AppRun"

# build the AppImage if the tool is available, else fall back to a tarball
if command -v appimagetool >/dev/null 2>&1; then
  echo "==> appimagetool -> $OUT/$NAME.AppImage"
  ARCH="$(uname -m)" appimagetool "$APPDIR" "$OUT/$NAME.AppImage"
  echo "==> done: $OUT/$NAME.AppImage"
else
  echo "==> appimagetool not found; producing a tarball instead"
  tar -C "$OUT" -czf "$OUT/$slug.tar.gz" "$(basename "$APPDIR")"
  echo "==> done: $OUT/$slug.tar.gz"
  echo "   (run ./$slug.AppDir/AppRun, or install appimagetool to get a .AppImage)"
fi
