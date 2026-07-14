#!/usr/bin/env bash
# Build and run the Positron demo. Run from this directory so `node server.js`
# resolves relative to the working directory.
set -euo pipefail
cd "$(dirname "$0")"

TACHYON="${TACHYON:-}"
if [ -z "$TACHYON" ]; then
  if [ -x "$PWD/../../../../tachyon/bin/tachyon" ]; then TACHYON="$PWD/../../../../tachyon/bin/tachyon";
  elif command -v tachyon >/dev/null 2>&1; then TACHYON="$(command -v tachyon)";
  else echo "tachyon compiler not found; set TACHYON=/path/to/tachyon" >&2; exit 1; fi
fi

"$TACHYON" build --release
exec ./target/release/hello
