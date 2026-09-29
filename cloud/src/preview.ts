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
const SOCKETS = new TextEncoder().encode('<script src="/_ember/socket.js"></script>');
// Where in a page's first bytes the script goes: after the <head> tag, else after <html>, else after the doctype, else
// first. Tags are ASCII, so the bytes are searched as they are, whatever the page's encoding.
function placeIn(bytes) {
  const text = String.fromCharCode(...bytes.subarray(0, 4096)).toLowerCase();
  for (const tag of [/<head[\\s>]/, /<html[\\s>]/, /<!doctype[\\s>]/]) {
    const at = text.search(tag);
    if (at >= 0) {
      const end = text.indexOf(">", at);
      if (end >= 0) return end + 1;
    }
  }
  return 0;
}
function withSockets(body) {
  let placed = false;
  return body.pipeThrough(new TransformStream({
    transform(chunk, out) {
      if (placed) return out.enqueue(chunk);
      placed = true;
      const at = placeIn(chunk);
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

// First in the code of a worker a service's page makes (see SOCKET): its WebSockets to the preview's own host go
// through the page, over the port the page hands it first (a message it never sees).
const WORKER_SOCKET = `(() => {
  const Native = self.WebSocket;
  let relay = null;
  const queued = [];
  const sockets = new Map();
  let next = 0;
  const post = (message) => (relay ? relay.postMessage(message) : queued.push(message));
  const take = (event) => {
    if (!(event.data && event.data.emberSockets instanceof MessagePort)) return;
    event.stopImmediatePropagation();
    relay = event.data.emberSockets;
    relay.onmessage = ({ data }) => sockets.get(data.id)?._on(data);
    for (const message of queued.splice(0)) relay.postMessage(message);
  };
  if (typeof SharedWorkerGlobalScope !== "undefined" && self instanceof SharedWorkerGlobalScope) {
    self.addEventListener("connect", (event) => {
      const port = event.ports[0];
      port.addEventListener("message", take);
      port.start();
    });
  } else {
    self.addEventListener("message", take);
  }
  class WorkerSocket extends EventTarget {
    static CONNECTING = 0;
    static OPEN = 1;
    static CLOSING = 2;
    static CLOSED = 3;
    constructor(url, protocols) {
      super();
      // A blob: worker's own location has no host: the page's origin is its.
      const here = new URL(location.origin);
      const to = new URL(url, location.protocol === "blob:" ? here : location.href);
      if (to.host !== here.host) return new Native(url, protocols);
      this.url = to.href;
      this.readyState = 0;
      this.protocol = "";
      this.extensions = "";
      this.bufferedAmount = 0;
      this.binaryType = "blob";
      this.onopen = this.onmessage = this.onerror = this.onclose = null;
      this._id = ++next;
      sockets.set(this._id, this);
      post({ open: this._id, url: to.href, protocols: protocols === undefined ? [] : [].concat(protocols).map(String) });
    }
    _on(data) {
      if (data.opened && this.readyState === 0) {
        this.readyState = 1;
        this.protocol = data.protocol || "";
        this._fire(new Event("open"));
      } else if (data.message !== undefined && this.readyState === 1) {
        const got = typeof data.message === "string" || this.binaryType === "arraybuffer" ? data.message : new Blob([data.message]);
        this._fire(new MessageEvent("message", { data: got }));
      } else if (data.close && this.readyState !== 3) {
        this.readyState = 3;
        sockets.delete(this._id);
        if (data.failed) this._fire(new Event("error"));
        this._fire(new CloseEvent("close", { code: data.code, reason: data.reason, wasClean: !data.failed }));
      }
    }
    _fire(event) {
      const handler = this["on" + event.type];
      if (typeof handler === "function") handler.call(this, event);
      this.dispatchEvent(event);
    }
    send(data) {
      if (this.readyState === 0) throw new DOMException("WebSocket 还没连上", "InvalidStateError");
      if (this.readyState === 1) post({ id: this._id, send: data });
    }
    close(code, reason) {
      if (this.readyState >= 2) return;
      this.readyState = 2;
      post({ id: this._id, close: [code ?? 1000, reason ?? ""] });
    }
  }
  self.WebSocket = WorkerSocket;
})();
`;

// A service's page, before any of its own scripts (the service worker puts it first in the page): its WebSockets to
// the preview's own host (a dev server's live reload) go through the frame, the client and the station to the
// service's port, like its requests; any other stays the browser's own. Without the frame (the page opened alone) it
// changes nothing.
const SOCKET = `(() => {
  let frame = null;
  try {
    for (let w = window; w !== w.parent; ) {
      w = w.parent;
      if (w.location.pathname === "/_ember/frame" && typeof w.emberPreviewSocket === "function") { frame = w; break; }
    }
  } catch {}
  if (!frame) return;
  const Native = window.WebSocket;
  class PreviewSocket extends EventTarget {
    static CONNECTING = 0;
    static OPEN = 1;
    static CLOSING = 2;
    static CLOSED = 3;
    constructor(url, protocols) {
      super();
      const to = new URL(url, location.href);
      if (to.protocol === "http:" || to.protocol === "https:") to.protocol = to.protocol === "http:" ? "ws:" : "wss:";
      if (to.protocol !== "ws:" && to.protocol !== "wss:") throw new DOMException("不是 WebSocket 地址：" + url, "SyntaxError");
      if (to.host !== location.host) return new Native(url, protocols);
      this.url = to.href;
      this.readyState = 0;
      this.protocol = "";
      this.extensions = "";
      this.bufferedAmount = 0;
      this.binaryType = "blob";
      this.onopen = this.onmessage = this.onerror = this.onclose = null;
      this._sending = Promise.resolve();
      const asked = protocols === undefined ? [] : [].concat(protocols).map(String);
      this._link = frame.emberPreviewSocket(to.pathname + to.search, asked, {
        open: (protocol) => {
          if (this.readyState !== 0) return;
          this.readyState = 1;
          this.protocol = protocol;
          this._fire(new Event("open"));
        },
        message: (data) => {
          if (this.readyState !== 1) return;
          let got = data;
          if (typeof got !== "string") {
            const bytes = new Uint8Array(got.length);
            bytes.set(got);
            got = this.binaryType === "arraybuffer" ? bytes.buffer : new Blob([bytes]);
          }
          this._fire(new MessageEvent("message", { data: got, origin: location.origin }));
        },
        close: (code, reason, failed) => {
          if (this.readyState === 3) return;
          this.readyState = 3;
          if (failed) this._fire(new Event("error"));
          this._fire(new CloseEvent("close", { code, reason, wasClean: !failed }));
        },
      });
    }
    _fire(event) {
      const handler = this["on" + event.type];
      if (typeof handler === "function") handler.call(this, event);
      this.dispatchEvent(event);
    }
    send(data) {
      if (this.readyState === 0) throw new DOMException("WebSocket 还没连上", "InvalidStateError");
      if (this.readyState !== 1) return;
      // In the order sent, a Blob read first.
      this._sending = this._sending.then(async () => {
        if (this.readyState !== 1) return;
        if (typeof data === "string") return this._link.send(data);
        const buffer = data instanceof Blob ? await data.arrayBuffer() : ArrayBuffer.isView(data) ? data.buffer.slice(data.byteOffset, data.byteOffset + data.byteLength) : data.slice(0);
        this._link.send(new Uint8Array(buffer));
      });
    }
    close(code, reason) {
      if (this.readyState >= 2) return;
      this.readyState = 2;
      this._link.close(code ?? 1000, reason ?? "");
    }
  }
  window.WebSocket = PreviewSocket;

  // Workers the page makes from its own code (a blob: URL: a dev server's check that it is back up, in a shared
  // worker) get the same WebSocket: WORKER_SOCKET goes first in their code, and each is given a port to open its
  // sockets here through. A worker from a script of the service's (not blob:) keeps the browser's own.
  const shim = ${JSON.stringify(WORKER_SOCKET)};
  const relay = (port) => {
    const open = new Map();
    port.onmessage = ({ data }) => {
      if (data.open !== undefined) {
        let socket;
        try { socket = new PreviewSocket(data.url, data.protocols); } catch { return port.postMessage({ id: data.open, close: true, code: 1006, reason: "", failed: true }); }
        socket.binaryType = "arraybuffer";
        open.set(data.open, socket);
        socket.onopen = () => port.postMessage({ id: data.open, opened: true, protocol: socket.protocol });
        socket.onmessage = (event) => port.postMessage({ id: data.open, message: event.data });
        socket.onclose = (event) => {
          open.delete(data.open);
          port.postMessage({ id: data.open, close: true, code: event.code, reason: event.reason, failed: !event.wasClean });
        };
      } else if (data.send !== undefined) {
        open.get(data.id)?.send(data.send);
      } else if (data.close) {
        open.get(data.id)?.close(data.close[0], data.close[1]);
      }
    };
  };
  const withShim = (code) => {
    // A "use strict" directive only counts first: it stays first.
    const strict = /^\\s*(["'])use strict\\1;?/.exec(code);
    return strict ? strict[0] + "\\n" + shim + code.slice(strict[0].length) : shim + code;
  };
  const wrap = (Native, shared) => {
    const Wrapped = function (url, options) {
      const href = String(url);
      if (!new.target || !href.startsWith("blob:")) return new Native(url, options);
      let code;
      try {
        const read = new XMLHttpRequest();
        read.open("GET", href, false);
        read.send();
        code = read.responseText;
      } catch {
        return new Native(url, options);
      }
      const worker = new Native(URL.createObjectURL(new Blob([withShim(code)], { type: "text/javascript" })), options);
      const { port1, port2 } = new MessageChannel();
      relay(port1);
      (shared ? worker.port : worker).postMessage({ emberSockets: port2 }, [port2]);
      return worker;
    };
    Wrapped.prototype = Native.prototype;
    return Wrapped;
  };
  if (window.Worker) window.Worker = wrap(window.Worker, false);
  if (window.SharedWorker) window.SharedWorker = wrap(window.SharedWorker, true);
})();
`;

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
