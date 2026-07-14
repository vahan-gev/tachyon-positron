# Positron

Run web apps — including a **Node.js backend**, not just static HTML/CSS —
inside a **native window**, and package them into a standalone macOS `.app`.

Positron is the Tachyon answer to Electron. Instead of bundling a whole
browser, it hosts the system webview (`WKWebView` on macOS) in a native window,
and manages your app's server process as a sidecar: it starts your Node/Next/
Express server, waits for its port, then points the window at `localhost`. When
the window closes, the server (and its child processes) are cleaned up.

```tachyon
import positron.app;

function main(): void {
    // start a Node server, wait for it, and show it in a native window
    pwServe("My App", 1100, 780, "cd web && npm start", "127.0.0.1", 3000, 30000);
}
```

## Install

```toml
# Tachyon.toml
[package]
name = "my-app"
deps = ["git+https://github.com/vahan-gev/tachyon-positron#v0.1.0"]
```

## API

```tachyon
import positron.app;

// window
pwInit(title, width, height)     // create the window + webview
pwLoadURL(url)                   // load a URL
pwLoadHTML(html)                 // load an HTML string
pwTitle(title)                   // set the window title
pwEval(js)                       // run JavaScript in the page
pwDevTools()                     // enable the Web Inspector (call before pwInit)
pwRun()                          // enter the event loop (blocks until closed)
pwQuit()

// sidecar processes (your server)
pwSpawn(cmd): int                // start `cmd` via /bin/sh; returns a pid
pwStop(pid)                      // terminate it (and its process group)
pwWaitPort(host, port, ms): bool // block until the server is listening
pwResourceDir(): string          // dir of the running executable (bundled assets)

// convenience: spawn a server, wait for it, show it, run until closed
pwServe(title, w, h, cmd, host, port, timeoutMs): bool
```

Sidecar processes run in their own process group and are terminated when the
app exits, so an `npm start` → `node` subtree doesn't leak.

## Packaging (macOS)

`tools/pack-macos.sh` wraps a compiled program into a double-clickable `.app`,
optionally bundling the `node` runtime and your web assets so the result is
self-contained:

```bash
tachyon build --release

tools/pack-macos.sh \
  --bin target/release/my-app \
  --name "My App" \
  --resources web \
  --resources server.js \
  --node                      # bundle the current `node` into the app
```

The generated launcher puts the bundled `node` on `PATH` and sets the working
directory to `Contents/Resources`, so bundled `node` and relative asset paths
resolve exactly as they do in development. The `Info.plist` permits HTTP to
localhost (App Transport Security) so a local server loads inside the app.

## Example

`examples/hello` starts a tiny Node HTTP server and shows it in a window:

```bash
cd examples/hello && ./run.sh
```

## Platforms

- **macOS** — full support (Cocoa + WebKit / `WKWebView`).
- **Linux / Windows** — the sidecar-process and wait-for-port pieces work, but
  the native window is macOS-only in this release. WebKitGTK (Linux) and
  WebView2 (Windows) backends are planned.

## License

MIT
