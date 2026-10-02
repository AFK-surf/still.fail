// First in each of a web service's pages in the app's preview (screens/Preview.kt puts it there, after <head>): what a
// preview's frame and its service worker do on the web (cloud/src/preview.ts, web/src/annotate/frame.ts), for a
// WebView that is the page itself. Three parts: the page's WebSockets through the app (socketScript() of
// cloud/src/previewSocket.ts, as written out with the link below: regenerate it from there when that changes), its
// requests' bodies, and marking the page.
(() => {
  // The words a person may read here in the app's language, which the app says first (PreviewWeb.kt pageScript).
  const en = self.__stillfailLang === "en";
  const link = (() => {
  // The page's own WebSockets go through the app (the preview's JavascriptInterface, StillFailPreviewNative, on to
  // the core's preview.socket): kept in the top page, which the app speaks to, for the page and its frames alike.
  let top;
  try { top = window.top; void top.location.href; } catch { return null; }
  const native = top.StillFailPreviewNative;
  if (!native) return null;
  if (!top.__stillfailSockets) {
    const open = new Map();
    top.__stillfailSockets = open;
    top.__stillfailSocketEvent = (sid, kind, a, b, c) => {
      const on = open.get(sid);
      if (!on) return;
      if (kind === "open") on.open(a);
      else if (kind === "text") on.message(a);
      else if (kind === "binary") on.message(Uint8Array.from(atob(a), (ch) => ch.charCodeAt(0)));
      else if (kind === "close") { open.delete(sid); on.close(a, b, c); }
    };
  }
  const base64 = (bytes) => { let s = ""; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return btoa(s); };
  return (path, protocols, on) => {
    const sid = top.crypto.randomUUID();
    top.__stillfailSockets.set(sid, on);
    native.open(sid, path, protocols.join(","));
    return {
      send: (data) => (typeof data === "string" ? native.send(sid, data) : native.sendBinary(sid, base64(data))),
      close: (code, reason) => native.close(sid, code, reason),
    };
  };
})();
  if (!link) return;
  const Native = window.WebSocket;
  // The sockets still open: a page that goes (reloaded, left) closes them, as the browser's own would be.
  const live = new Set();
  class PreviewSocket extends EventTarget {
    static CONNECTING = 0;
    static OPEN = 1;
    static CLOSING = 2;
    static CLOSED = 3;
    constructor(url, protocols) {
      super();
      const to = new URL(url, location.href);
      if (to.protocol === "http:" || to.protocol === "https:") to.protocol = to.protocol === "http:" ? "ws:" : "wss:";
      if (to.protocol !== "ws:" && to.protocol !== "wss:") throw new DOMException((en ? "Not a WebSocket address: " : "不是 WebSocket 地址：") + url, "SyntaxError");
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
      this._link = link(to.pathname + to.search, asked, {
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
          live.delete(this);
          if (failed) this._fire(new Event("error"));
          this._fire(new CloseEvent("close", { code, reason, wasClean: !failed }));
        },
      });
      live.add(this);
    }
    _fire(event) {
      const handler = this["on" + event.type];
      if (typeof handler === "function") handler.call(this, event);
      this.dispatchEvent(event);
    }
    send(data) {
      if (this.readyState === 0) throw new DOMException(en ? "WebSocket is not connected yet" : "WebSocket 还没连上", "InvalidStateError");
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
  Object.assign(PreviewSocket.prototype, { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 });
  addEventListener("pagehide", () => { for (const socket of [...live]) socket.close(1001, ""); });
  window.WebSocket = PreviewSocket;

  // Workers the page makes from its own code (a blob: URL: a dev server's check that it is back up, in a shared
  // worker) get the same WebSocket: WORKER_SOCKET goes first in their code, and each is given a port to open its
  // sockets here through. A worker from a script of the service's (not blob:) keeps the browser's own.
  const shim = "(() => {\n  const Native = self.WebSocket;\n  let relay = null;\n  const queued = [];\n  const sockets = new Map();\n  let next = 0;\n  const post = (message) => (relay ? relay.postMessage(message) : queued.push(message));\n  const take = (event) => {\n    if (!(event.data && event.data.stillfailSockets instanceof MessagePort)) return;\n    event.stopImmediatePropagation();\n    relay = event.data.stillfailSockets;\n    relay.onmessage = ({ data }) => sockets.get(data.id)?._on(data);\n    for (const message of queued.splice(0)) relay.postMessage(message);\n  };\n  if (typeof SharedWorkerGlobalScope !== \"undefined\" && self instanceof SharedWorkerGlobalScope) {\n    self.addEventListener(\"connect\", (event) => {\n      const port = event.ports[0];\n      port.addEventListener(\"message\", take);\n      port.start();\n    });\n  } else {\n    self.addEventListener(\"message\", take);\n  }\n  class WorkerSocket extends EventTarget {\n    static CONNECTING = 0;\n    static OPEN = 1;\n    static CLOSING = 2;\n    static CLOSED = 3;\n    constructor(url, protocols) {\n      super();\n      // A blob: worker's own location has no host: the page's origin is its.\n      const here = new URL(location.origin);\n      const to = new URL(url, location.protocol === \"blob:\" ? here : location.href);\n      if (to.host !== here.host) return new Native(url, protocols);\n      this.url = to.href;\n      this.readyState = 0;\n      this.protocol = \"\";\n      this.extensions = \"\";\n      this.bufferedAmount = 0;\n      this.binaryType = \"blob\";\n      this.onopen = this.onmessage = this.onerror = this.onclose = null;\n      this._id = ++next;\n      sockets.set(this._id, this);\n      post({ open: this._id, url: to.href, protocols: protocols === undefined ? [] : [].concat(protocols).map(String) });\n    }\n    _on(data) {\n      if (data.opened && this.readyState === 0) {\n        this.readyState = 1;\n        this.protocol = data.protocol || \"\";\n        this._fire(new Event(\"open\"));\n      } else if (data.message !== undefined && this.readyState === 1) {\n        const got = typeof data.message === \"string\" || this.binaryType === \"arraybuffer\" ? data.message : new Blob([data.message]);\n        this._fire(new MessageEvent(\"message\", { data: got }));\n      } else if (data.close && this.readyState !== 3) {\n        this.readyState = 3;\n        sockets.delete(this._id);\n        if (data.failed) this._fire(new Event(\"error\"));\n        this._fire(new CloseEvent(\"close\", { code: data.code, reason: data.reason, wasClean: !data.failed }));\n      }\n    }\n    _fire(event) {\n      const handler = this[\"on\" + event.type];\n      if (typeof handler === \"function\") handler.call(this, event);\n      this.dispatchEvent(event);\n    }\n    send(data) {\n      if (this.readyState === 0) throw new DOMException(" + JSON.stringify(en ? "WebSocket is not connected yet" : "WebSocket 还没连上") + ", \"InvalidStateError\");\n      if (this.readyState === 1) post({ id: this._id, send: data });\n    }\n    close(code, reason) {\n      if (this.readyState >= 2) return;\n      this.readyState = 2;\n      post({ id: this._id, close: [code ?? 1000, reason ?? \"\"] });\n    }\n  }\n  Object.assign(WorkerSocket.prototype, { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 });\n  self.WebSocket = WorkerSocket;\n})();\n";
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
    const strict = /^\s*(["'])use strict\1;?/.exec(code);
    return strict ? strict[0] + "\n" + shim + code.slice(strict[0].length) : shim + code;
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
      (shared ? worker.port : worker).postMessage({ stillfailSockets: port2 }, [port2]);
      return worker;
    };
    Wrapped.prototype = Native.prototype;
    return Wrapped;
  };
  if (window.Worker) window.Worker = wrap(window.Worker, false);
  if (window.SharedWorker) window.SharedWorker = wrap(window.SharedWorker, true);
})();

// What a request of the service's carries (a POST's body): the WebView does not hand request bodies to the app, so a
// body of the page's own fetch or XMLHttpRequest to its own host is left with the app first (stash), under an id the
// request then carries in a header, x-stillfail-body, which the app takes off again. The top page's fetch() goes to
// the app whole instead, and its answer comes as it is sent (below).
(() => {
  // The words a person may read here in the app's language, which the app says first (PreviewWeb.kt pageScript).
  const en = self.__stillfailLang === "en";
  const native = window.StillFailPreviewNative;
  if (!native || window.__stillfailBodies) return;
  window.__stillfailBodies = true;
  const base64 = (bytes) => { let s = ""; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return btoa(s); };
  const own = (url) => { try { return new URL(url, location.href).origin === location.origin; } catch { return false; } };
  const stash = (bytes, type) => {
    const id = crypto.randomUUID();
    native.stash(id, base64(bytes), type || "");
    return id;
  };
  // The top page's fetch() of its own host goes through the app instead (PreviewWeb.kt fetchSaid), over a message port
  // the app gives it: a WebView hands the page what the app answers only 2 KB at a time, and this way each piece of a
  // body comes as the service sends it (a log, a streamed answer). Without the port (a file's page, an app from
  // before), as below.
  const bridge = (() => {
    if (window !== window.top || typeof native.fetchPort !== "function") return null;
    const token = "stillfail-fetch-" + crypto.randomUUID();
    const waiting = new Map();
    const port = new Promise((resolve) => {
      const take = (event) => {
        // Only the app's own message (no window sent it) carrying the token asked for.
        if (event.data !== token || event.source !== null || !event.ports || !event.ports[0]) return;
        event.stopImmediatePropagation();
        removeEventListener("message", take, true);
        const got = event.ports[0];
        got.onmessage = ({ data }) => {
          let said;
          try { said = JSON.parse(data); } catch { return; }
          waiting.get(said && said.id)?.(said);
        };
        resolve(got);
      };
      addEventListener("message", take, true);
      setTimeout(() => resolve(null), 5000);
    });
    let asking = false;
    try { asking = native.fetchPort(token) === true; } catch {}
    if (!asking) return null;
    const bytesOf = (text) => { const s = atob(text); const out = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i); return out; };
    const define = (answer, props) => { for (const [k, v] of Object.entries(props)) Object.defineProperty(answer, k, { value: v }); return answer; };
    const go = (to, asked, bytes) => new Promise((resolve, reject) => {
      const id = crypto.randomUUID();
      const signal = asked.signal;
      const aborted = () => signal.reason ?? new DOMException("signal is aborted without reason", "AbortError");
      if (signal.aborted) return reject(aborted());
      let stream = null;
      let done = false;
      const finish = () => { done = true; waiting.delete(id); signal.removeEventListener("abort", onAbort); };
      const stop = () => { if (done) return; finish(); to.postMessage(JSON.stringify({ t: "stop", id })); };
      const onAbort = () => {
        const why = aborted();
        if (stream) { try { stream.error(why); } catch {} } else reject(why);
        stop();
      };
      signal.addEventListener("abort", onAbort);
      waiting.set(id, (said) => {
        if (done) return;
        if (said.t === "head") {
          const moved = said.status >= 300 && said.status < 400 && said.headers.some(([k]) => k.toLowerCase() === "location");
          const url = location.origin + said.path;
          if (moved && asked.redirect === "error") { stop(); return reject(new TypeError("Failed to fetch")); }
          if (moved && asked.redirect === "manual") { stop(); return resolve(define(Response.error(), { type: "opaqueredirect", url, redirected: false })); }
          const headers = new Headers();
          for (const [k, v] of said.headers) if (!/^set-cookie2?$/i.test(k)) { try { headers.append(k, v); } catch {} }
          const empty = asked.method === "HEAD" || [101, 204, 205, 304].includes(said.status);
          const body = empty ? null : new ReadableStream({ start: (c) => { stream = c; }, cancel: () => stop() }, new ByteLengthQueuingStrategy({ highWaterMark: 1 << 16 }));
          let answer;
          try { answer = new Response(body, { status: said.status, statusText: said.statusText || "", headers }); } catch (e) { stop(); return reject(new TypeError("Failed to fetch: " + e.message)); }
          resolve(define(answer, { url, redirected: said.redirected === true, type: "basic" }));
        } else if (said.t === "chunk") {
          if (!stream) return;
          stream.enqueue(bytesOf(said.b));
          // Read too slowly (as in PreviewWeb.kt's Chunks): given up rather than kept here without end.
          if (stream.desiredSize < -(32 << 20)) { stream.error(new TypeError(en ? "The page read too slowly and was stopped" : "网页读得太慢，已停止")); stop(); }
        } else if (said.t === "end") {
          finish();
          try { stream?.close(); } catch {}
        } else if (said.t === "error") {
          finish();
          const why = new TypeError("Failed to fetch: " + said.message);
          if (stream) { try { stream.error(why); } catch {} } else reject(why);
        }
      });
      const to_ = new URL(asked.url);
      const headers = new Headers(asked.headers);
      // What the browser would add to a request of its own.
      if (!headers.has("accept")) headers.set("accept", "*/*");
      if (!headers.has("accept-language") && navigator.languages?.length) headers.set("accept-language", navigator.languages.join(","));
      headers.set("user-agent", navigator.userAgent);
      if (asked.referrer && asked.referrer !== "no-referrer") headers.set("referer", asked.referrer === "about:client" ? location.href : asked.referrer);
      if (asked.method !== "GET" && asked.method !== "HEAD") headers.set("origin", location.origin);
      to.postMessage(JSON.stringify({
        t: "go", id, method: asked.method, path: to_.pathname + to_.search, headers: [...headers], redirect: asked.redirect,
        cookies: asked.credentials !== "omit", body: bytes && bytes.length ? base64(bytes) : "",
      }));
    });
    const through = async (asked, bytes) => {
      const to = await port;
      return to ? go(to, asked, bytes) : null;
    };
    through.ready = port;
    return through;
  })();
  const fetched = window.fetch;
  window.fetch = async function (input, init) {
    let asked;
    try { asked = new Request(input, init); } catch { return fetched.call(this, input, init); }
    if (bridge && own(asked.url) && /^https?:$/.test(new URL(asked.url).protocol) && !new URL(asked.url).pathname.startsWith("/_stillfail/")) {
      const bytes = asked.method === "GET" || asked.method === "HEAD" ? null : new Uint8Array(await asked.clone().arrayBuffer());
      const answer = await bridge(asked, bytes);
      if (answer) return answer;
    }
    if (!own(asked.url) || asked.method === "GET" || asked.method === "HEAD") return fetched.call(this, input, init);
    const bytes = new Uint8Array(await asked.clone().arrayBuffer());
    if (!bytes.length) return fetched.call(this, input, init);
    const headers = new Headers(asked.headers);
    headers.set("x-stillfail-body", stash(bytes, headers.get("content-type")));
    return fetched.call(this, new Request(asked, { headers }));
  };
  const X = XMLHttpRequest.prototype;
  const opened = X.open, sent = X.send, typed = X.setRequestHeader;
  X.open = function (method, url, async) {
    this.__stillfail = { method: String(method).toUpperCase(), url: String(url), async: async !== false, type: null };
    return opened.apply(this, arguments);
  };
  X.setRequestHeader = function (name, value) {
    if (this.__stillfail && String(name).toLowerCase() === "content-type") this.__stillfail.type = String(value);
    return typed.apply(this, arguments);
  };
  X.send = function (body) {
    const asked = this.__stillfail;
    if (!asked || body == null || asked.method === "GET" || asked.method === "HEAD" || !own(asked.url)) return sent.apply(this, arguments);
    if (typeof body === "string") {
      typed.call(this, "x-stillfail-body", stash(new TextEncoder().encode(body), asked.type || "text/plain;charset=UTF-8"));
      return sent.call(this, body);
    }
    if (body instanceof ArrayBuffer || ArrayBuffer.isView(body)) {
      const bytes = body instanceof ArrayBuffer ? new Uint8Array(body) : new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
      typed.call(this, "x-stillfail-body", stash(bytes, asked.type));
      return sent.call(this, body);
    }
    // A Blob, a form: read first (only when the request waits for nothing: a synchronous one goes without).
    if (!asked.async) return sent.apply(this, arguments);
    const answer = new Response(body);
    const type = asked.type || answer.headers.get("content-type");
    answer.arrayBuffer().then((buffer) => {
      typed.call(this, "x-stillfail-body", stash(new Uint8Array(buffer), type));
      if (!asked.type && type) typed.call(this, "content-type", type);
      sent.call(this, buffer);
    }, () => sent.call(this, body));
  };

  // The top page's asynchronous XMLHttpRequest of its own host goes the same way (its progress as the body comes): the
  // request itself stays the page's, with what it says (its state, its answer, its events) given here.
  if (!bridge) return;
  const opened2 = X.open, sent2 = X.send, typed2 = X.setRequestHeader, aborted2 = X.abort, header2 = X.getResponseHeader, headers2 = X.getAllResponseHeaders;
  const SHOWN = ["readyState", "status", "statusText", "responseURL", "responseText", "response", "responseXML"];
  const unshow = (xhr) => { for (const k of SHOWN) delete xhr[k]; };
  X.open = function (method, url, async) {
    const had = this.__stillfailX;
    if (had && had.state && !had.state.over) { had.state.over = true; had.controller.abort(); }
    unshow(this);
    this.__stillfailX = { method: String(method).toUpperCase(), url: String(url), async: async !== false, headers: [] };
    return opened2.apply(this, arguments);
  };
  X.setRequestHeader = function (name, value) {
    this.__stillfailX?.headers.push([String(name), String(value)]);
    return typed2.apply(this, arguments);
  };
  X.getResponseHeader = function (name) {
    const state = this.__stillfailX?.state;
    if (!state) return header2.apply(this, arguments);
    return state.readyState >= 2 && state.headers ? state.headers.get(name) : null;
  };
  X.getAllResponseHeaders = function () {
    const state = this.__stillfailX?.state;
    if (!state) return headers2.apply(this, arguments);
    return state.readyState >= 2 && state.headers ? [...state.headers].map(([k, v]) => k + ": " + v + "\r\n").join("") : "";
  };
  X.abort = function () {
    const asked = this.__stillfailX;
    if (!asked || !asked.state) return aborted2.apply(this, arguments);
    const state = asked.state;
    if (state.over) { state.readyState = 0; return; }
    state.over = true;
    asked.controller.abort();
    state.fail("abort");
    state.readyState = 0;
  };
  X.send = function (body) {
    const asked = this.__stillfailX;
    const xhr = this;
    let to;
    try { to = new URL(asked.url, location.href); } catch { return sent2.apply(this, arguments); }
    if (!asked || !asked.async || asked.state || to.origin !== location.origin || to.pathname.startsWith("/_stillfail/") || xhr.responseType === "document" || (typeof Document !== "undefined" && body instanceof Document)) return sent2.apply(this, arguments);
    const args = arguments;
    const controller = new AbortController();
    const state = { readyState: 1, status: 0, statusText: "", url: "", headers: null, text: "", pieces: [], loaded: 0, over: false };
    asked.controller = controller;
    const fire = (type) => xhr.dispatchEvent(type === "readystatechange" ? new Event(type) : new ProgressEvent(type, { lengthComputable: state.total > 0, loaded: state.loaded, total: state.total || 0 }));
    const move = (n) => { state.readyState = n; fire("readystatechange"); };
    state.fail = (type) => {
      state.status = 0; state.statusText = ""; state.headers = null; state.text = ""; state.pieces = [];
      move(4); fire(type); fire("loadend");
    };
    const whole = () => {
      if (state.readyState !== 4) return null;
      const type = xhr.responseType;
      if (type === "json") { try { return JSON.parse(state.text); } catch { return null; } }
      if (type === "arraybuffer") return joined();
      if (type === "blob") return new Blob(state.pieces, { type: state.headers?.get("content-type") || "" });
      return state.text;
    };
    const joined = () => { const out = new Uint8Array(state.loaded); let at = 0; for (const p of state.pieces) { out.set(p, at); at += p.length; } return out.buffer; };
    (async () => {
      const port = await bridge.ready;
      if (!port) return sent2.apply(xhr, args);
      let request;
      try {
        const headers = new Headers(asked.headers);
        request = new Request(to.href, { method: asked.method, headers, body: asked.method === "GET" || asked.method === "HEAD" ? undefined : body ?? undefined, signal: controller.signal, credentials: "include" });
      } catch {
        return sent2.apply(xhr, args);
      }
      asked.state = state;
      Object.defineProperties(xhr, {
        readyState: { get: () => state.readyState, configurable: true },
        status: { get: () => state.status, configurable: true },
        statusText: { get: () => state.statusText, configurable: true },
        responseURL: { get: () => state.url, configurable: true },
        responseXML: { get: () => null, configurable: true },
        responseText: { get: () => { if (xhr.responseType && xhr.responseType !== "text") throw new DOMException(en ? "responseType is not text" : "responseType 不是文字", "InvalidStateError"); return state.text; }, configurable: true },
        response: { get: () => (!xhr.responseType || xhr.responseType === "text" ? state.text : whole()), configurable: true },
      });
      fire("loadstart");
      let timer = 0;
      if (xhr.timeout > 0) timer = setTimeout(() => { if (state.over) return; state.over = true; controller.abort(); state.fail("timeout"); }, xhr.timeout);
      try {
        const bytes = asked.method === "GET" || asked.method === "HEAD" ? null : new Uint8Array(await request.clone().arrayBuffer());
        const answer = await bridge(request, bytes);
        if (state.over) return;
        state.status = answer.status; state.statusText = answer.statusText; state.url = answer.url; state.headers = answer.headers;
        state.total = Number(answer.headers.get("content-length")) || 0;
        move(2);
        const charset = /charset=([^;]+)/i.exec(answer.headers.get("content-type") || "")?.[1]?.trim().replace(/"/g, "") || "utf-8";
        let decode;
        try { decode = new TextDecoder(charset); } catch { decode = new TextDecoder(); }
        const text = !xhr.responseType || xhr.responseType === "text" || xhr.responseType === "json";
        if (answer.body) {
          const reader = answer.body.getReader();
          for (;;) {
            const { value, done } = await reader.read();
            if (state.over) return;
            if (done) break;
            state.loaded += value.length;
            if (text) state.text += decode.decode(value, { stream: true }); else state.pieces.push(value);
            move(3);
            fire("progress");
          }
        }
        if (text) state.text += decode.decode();
        state.over = true;
        clearTimeout(timer);
        if (state.readyState < 3) move(3);
        move(4);
        fire("load");
        fire("loadend");
      } catch {
        clearTimeout(timer);
        if (state.over) return;
        state.over = true;
        state.fail("error");
      }
    })();
  };
})();

// Marking the page for a chat's agent (as web/src/annotate/frame.ts does in a preview's frame): told by the app
// (__stillfailMarks.on / remove / clear / scroll), it holds the page's taps while picking, says what was picked
// (StillFailPreviewNative.marked, `picked`) and where the marks are as the page scrolls or moves (`at`, in the
// page's viewport, with its width so the app knows its scale). The app draws the marks, and takes the pictures.
(() => {
  // The words a person may read here in the app's language, which the app says first (PreviewWeb.kt pageScript).
  const en = self.__stillfailLang === "en";
  const native = window.StillFailPreviewNative;
  if (!native || window !== window.top || window.__stillfailMarks) return;
  let on = false;
  let marks = [];
  let next = 1;
  const say = (data) => native.marked(JSON.stringify(data));
  const box = (r) => ({ x: Math.round(r.x), y: Math.round(r.y), width: Math.round(r.width), height: Math.round(r.height) });
  let told = "";
  const draw = () => {
    const at = marks.map((m) => ({ n: m.n, ...box(m.el.isConnected ? m.el.getBoundingClientRect() : m.rect) }));
    const now = JSON.stringify([innerWidth, at]);
    if (now !== told) { told = now; say({ event: "at", at, width: innerWidth, height: innerHeight }); }
  };
  let frame = 0;
  const loop = () => { draw(); frame = on || marks.length ? requestAnimationFrame(loop) : 0; };
  const wake = () => { if (!frame) frame = requestAnimationFrame(loop); };
  const target = (el) => {
    if (!el || !(el instanceof Element)) return null;
    const svg = el.closest("svg");
    return svg && svg !== el ? svg : el;
  };
  const pick = (el) => {
    const had = marks.find((m) => m.el === el);
    if (had) { say({ event: "focus", n: had.n }); return; }
    const r = el.getBoundingClientRect();
    const n = next++;
    marks.push({ n, el, rect: r });
    say({ event: "picked", mark: {
      n, path: location.pathname + location.search + location.hash, viewport: { width: innerWidth, height: innerHeight },
      label: label(el), kind: kindOf(el), selector: selector(el), text: words(el), rect: box(r),
      page: box(new DOMRect(r.left + scrollX, r.top + scrollY, r.width, r.height)), component: component(el),
    } });
    wake();
  };
  const hold = (event) => {
    if (!on) return;
    event.preventDefault();
    event.stopImmediatePropagation();
    if (event.type === "click") { const el = target(event.target); if (el) pick(el); }
  };
  for (const type of ["pointerdown", "pointerup", "mousedown", "mouseup", "click", "dblclick", "auxclick", "contextmenu", "submit"]) document.addEventListener(type, hold, true);
  window.__stillfailMarks = {
    on(value) { on = value; wake(); },
    remove(n) { marks = marks.filter((m) => m.n !== n); told = ""; wake(); },
    clear() { marks = []; next = 1; told = ""; wake(); },
    /** Where a mark is now, in the viewport; `center`: the page scrolled first so that it is in the middle. */
    place(n, center) {
      const m = marks.find((x) => x.n === n);
      if (!m) return null;
      if (center) {
        const r = m.el.isConnected ? m.el.getBoundingClientRect() : m.rect;
        scrollTo({ left: scrollX, top: Math.max(0, r.top + scrollY + r.height / 2 - innerHeight / 2), behavior: "instant" });
      }
      return JSON.stringify({ ...box(m.el.isConnected ? m.el.getBoundingClientRect() : m.rect), width: innerWidth, scrollY });
    },
    back(y) { scrollTo({ left: scrollX, top: y, behavior: "instant" }); },
  };

  /** Names that look made by a build (css-in-js, css modules) say nothing to a person. */
  const made = (name) => /\d{3,}|^css-|^sc-|^_|__[A-Za-z0-9]{5,}$|^[a-z]{1,3}-[A-Za-z0-9]{5,}$/.test(name);
  function label(el) {
    let text = el.localName;
    if (el.id && !made(el.id)) text += "#" + el.id;
    const classes = [...el.classList].filter((c) => !made(c)).slice(0, 3);
    if (classes.length) text += "." + classes.join(".");
    return text;
  }
  const KINDS = en ? {
    button: "button", a: "link", img: "image", svg: "icon", picture: "image", video: "video", input: "input", textarea: "input",
    select: "dropdown", label: "label", h1: "heading", h2: "heading", h3: "heading", h4: "heading", h5: "heading", h6: "heading", p: "paragraph",
    li: "list item", ul: "list", ol: "list", nav: "navigation", header: "header", footer: "footer", table: "table", tr: "table row", td: "cell",
    th: "table header", form: "form", aside: "sidebar", dialog: "dialog", code: "code", pre: "code",
  } : {
    button: "按钮", a: "链接", img: "图片", svg: "图标", picture: "图片", video: "视频", input: "输入框", textarea: "输入框",
    select: "下拉框", label: "标签", h1: "标题", h2: "标题", h3: "标题", h4: "标题", h5: "标题", h6: "标题", p: "段落",
    li: "列表项", ul: "列表", ol: "列表", nav: "导航", header: "页头", footer: "页脚", table: "表格", tr: "表格行", td: "单元格",
    th: "表头", form: "表单", aside: "侧栏", dialog: "对话框", code: "代码", pre: "代码",
  };
  function kindOf(el) {
    const role = el.getAttribute("role");
    if (role === "button") return KINDS.button;
    if (role === "link") return KINDS.a;
    if (el instanceof HTMLInputElement && ["button", "submit", "reset"].includes(el.type)) return KINDS.button;
    if (el instanceof HTMLInputElement && ["checkbox", "radio"].includes(el.type)) return en ? "checkbox" : "选框";
    if (KINDS[el.localName]) return KINDS[el.localName];
    const own = [...el.childNodes].some((n) => n.nodeType === Node.TEXT_NODE && n.textContent.trim());
    return own ? (en ? "text" : "文字") : (en ? "block" : "区块");
  }
  function selector(el) {
    const one = (css) => { try { return document.querySelectorAll(css).length === 1; } catch { return false; } };
    const parts = [];
    for (let node = el; node && node !== document.documentElement; node = node.parentElement) {
      if (node.id && !made(node.id) && one("#" + CSS.escape(node.id))) { parts.unshift("#" + CSS.escape(node.id)); break; }
      const tag = ["data-testid", "data-test", "data-cy", "data-qa"].find((a) => node.hasAttribute(a));
      if (tag) {
        const css = "[" + tag + '="' + CSS.escape(node.getAttribute(tag)) + '"]';
        if (one(css)) { parts.unshift(css); break; }
      }
      let part = node.localName;
      const kin = node.parentElement ? [...node.parentElement.children].filter((c) => c.localName === node.localName) : [];
      if (kin.length > 1) part += ":nth-of-type(" + (kin.indexOf(node) + 1) + ")";
      parts.unshift(part);
      if (node.localName === "body") break;
    }
    return parts.join(" > ");
  }
  function words(el) {
    const cut = (s) => { const t = s.replace(/\s+/g, " ").trim(); return t.length > 80 ? t.slice(0, 80) + "…" : t; };
    if (el instanceof HTMLInputElement || el instanceof HTMLTextAreaElement) return cut(el.value || el.placeholder || "");
    if (el instanceof HTMLImageElement) return cut(el.alt);
    const aria = el.getAttribute("aria-label");
    if (aria) return cut(aria);
    return cut(el.innerText ?? el.textContent ?? "");
  }
  function component(el) {
    const names = [];
    let source = null;
    const fiberKey = Object.keys(el).find((k) => k.startsWith("__reactFiber$"));
    if (fiberKey) {
      for (let fiber = el[fiberKey]; fiber && names.length < 4; fiber = fiber.return) {
        if (!source && fiber._debugSource) source = fiber._debugSource.fileName + ":" + fiber._debugSource.lineNumber;
        const type = fiber.type;
        if (!type || typeof type === "string") continue;
        const name = type.displayName || type.name || (type.render && type.render.name);
        if (name && !names.includes(name) && /^[A-Z]/.test(name)) names.unshift(name);
      }
    } else {
      let node = el;
      while (node && !node.__vueParentComponent) node = node.parentElement;
      for (let c = node ? node.__vueParentComponent : null; c && names.length < 4; c = c.parent) {
        const name = c.type.__name || c.type.name || (c.type.__file && c.type.__file.split("/").pop().replace(/\.vue$/, ""));
        if (!source && c.type.__file) source = c.type.__file;
        if (name && !names.includes(name)) names.unshift(name);
      }
    }
    if (!names.length) return null;
    return names.join(" › ") + (source ? "（" + source + "）" : "");
  }
})();
