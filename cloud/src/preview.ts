// The preview host (PREVIEW_ORIGIN): where a client shows a web service
// running on a station's machine, framed, on an origin of its own so the
// service's scripts reach nothing of ember's (no login, no storage). A static
// Worker of its own (ember-preview): these files, written out by
// build-static.ts, with the headers in its _headers.
//
// It serves three files and nothing else. /_ember/frame is the frame a client
// puts in its page; it registers /_ember/sw.js for the whole host, then shows
// the service in a frame of its own at the service's own paths. The service
// worker answers every request of that inner frame by handing it to the
// outer frame, which hands it (over a MessagePort) to the client that made
// it; the client sends it to the station through its core — over the mesh,
// like any other call — and the answer comes back the same way. Nothing of
// the service passes through here. /_ember/annotate.js, which the frame
// loads, marks the service's page for a chat (web/src/annotate/frame.ts).
//
// A service's WebSockets are not requests a service worker sees: /_ember/socket.js,
// which the service worker puts first in each of the service's pages, carries
// those to the preview's own host the same way (a dev server's live reload),
// through the frame. Answers come as they are sent (an event stream, a long
// poll), and a request its page gave up is stopped at the station.
//
// Its limits: cookies the service sets are not sent back (the service
// worker's requests carry none).

import { socketScript, socketTagAt } from "./previewSocket.ts";

const FRAME = `<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>ember preview</title>
<style>
  html, body { margin: 0; height: 100%; background: #fff; }
  iframe { display: block; width: 100%; height: 100%; border: 0; }
  p { margin: 0; padding: 24px; font: 14px system-ui, sans-serif; color: #777; }
</style>
<script src="/_ember/annotate.js"></script>
<script>
  const params = new URLSearchParams(location.search);
  const nonce = params.get("n") || "";
  let port = null;
  // The client gives answers as they come and carries WebSockets (web/src/previewBridge.ts); an older one answers whole.
  let streams = false;
  let next = 0;
  // Each request's port back to the service worker, by the id it was sent to the client with.
  const waiting = new Map();
  // Each WebSocket's page (/_ember/socket.js), by its id.
  const sockets = new Map();
  const fromClient = (event) => {
    const data = event.data;
    if (typeof data?.type === "string" && data.type.startsWith("socket-")) {
      const socket = sockets.get(data.sid);
      if (!socket) return;
      if (data.type === "socket-open") socket.open(data.protocol || "");
      else if (data.type === "socket-message") socket.message(typeof data.text === "string" ? data.text : data.binary);
      else if (data.type === "socket-close") { sockets.delete(data.sid); socket.close(data.code, data.reason || "", data.failed === true); }
      return;
    }
    const reply = waiting.get(data.id);
    if (!reply) return;
    // Whole (an older client), or its end: nothing more comes for it.
    if (data.end || data.error || !streams) waiting.delete(data.id);
    reply.postMessage(data, data.body ? [data.body.buffer] : data.chunk ? [data.chunk.buffer] : []);
  };
  // A request of the service's frame, from the service worker: on to the client. Given up (its page left, its reader
  // cancelled), the client is told to stop it.
  navigator.serviceWorker.addEventListener("message", (event) => {
    if (event.data?.type !== "ember-preview-fetch" || !port) return;
    const id = ++next;
    const reply = event.ports[0];
    waiting.set(id, reply);
    reply.onmessage = (m) => {
      if (m.data?.cancel && streams && waiting.delete(id)) port.postMessage({ type: "cancel", id });
    };
    const { method, path, headers, body } = event.data;
    port.postMessage({ id, method, path, headers, body }, body ? [body.buffer] : []);
  });
  // A WebSocket of the service's page (/_ember/socket.js, same origin: it calls this): through the client to the
  // station. \`on\` hears it open, its messages and its close; what is returned sends and closes.
  window.emberPreviewSocket = (path, protocols, on) => {
    const sid = crypto.randomUUID();
    if (!port || !streams) {
      setTimeout(() => on.close(1006, "", true));
      return { send() {}, close() {} };
    }
    sockets.set(sid, on);
    port.postMessage({ type: "socket", sid, path, protocols });
    return {
      send: (data) => typeof data === "string"
        ? port.postMessage({ type: "socket-send", sid, text: data })
        : port.postMessage({ type: "socket-send", sid, binary: data }, [data.buffer]),
      close: (code, reason) => port.postMessage({ type: "socket-send", sid, close: [code, reason] }),
    };
  };
  window.addEventListener("message", (event) => {
    if (event.source !== parent || event.data?.type !== "ember-preview-port" || port || !event.ports[0]) return;
    port = event.ports[0];
    streams = event.data.streams === true;
    port.onmessage = fromClient;
    start().catch((error) => { document.body.innerHTML = "<p></p>"; document.querySelector("p").textContent = "预览没能启动：" + error.message; });
  });
  // The service's frame, and a history of its own: the bar's back, forward and go move along it with replace(), so they
  // never step the page it sits in (a frame shares its window's history: history.back() at its start leaves the page).
  // Where it is, and whether it can go back or on, is said back to the client as it loads and as a page moves itself.
  let inner = null;
  const trail = [];
  let here = -1;
  let moving = false;
  let said = "";
  const where = () => {
    try { const at = inner.contentWindow.location; return at.pathname + at.search + at.hash; } catch { return null; }
  };
  const report = () => {
    const path = where();
    if (path === null) return;
    if (!moving && trail[here] !== path) {
      trail.splice(here + 1);
      trail.push(path);
      here = trail.length - 1;
    }
    const state = path + "|" + here + "|" + trail.length;
    if (state === said) return;
    said = state;
    parent.postMessage({ type: "ember-preview-at", nonce, path, back: here > 0, forward: here < trail.length - 1, annotate: !!window.emberAnnotate }, "*");
  };
  const replace = (path) => {
    moving = true;
    inner.contentWindow.location.replace(path);
  };
  window.addEventListener("message", (event) => {
    if (event.source !== parent || event.data?.type !== "ember-preview-nav" || !inner) return;
    const { action, path } = event.data;
    if (action === "back" && here > 0) replace(trail[--here]);
    else if (action === "forward" && here < trail.length - 1) replace(trail[++here]);
    else if (action === "reload") { moving = true; inner.contentWindow.location.reload(); }
    else if (action === "go" && typeof path === "string" && path.startsWith("/")) inner.contentWindow.location.replace(path);
  });
  async function start() {
    await navigator.serviceWorker.register("/_ember/sw.js", { scope: "/" });
    const worker = (await navigator.serviceWorker.ready).active;
    worker.postMessage({ type: "ember-preview-frame", nonce });
    inner = document.createElement("iframe");
    inner.src = params.get("path") || "/";
    inner.addEventListener("load", () => { report(); moving = false; });
    document.body.append(inner);
    // Marking the page for a chat (/_ember/annotate.js, web/src/annotate/frame.ts), when it loaded.
    window.emberAnnotate?.attach(inner, nonce);
    setInterval(report, 500);
  }
  parent.postMessage({ type: "ember-preview-ready", nonce, streams: true }, "*");
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
// What goes into a page of the service, first in its <head>: its WebSockets through ember (/_ember/socket.js).
// Where it goes: previewSocket.ts's, as its source (types already stripped by whatever loaded this module).
const SOCKETS = new TextEncoder().encode('<script src="/_ember/socket.js"></script>');
${socketTagAt.toString()}
function withSockets(body) {
  let placed = false;
  return body.pipeThrough(new TransformStream({
    transform(chunk, out) {
      if (placed) return out.enqueue(chunk);
      placed = true;
      const at = socketTagAt(chunk);
      out.enqueue(chunk.subarray(0, at));
      out.enqueue(SOCKETS);
      out.enqueue(chunk.subarray(at));
    },
  }));
}
async function relay(event, url) {
  const frame = await frameOf(nonceOf(event));
  if (!frame) return plain(502, "预览已经断开：在 ember 里重新打开它。");
  const request = event.request;
  const body = request.method === "GET" || request.method === "HEAD" ? null : new Uint8Array(await request.arrayBuffer());
  const channel = new MessageChannel();
  // The answer as it comes (web/src/previewBridge.ts): its head, then its body into a stream; or whole (an older client).
  let body$ = null;
  let settled = false;
  const stop = () => {
    if (settled) return;
    settled = true;
    channel.port1.postMessage({ cancel: true });
  };
  const stream = new ReadableStream({ start(c) { body$ = c; }, cancel: stop });
  request.signal?.addEventListener("abort", () => { stop(); try { body$.error(new Error("aborted")); } catch {} });
  const head = new Promise((resolve) => {
    channel.port1.onmessage = (m) => {
      const reply = m.data;
      if (reply.head) return resolve(reply.head);
      if (reply.chunk) { try { body$.enqueue(reply.chunk); } catch {} return; }
      if (reply.end) { settled = true; try { body$.close(); } catch {} return; }
      if (reply.error) {
        settled = true;
        try { body$.error(new Error(reply.error)); } catch {}
        return resolve({ error: reply.error });
      }
      // Whole.
      settled = true;
      resolve({ status: reply.status, headers: reply.headers, whole: reply.body });
    };
  });
  frame.postMessage({ type: "ember-preview-fetch", method: request.method, path: url.pathname + url.search, headers: [...request.headers], body }, [channel.port2, ...(body ? [body.buffer] : [])]);
  const reply = await head;
  if (reply.error) return plain(502, reply.error);
  const empty = request.method === "HEAD" || [101, 204, 205, 304].includes(reply.status);
  if (empty) {
    stop();
    return new Response(null, { status: reply.status, headers: reply.headers });
  }
  let out = reply.whole ? new Blob([reply.whole]).stream() : stream;
  const type = new Headers(reply.headers).get("content-type") || "";
  if (request.mode === "navigate" && type.startsWith("text/html")) out = withSockets(out);
  return new Response(out, { status: reply.status, headers: reply.headers });
}
`;

// A service's page, before any of its own scripts (the service worker puts it first in the page): its WebSockets go
// through the frame (previewSocket.ts). Without the frame (the page opened alone) it changes nothing.
const SOCKET = socketScript(`(() => {
  try {
    for (let w = window; w !== w.parent; ) {
      w = w.parent;
      if (w.location.pathname === "/_ember/frame" && typeof w.emberPreviewSocket === "function") return w.emberPreviewSocket;
    }
  } catch {}
  return null;
})()`);

/** The preview host's files, by path under its assets directory. */
export function previewFiles(annotate = ""): Record<string, string> {
  return {
    "_ember/frame.html": FRAME,
    "_ember/sw.js": WORKER,
    // Marking the page for a chat (web/src/annotate/frame.ts), bundled by build-static.ts.
    "_ember/annotate.js": annotate,
    "_ember/socket.js": SOCKET,
    // Only reached before the service worker runs, or when a frame opens this host by itself.
    "404.html": `<!doctype html><meta charset="utf-8"><title>ember preview</title><p>这是 ember 的预览地址：在 ember 里打开一个预览。</p>`,
    // The service worker is the whole host's, from under /_ember/.
    "_headers": "/_ember/sw.js\n  Service-Worker-Allowed: /\n  Cache-Control: no-cache\n/_ember/frame\n  Cache-Control: no-cache\n/_ember/annotate.js\n  Cache-Control: no-cache\n/_ember/socket.js\n  Cache-Control: no-cache\n",
  };
}
