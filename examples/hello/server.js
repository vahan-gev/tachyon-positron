// A tiny Node.js server — this is the "not just static HTML" part: real
// server-side JS runs the app, and Positron shows it in a native window.
const http = require("http");

const PORT = process.env.PORT || 7777;
let hits = 0;

http
  .createServer((req, res) => {
    if (req.url === "/api/ping") {
      res.writeHead(200, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ pong: ++hits, node: process.version, pid: process.pid }));
      return;
    }
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(`<!doctype html>
<html><head><meta charset="utf-8"><title>Positron × Node</title>
<style>
  body{margin:0;font-family:-apple-system,system-ui,sans-serif;background:#0b0f19;color:#e5e7eb;
       display:flex;min-height:100vh;align-items:center;justify-content:center;text-align:center}
  .card{background:#151b2b;border:1px solid #232b3d;border-radius:18px;padding:40px 48px}
  h1{margin:0 0 6px;font-size:30px}
  .muted{color:#8b95a7}
  button{margin-top:18px;border:0;border-radius:10px;background:#2563eb;color:#fff;
         padding:11px 18px;font-size:15px;font-weight:600;cursor:pointer}
  code{color:#60a5fa}
</style></head>
<body><div class="card">
  <h1>Hello from a native window</h1>
  <div class="muted">served by <code>Node ${process.version}</code>, pid ${process.pid}</div>
  <button onclick="ping()">Ping the Node server</button>
  <p id="out" class="muted"></p>
</div>
<script>
  async function ping(){
    const r = await fetch('/api/ping');
    const j = await r.json();
    document.getElementById('out').textContent =
      'pong #' + j.pong + ' from Node ' + j.node + ' (pid ' + j.pid + ')';
  }
</script>
</body></html>`);
  })
  .listen(PORT, "127.0.0.1", () => console.log("demo server on http://127.0.0.1:" + PORT));
