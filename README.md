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

## Packaging

Each platform has a packager under `tools/` that wraps a compiled program into
a distributable app, optionally bundling the `node` runtime and your web assets
so the result is self-contained. Run the packager on the platform you built the
binary on. They share the same flags (`--bin`, `--name`, `--resources`,
`--node`, `--icon`).

**macOS** → a double-clickable `.app`:

```bash
tachyon build --release
tools/pack-macos.sh \
  --bin target/release/my-app \
  --name "My App" \
  --resources web --resources server.js \
  --node \
  --sign -                    # ad-hoc; or a "Developer ID Application: …" identity
```

The launcher puts the bundled `node` on `PATH` and sets the working directory to
`Contents/Resources`, so bundled `node` and relative paths resolve as in
development. The `Info.plist` permits HTTP to localhost so a local server loads.
`--sign -` signs ad-hoc (runs locally); pass a Developer ID identity for
distribution — see the notarization notes at the end of `tools/pack-macos.sh`.

**Linux** → an AppDir, turned into a single-file `.AppImage` if `appimagetool`
is installed, otherwise a `.tar.gz`:

```bash
tachyon build --release
tools/pack-linux.sh \
  --bin target/release/my-app \
  --name "My App" \
  --resources web --resources server.js \
  --node
```

**Windows** → a self-contained folder + `.zip`, with optional `signtool`
signing (run in PowerShell):

```powershell
tachyon build --release
pwsh tools/pack-windows.ps1 `
  -Bin target/release/my-app.exe -Name "My App" `
  -Resources web,server.js `
  -Node -WebView2Loader "C:\path\to\WebView2Loader.dll" `
  -Icon app.ico `            # embedded into the .exe via rcedit (if on PATH)
  -Sign "My Cert Subject"     # or a 40-char cert thumbprint
```

Icons: `--icon` sets the bundle icon on macOS (`.icns` via `Info.plist`) and
Linux (`.png` via the `.desktop` entry). On Windows the icon is embedded into
the `.exe` with [`rcedit`](https://github.com/electron/rcedit) — install it
(`scoop install rcedit` / `choco install rcedit`) so it's on PATH.

> The macOS packager (incl. `--sign`) is verified end-to-end. The Linux packager
> is verified through AppDir assembly; the `.AppImage` step and the Windows
> packager have not been run on-target yet.

## Example

`examples/hello` starts a tiny Node HTTP server and shows it in a window:

```bash
cd examples/hello && ./run.sh
```

## Platforms

The same API works on all three desktop platforms; each uses the OS's own
webview, so there's no bundled browser.

| Platform | Webview | Native shim |
|----------|---------|-------------|
| macOS    | `WKWebView` (Cocoa + WebKit) | `native/positron_macos.m` |
| Linux    | WebKitGTK (GTK 3)           | `native/positron_linux.c` |
| Windows  | Microsoft Edge WebView2     | `native/positron_win32.c` |

**Build requirements**

- **macOS** — nothing extra; the Cocoa/WebKit frameworks ship with the OS.
- **Linux** — GTK 3 + WebKitGTK development packages, e.g.
  `sudo apt install libgtk-3-dev libwebkit2gtk-4.1-dev` (or `-4.0-dev`). Link
  flags are resolved with `pkg-config` automatically.
- **Windows** — the [WebView2 SDK](https://developer.microsoft.com/microsoft-edge/webview2/)
  header (`WebView2.h`) on `C_INCLUDE_PATH` at build time, and at runtime the
  Edge WebView2 runtime (preinstalled on current Windows 10/11) plus
  `WebView2Loader.dll` (resolved dynamically — no import library needed).

> Testing status: the macOS backend is verified end-to-end (window + Node
> sidecar + `.app` packaging). The Linux and Windows backends are written to
> the respective platform APIs but were authored on macOS and have **not** been
> compile-tested on their targets yet — expect to build them on a real
> Linux/Windows box first. Packaging (`tools/pack-macos.sh`) is macOS-only.

## License

MIT
