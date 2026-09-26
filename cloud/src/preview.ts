// The preview host (PREVIEW_ORIGIN): where a client shows a web service
// running on a station's machine, framed, on an origin of its own so the
// service's scripts reach nothing of ember's (no login, no storage).
//
// It serves two files and nothing else. /_ember/frame is the frame a client
// puts in its page; it registers /_ember/sw.js for the whole host, then shows
// the service in a frame of its own at the service's own paths. The service
// worker answers every request of that inner frame by handing it to the
// outer frame, which hands it (over a MessagePort) to the client that made
// it; the client sends it to the station through its core — over the mesh,
// like any other call — and the answer comes back the same way. Nothing of
// the service passes through here.
//
// Its limits: WebSockets are not requests a service worker sees (a dev
// server's live reload does not work), and cookies the service sets are not
// sent back (the service worker's requests carry none).

const FRAME = `<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ember preview</title>
<style>
  html, body { margin: 0; height: 100%; background: #fff; }
  iframe { display: block; width: 100%; height: 100%; border: 0; }
  p { margin: 0; padding: 24px; font: 14px system-ui, sans-serif; color: #777; }
</style>
<script>
  const params = new URLSearchParams(location.search);
  const nonce = params.get("n") || "";
  let port = null;
  let next = 0;
  const waiting = new Map();
  // The client's answers, by the id each request was sent with.
  const fromClient = (event) => {
    const reply = waiting.get(event.data.id);
    if (!reply) return;
    waiting.delete(event.data.id);
    reply.postMessage(event.data, event.data.body ? [event.data.body.buffer] : []);
  };
  // A request of the service's frame, from the service worker: on to the client.
  navigator.serviceWorker.addEventListener("message", (event) => {
    if (event.data?.type !== "ember-preview-fetch" || !port) return;
    const id = ++next;
    waiting.set(id, event.ports[0]);
    const { method, path, headers, body } = event.data;
    port.postMessage({ id, method, path, headers, body }, body ? [body.buffer] : []);
  });
  window.addEventListener("message", (event) => {
    if (event.source !== parent || event.data?.type !== "ember-preview-port" || port || !event.ports[0]) return;
    port = event.ports[0];
    port.onmessage = fromClient;
    start().catch((error) => { document.body.innerHTML = "<p></p>"; document.querySelector("p").textContent = "预览没能启动：" + error.message; });
  });
  async function start() {
    await navigator.serviceWorker.register("/_ember/sw.js", { scope: "/" });
    const worker = (await navigator.serviceWorker.ready).active;
    worker.postMessage({ type: "ember-preview-frame", nonce });
    const inner = document.createElement("iframe");
    inner.src = params.get("path") || "/";
    document.body.append(inner);
  }
  parent.postMessage({ type: "ember-preview-ready", nonce }, "*");
</script>
<body></body>
`;

const WORKER = `
// Which outer frame each of the service's frames belongs to (by client id), and the last frame that started.
const owners = new Map();
let latest = null;
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));
self.addEventListener("message", (event) => {
  if (event.data?.type === "ember-preview-frame") latest = event.data.nonce;
});
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (url.origin !== location.origin || url.pathname.startsWith("/_ember/")) return;
  event.respondWith(relay(event, url));
});
function nonceOf(event) {
  let nonce = null;
  try {
    const from = new URL(event.request.referrer);
    if (from.origin === location.origin && from.pathname === "/_ember/frame") nonce = from.searchParams.get("n");
  } catch {}
  nonce = nonce || owners.get(event.clientId) || latest;
  if (nonce && event.resultingClientId) owners.set(event.resultingClientId, nonce);
  if (nonce && event.clientId) owners.set(event.clientId, nonce);
  return nonce;
}
async function frameOf(nonce) {
  const frames = (await self.clients.matchAll({ type: "window", includeUncontrolled: true })).filter((c) => new URL(c.url).pathname === "/_ember/frame");
  return frames.find((c) => new URL(c.url).searchParams.get("n") === nonce) || frames.at(-1) || null;
}
function plain(status, text) {
  return new Response(text, { status, headers: { "content-type": "text/plain; charset=utf-8" } });
}
async function relay(event, url) {
  const frame = await frameOf(nonceOf(event));
  if (!frame) return plain(502, "预览已经断开：在 ember 里重新打开它。");
  const request = event.request;
  const body = request.method === "GET" || request.method === "HEAD" ? null : new Uint8Array(await request.arrayBuffer());
  const channel = new MessageChannel();
  const answer = new Promise((resolve) => { channel.port1.onmessage = (m) => resolve(m.data); });
  frame.postMessage({ type: "ember-preview-fetch", method: request.method, path: url.pathname + url.search, headers: [...request.headers], body }, [channel.port2, ...(body ? [body.buffer] : [])]);
  const reply = await answer;
  if (reply.error) return plain(502, reply.error);
  const empty = request.method === "HEAD" || [101, 204, 205, 304].includes(reply.status);
  return new Response(empty ? null : reply.body, { status: reply.status, headers: reply.headers });
}
`;

/** A request to the preview host. */
export function previewSite(url: URL): Response {
  if (url.pathname === "/_ember/frame") {
    return new Response(FRAME, { headers: { "content-type": "text/html; charset=utf-8", "cache-control": "no-cache" } });
  }
  if (url.pathname === "/_ember/sw.js") {
    return new Response(WORKER, { headers: { "content-type": "text/javascript; charset=utf-8", "cache-control": "no-cache", "service-worker-allowed": "/" } });
  }
  // Only reached before the service worker runs, or when a frame opens this host by itself.
  return new Response("这是 ember 的预览地址：在 ember 里打开一个预览。", { status: 404, headers: { "content-type": "text/plain; charset=utf-8" } });
}
