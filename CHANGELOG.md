# Changelog

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
