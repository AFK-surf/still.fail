// The preview host (PREVIEW_ORIGIN): where a client shows a web service
// running on a station's machine, framed, on an origin of its own so the
// service's scripts reach nothing of still.fail's (no login, no storage). A static
// Worker of its own (ember-preview): these files, written out by
// build-static.ts, with the headers in its _headers.
//
// It serves four files and nothing else. /_stillfail/frame is the frame a client
// puts in its page; it registers /_stillfail/sw.js for the whole host, then shows
// the service in a frame of its own at the service's own paths. The service
// worker answers every request of that inner frame by handing it to the
// outer frame, which hands it (over a MessagePort) to the client that made
// it; the client sends it to the station through its core — over the mesh,
// like any other call — and the answer comes back the same way. Nothing of
// the service passes through here. /_stillfail/annotate.js, which the frame
// loads, marks the service's page for a chat (web/src/annotate/frame.ts).
//
// A service's WebSockets are not requests a service worker sees: /_ember/socket.js,
// which the service worker puts first in each of the service's pages, carries
// those to the preview's own host the same way (a dev server's live reload),
// through the frame. Answers come as they are sent (an event stream, a long
// poll), and a request its page gave up is stopped at the station.
//
// Clients from before the rename open /_ember/frame: the same files are
// under /_ember/ too, and the frame loads its script and service worker from
// beside itself, so each stays under the prefix it was opened with. The
// messages between the frame, its service worker and the client keep their
// "ember-preview-*" types (clients and service workers of either age are
// running at once); the frame and the service worker also take
// "stillfail-preview-*" ones. The tag the service worker puts in a page stays
// /_ember/socket.js (the desktop app answers that path too).
//
// Its limits: cookies the service sets are not sent back (the service
// worker's requests carry none).

import { SOCKET_TAG_JS, socketScript } from "./previewSocket.ts";

const FRAME = `<!doctype html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>still.fail preview</title>
<style>
  html, body { margin: 0; height: 100%; background: #fff; }
  iframe { display: block; width: 100%; height: 100%; border: 0; }
  p { margin: 0; padding: 24px; font: 14px system-ui, sans-serif; color: #777; }
</style>
<script src="annotate.js"></script>
<script>
  const is = (data, name) => data?.type === "stillfail-preview-" + name || data?.type === "ember-preview-" + name;
  const annotator = () => window.stillfailAnnotate || window.emberAnnotate;
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
    const asked = waiting.get(data.id);
    if (!asked) return;
    // Whole (an older client), or its end: nothing more comes for it.
    if (data.end || data.error || !streams) waiting.delete(data.id);
    if (asked.streams || !streams || data.error) {
      asked.reply.postMessage(data, data.body ? [data.body.buffer] : data.chunk ? [data.chunk.buffer] : []);
      return;
    }
    // A service worker from before answers as they come (one that has not been replaced yet): given it whole.
    if (data.head) asked.head = data.head;
    else if (data.chunk) asked.chunks.push(data.chunk);
    else if (data.end) {
      const body = new Uint8Array(asked.chunks.reduce((n, c) => n + c.length, 0));
      let at = 0;
      for (const c of asked.chunks) { body.set(c, at); at += c.length; }
      asked.reply.postMessage({ id: data.id, status: asked.head.status, headers: asked.head.headers, body }, [body.buffer]);
    }
  };
  // A request of the service's frame, from the service worker: on to the client. Given up (its page left, its reader
  // cancelled), the client is told to stop it.
  navigator.serviceWorker.addEventListener("message", (event) => {
    if (!is(event.data, "fetch") || !port) return;
    const id = ++next;
    const reply = event.ports[0];
    // Whether this service worker takes an answer as it comes (one from before takes it whole).
    waiting.set(id, { reply, streams: event.data.streams === true, head: null, chunks: [] });
    reply.onmessage = (m) => {
      if (m.data?.cancel && streams && waiting.delete(id)) port.postMessage({ type: "cancel", id });
    };
    const { method, path, headers, body } = event.data;
    port.postMessage({ id, method, path, headers, body }, body ? [body.buffer] : []);
  });
  // A WebSocket of the service's page (/_ember/socket.js, same origin: it calls this): through the client to the
  // station. \`on\` hears it open, its messages and its close; what is returned sends and closes. Under both names, as
  // annotate.js is: a page's socket.js from before the rename looks for \`emberPreviewSocket\`.
  window.stillfailPreviewSocket = window.emberPreviewSocket = (path, protocols, on) => {
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
    if (event.source !== parent || !is(event.data, "port") || port || !event.ports[0]) return;
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
    parent.postMessage({ type: "ember-preview-at", nonce, path, back: here > 0, forward: here < trail.length - 1, annotate: !!annotator() }, "*");
  };
  const replace = (path) => {
    moving = true;
    inner.contentWindow.location.replace(path);
  };
  window.addEventListener("message", (event) => {
    if (event.source !== parent || !is(event.data, "nav") || !inner) return;
    const { action, path } = event.data;
    if (action === "back" && here > 0) replace(trail[--here]);
    else if (action === "forward" && here < trail.length - 1) replace(trail[++here]);
    else if (action === "reload") { moving = true; inner.contentWindow.location.reload(); }
    else if (action === "go" && typeof path === "string" && path.startsWith("/")) inner.contentWindow.location.replace(path);
  });
  async function start() {
    await navigator.serviceWorker.register("sw.js", { scope: "/" });
    const worker = (await navigator.serviceWorker.ready).active;
    worker.postMessage({ type: "ember-preview-frame", nonce });
    inner = document.createElement("iframe");
    inner.src = params.get("path") || "/";
    inner.addEventListener("load", () => { report(); moving = false; });
    document.body.append(inner);
    // Marking the page for a chat (annotate.js, web/src/annotate/frame.ts), when it loaded.
    annotator()?.attach(inner, nonce);
    setInterval(report, 500);
  }
  parent.postMessage({ type: "ember-preview-ready", nonce, streams: true }, "*");
</script>
<body></body>
`;

const WORKER = `
// The frame, under the prefix of either name; the host's own files are under them.
const FRAMES = ["/_stillfail/frame", "/_ember/frame"];
const OWN = /^\\/_(stillfail|ember)\\//;
const is = (data, name) => data?.type === "stillfail-preview-" + name || data?.type === "ember-preview-" + name;
// Which outer frame each of the service's frames belongs to (by client id), and the last frame that started.
const owners = new Map();
let latest = null;
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (event) => event.waitUntil(self.clients.claim()));
self.addEventListener("message", (event) => {
  if (is(event.data, "frame")) latest = event.data.nonce;
});
self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  if (url.origin !== location.origin || OWN.test(url.pathname)) return;
  event.respondWith(relay(event, url));
});
function nonceOf(event) {
  let nonce = null;
  try {
    const from = new URL(event.request.referrer);
    if (from.origin === location.origin && FRAMES.includes(from.pathname)) nonce = from.searchParams.get("n");
  } catch {}
  nonce = nonce || owners.get(event.clientId) || latest;
  if (nonce && event.resultingClientId) owners.set(event.resultingClientId, nonce);
  if (nonce && event.clientId) owners.set(event.clientId, nonce);
  return nonce;
}
async function frameOf(nonce) {
  const frames = (await self.clients.matchAll({ type: "window", includeUncontrolled: true })).filter((c) => FRAMES.includes(new URL(c.url).pathname));
  return frames.find((c) => new URL(c.url).searchParams.get("n") === nonce) || frames.at(-1) || null;
}
function plain(status, text) {
  return new Response(text, { status, headers: { "content-type": "text/plain; charset=utf-8" } });
}
// What puts the service's pages' WebSockets through still.fail (/_ember/socket.js) into them: previewSocket.ts's.
${SOCKET_TAG_JS}
async function relay(event, url) {
  const frame = await frameOf(nonceOf(event));
  if (!frame) return plain(502, "预览已经断开：在 still.fail 里重新打开它。");
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
  frame.postMessage({ type: "ember-preview-fetch", streams: true, method: request.method, path: url.pathname + url.search, headers: [...request.headers], body }, [channel.port2, ...(body ? [body.buffer] : [])]);
  const reply = await head;
  if (reply.error) return plain(502, reply.error);
  const empty = request.method === "HEAD" || [101, 204, 205, 304].includes(reply.status);
  if (empty) {
    stop();
    return new Response(null, { status: reply.status, headers: reply.headers });
  }
  let out = reply.whole ? new Blob([reply.whole]).stream() : stream;
  const type = new Headers(reply.headers).get("content-type") || "";
  if (request.mode === "navigate" && type.startsWith("text/html")) out = withSocketTag(out);
  return new Response(out, { status: reply.status, headers: reply.headers });
}
`;

// A service's page, before any of its own scripts (the service worker puts it first in the page): its WebSockets go
// through the frame (previewSocket.ts). Without the frame (the page opened alone) it changes nothing.
const SOCKET = socketScript(`(() => {
  try {
    for (let w = window; w !== w.parent; ) {
      w = w.parent;
      if (!["/_stillfail/frame", "/_ember/frame"].includes(w.location.pathname)) continue;
      const link = w.stillfailPreviewSocket || w.emberPreviewSocket;
      if (typeof link === "function") return link;
    }
  } catch {}
  return null;
})()`);

/** Where the host's own files are: the new prefix, and the one clients from before the rename open. */
export const PREVIEW_PREFIXES = ["_stillfail", "_ember"] as const;

/** The preview host's files, by path under its assets directory. */
export function previewFiles(annotate = ""): Record<string, string> {
  return {
    ...Object.fromEntries(PREVIEW_PREFIXES.flatMap((prefix) => [
      [`${prefix}/frame.html`, FRAME],
      [`${prefix}/sw.js`, WORKER],
      // Marking the page for a chat (web/src/annotate/frame.ts), bundled by build-static.ts.
      [`${prefix}/annotate.js`, annotate],
      [`${prefix}/socket.js`, SOCKET],
    ])),
    // Only reached before the service worker runs, or when a frame opens this host by itself.
    "404.html": `<!doctype html><meta charset="utf-8"><title>still.fail preview</title><p>这是 still.fail 的预览地址：在 still.fail 里打开一个预览。</p>`,
    // The service worker is the whole host's, from under either prefix.
    "_headers": PREVIEW_PREFIXES.map((prefix) => `/${prefix}/sw.js\n  Service-Worker-Allowed: /\n  Cache-Control: no-cache\n/${prefix}/frame\n  Cache-Control: no-cache\n/${prefix}/annotate.js\n  Cache-Control: no-cache\n/${prefix}/socket.js\n  Cache-Control: no-cache\n`).join(""),
  };
}
