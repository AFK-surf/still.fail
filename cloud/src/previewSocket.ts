// What makes a web service's WebSockets work in its preview, on the web (cloud/src/preview.ts) and in the desktop app
// (apps/desktop/src/main.ts): a script first in each of the service's pages gives it a WebSocket that, for the
// preview's own host (a dev server's live reload), goes to the station and on to the service's port; any other stays
// the browser's own. How it gets there is each host's `link`.
import { browserWords } from "./i18n.ts";

/**
 * The page's script. `link` is JavaScript for an expression that gives `(path, protocols, on) => ({ send, close })`,
 * or null to leave the page as it is: `on.open(protocol)`, `on.message(text | Uint8Array)`, `on.close(code, reason,
 * failed)` say what the socket does; `send(text | Uint8Array)` and `close(code, reason)` do it.
 */
export function socketScript(link: string): string {
  return `(() => {
  const link = ${link};
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
      if (to.protocol !== "ws:" && to.protocol !== "wss:") throw new DOMException(${browserWords("cloud.preview.socket.notWebSocket", { url: "url" })}, "SyntaxError");
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
      if (this.readyState === 0) throw new DOMException(${browserWords("cloud.preview.socket.notOpen")}, "InvalidStateError");
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
      (shared ? worker.port : worker).postMessage({ stillfailSockets: port2 }, [port2]);
      return worker;
    };
    Wrapped.prototype = Native.prototype;
    return Wrapped;
  };
  if (window.Worker) window.Worker = wrap(window.Worker, false);
  if (window.SharedWorker) window.SharedWorker = wrap(window.SharedWorker, true);
})();
`;
}

// First in the code of a worker a service's page makes (see socketScript): its WebSockets to the preview's own host
// go through the page, over the port the page hands it first (a message it never sees).
const WORKER_SOCKET = `(() => {
  const Native = self.WebSocket;
  let relay = null;
  const queued = [];
  const sockets = new Map();
  let next = 0;
  const post = (message) => (relay ? relay.postMessage(message) : queued.push(message));
  const take = (event) => {
    if (!(event.data && event.data.stillfailSockets instanceof MessagePort)) return;
    event.stopImmediatePropagation();
    relay = event.data.stillfailSockets;
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
      if (this.readyState === 0) throw new DOMException(${browserWords("cloud.preview.socket.notOpen")}, "InvalidStateError");
      if (this.readyState === 1) post({ id: this._id, send: data });
    }
    close(code, reason) {
      if (this.readyState >= 2) return;
      this.readyState = 2;
      post({ id: this._id, close: [code ?? 1000, reason ?? ""] });
    }
  }
  Object.assign(WorkerSocket.prototype, { CONNECTING: 0, OPEN: 1, CLOSING: 2, CLOSED: 3 });
  self.WebSocket = WorkerSocket;
})();
`;

/**
 * A `link` over the page's own requests, for a host that answers them itself (the desktop app's stillfail-preview://):
 * `GET /_ember/socket/<id>?path=&protocols=` opens the socket and streams what happens on it, `POST /_ember/socket/<id>`
 * sends one message. Both are framed as the station frames a socket (client/core/src/station.rs, SocketFrame: a kind
 * byte, the length in 4 bytes big-endian, the payload), with kind 0 for its opening (the sub-protocol).
 */
export const FETCH_LINK = `(path, protocols, on) => {
  const at = "/_ember/socket/" + crypto.randomUUID();
  const stop = new AbortController();
  const utf8 = new TextEncoder();
  const text = new TextDecoder();
  const frame = (kind, payload) => {
    const out = new Uint8Array(5 + payload.length);
    out[0] = kind;
    new DataView(out.buffer).setUint32(1, payload.length);
    out.set(payload, 5);
    return out;
  };
  let ended = false;
  const end = (code, reason, failed) => {
    if (ended) return;
    ended = true;
    stop.abort();
    on.close(code, reason, failed);
  };
  fetch(at + "?path=" + encodeURIComponent(path) + "&protocols=" + encodeURIComponent(protocols.join(",")), { signal: stop.signal, cache: "no-store" })
    .then(async (answer) => {
      if (!answer.ok || !answer.body) return end(1006, "", true);
      const reader = answer.body.getReader();
      let buf = new Uint8Array(0);
      for (;;) {
        const { value, done } = await reader.read();
        if (done) return end(1006, "", true);
        const joined = new Uint8Array(buf.length + value.length);
        joined.set(buf);
        joined.set(value, buf.length);
        buf = joined;
        while (buf.length >= 5) {
          const len = new DataView(buf.buffer, buf.byteOffset).getUint32(1);
          if (buf.length < 5 + len) break;
          const kind = buf[0];
          const payload = buf.slice(5, 5 + len);
          buf = buf.slice(5 + len);
          if (kind === 0) on.open(text.decode(payload));
          else if (kind === 1) on.message(text.decode(payload));
          else if (kind === 2) on.message(payload);
          else if (kind === 8) {
            const code = payload.length >= 2 ? (payload[0] << 8) | payload[1] : 1005;
            return end(code, text.decode(payload.slice(2)), code === 1006);
          }
        }
      }
    })
    .catch(() => end(1006, "", true));
  // One after another, in the order sent; kept alive, so a close sent as the page goes still gets there.
  let sending = Promise.resolve();
  const post = (bytes, failed = () => {}) => {
    sending = sending.then(() => fetch(at, { method: "POST", body: bytes, keepalive: true }).then((r) => { if (!r.ok) failed(); }, failed));
  };
  return {
    send: (data) => post(typeof data === "string" ? frame(1, utf8.encode(data)) : frame(2, data)),
    // A close that did not get there stops the socket's stream instead: nothing is left open.
    close: (code, reason) => post(frame(8, new Uint8Array([code >> 8, code & 255, ...utf8.encode(reason)])), () => stop.abort()),
  };
}`;

/**
 * What puts socketScript into a page of the service, first in its <head>: `withSocketTag(body)`, a page's body with the
 * script's tag in it. JavaScript, for the web's service worker (cloud/src/preview.ts) to carry as it is; the desktop app
 * runs it in its main process. The tag goes after the <head> tag, else after <html>, else after the doctype, else
 * first; the page's first bytes wait until <head> or <html> is there (or 4 KB, or the end), so it never goes before a
 * doctype cut in two. Tags are ASCII: the bytes are searched as they are, whatever the page's encoding.
 */
export const SOCKET_TAG_JS = `
const SOCKET_TAG = new TextEncoder().encode('<script src="/_ember/socket.js"></script>');
function socketTagAt(bytes, whole) {
  const text = String.fromCharCode(...bytes.subarray(0, 4096)).toLowerCase();
  // All there is to wait for: the doctype, or the very start, will do.
  const last = whole || bytes.length >= 4096;
  for (const tag of last ? [/<head[\\s>]/, /<html[\\s>]/, /<!doctype[\\s>]/] : [/<head[\\s>]/, /<html[\\s>]/]) {
    const at = text.search(tag);
    if (at >= 0) {
      const end = text.indexOf(">", at);
      if (end >= 0) return end + 1;
    }
  }
  return last ? 0 : -1;
}
function withSocketTag(body) {
  let head = new Uint8Array(0);
  let placed = false;
  const place = (out, whole) => {
    const at = socketTagAt(head, whole);
    if (at < 0) return;
    placed = true;
    out.enqueue(head.subarray(0, at));
    out.enqueue(SOCKET_TAG);
    out.enqueue(head.subarray(at));
  };
  return body.pipeThrough(new TransformStream({
    transform(chunk, out) {
      if (placed) return out.enqueue(chunk);
      const joined = new Uint8Array(head.length + chunk.length);
      joined.set(head);
      joined.set(chunk, head.length);
      head = joined;
      place(out, false);
    },
    flush(out) {
      if (!placed && head.length) place(out, true);
    },
  }));
}
`;

type WithSocketTag = (body: ReadableStream<Uint8Array>) => ReadableStream<Uint8Array>;
let made: WithSocketTag | null = null;

/** SOCKET_TAG_JS's `withSocketTag`, here (the desktop app's main process; made when first used). */
export function withSocketTag(body: ReadableStream<Uint8Array>): ReadableStream<Uint8Array> {
  made ??= new Function(`${SOCKET_TAG_JS}\nreturn withSocketTag;`)() as WithSocketTag;
  return made(body);
}
