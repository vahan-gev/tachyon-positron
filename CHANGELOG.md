# Changelog

## 0.3.1

- CLI output follows standard conventions: `error:` / `warning:` diagnostics on
  stderr, a structured `USAGE` / `COMMANDS` / `PACK OPTIONS` help block, and
  plain ASCII throughout. Internal steps (file copies, `codesign`) run quietly
  instead of leaking tool chatter, so `pack` reports only what it bundled.
- `positron build` / `run` / `pack` now report a clear diagnostic when run
  outside a project.

## 0.3.0

- **`positron` CLI** (`cli/`, written in Tachyon) so you don't need shell
  scripts:
  - `positron new <name> [--node]` — scaffold an app (HTML, or a Node-backed
    template with a `server.js`).
  - `positron build` — compile the current app (release).
  - `positron run` — build, then open the app window.
  - `positron pack [--name --sign --icon --out]` — build a signed macOS `.app`,
    auto-bundling `server.js` / `web` and a `node` runtime when present.
  Uses only Tachyon built-ins (`shell`, `args`, file I/O) — no external deps.

## 0.2.1

- Windows packager now embeds `-Icon` into the `.exe` via `rcedit` (when it's on
  PATH), instead of only copying the `.ico` alongside — so the executable
  actually shows the icon. Falls back to a warning if `rcedit` is absent. (The
  macOS and Linux packagers already applied icons to the bundle.)

## 0.2.0

- Cross-platform packaging: `tools/pack-linux.sh` (AppDir → `.AppImage`, or a
  `.tar.gz` fallback) and `tools/pack-windows.ps1` (self-contained folder +
  `.zip`), alongside the existing `tools/pack-macos.sh`. All share the same
  flags and can bundle the `node` runtime + web assets.
- Code signing: `--sign` for `pack-macos.sh` (`codesign`, incl. ad-hoc `-`) and
  `-Sign` for `pack-windows.ps1` (`signtool`). macOS signing is verified;
  notarization steps are documented in the script.

## 0.1.0

Initial release.

- Native window hosting the system webview (`WKWebView` on macOS).
- `pwInit` / `pwLoadURL` / `pwLoadHTML` / `pwTitle` / `pwEval` / `pwRun` /
  `pwQuit` / `pwDevTools`.
- Sidecar process management — `pwSpawn` / `pwStop`, each child in its own
  process group and terminated when the app exits; `pwWaitPort` blocks until a
  server is listening. This is what lets a real Node.js/Next/Express backend
  run behind the window (not just static HTML/CSS).
- `pwServe` — one-call spawn-a-server + wait + show + run.
- `pwResourceDir` for locating bundled assets.
- `tools/pack-macos.sh` — package into a standalone `.app`, optionally bundling
  the `node` runtime and web assets.
- Backends for all three desktop platforms: macOS (`WKWebView`), Linux
  (WebKitGTK), Windows (Edge WebView2). macOS is verified end-to-end; the Linux
  and Windows backends are written against their platform APIs but not yet
  compile-tested on-target.
