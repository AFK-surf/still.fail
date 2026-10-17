// The WebView end of a web service's preview (Preview.tsx): what the web's preview frame, its service worker and
// previewBridge.ts do there (cloud/src/preview.ts, web/src/previewBridge.ts), for a WebView that is the page itself.
// Every request the page makes of its own host is answered here from the station through the core (station.preview,
// as it comes: an event stream, a long poll, a big file go on as the station sends them), and stopped at the station
// when the page gives it up. The page's own script (page.js, first in each of its pages) carries its WebSockets
// (preview.socket), its requests' bodies (which a WebView never hands over) and marking the page through
// StillFailPreviewNative, here a script put in the page ahead of its own that says each call to the app as a message
// (react-native-webview has no JavascriptInterface). No port on the station is open to anyone.
import type { CoreClient } from "../../../../web/src/core/client.ts";
import { CoreError } from "../../../../web/src/core/client.ts";
import type { ShouldStartLoadRequest, WebViewNavigation } from "react-native-webview/lib/WebViewTypes";
import { lang, t } from "../i18n";
import { fromBase64, toBase64 } from "../data/Calls";

/** The host the WebView loads the service at: nothing answers it but the core. */
export const PREVIEW_HOST = "preview.stillfail.invalid";
/** page.js as served, the language now said first (its words for a person are in it, in both). */
export function pageScript(script: string): string {
  return `self.__stillfailLang = "${lang()}";\n` + script;
}

/** The page's own script, served here (never asked of the service). */
const PAGE_JS = "/_stillfail/page.js";
const BODY_HEADER = "x-stillfail-body";
/** How long a request waits for its answer's head. */
const HEAD_WAIT_S = 60;
/**
 * How much of an answer waits here for the WebView to read it. The station sends as it has it (the core's calls have
 * no way to hold it back): an answer that gets this far ahead of its reader is stopped.
 */
const BUFFERED_MAX = 32 << 20;

/** Where one cookie ends in a Set-Cookie header holding several (an Expires date's comma is not followed by name=). */
const COOKIES_JOINED = /,\s*(?=[!#$%&'*+.^_`|~0-9A-Za-z-]+=)/;

/** A URL's parts (react-native's URL has no getters for them): its scheme, host, path and query. */
export function urlParts(url: string): { scheme: string; host: string; path: string; query: string | null } | null {
  const m = /^([a-zA-Z][a-zA-Z0-9+.-]*):(?:\/\/([^/?#]*))?([^?#]*)(?:\?([^#]*))?/.exec(url);
  if (!m) return null;
  return { scheme: m[1]!.toLowerCase(), host: (m[2] ?? "").replace(/^[^@]*@/, "").replace(/:\d+$/, "").toLowerCase(), path: m[3] ?? "", query: m[4] ?? null };
}

/** A path on the service, as the WebView has it: its path and query. */
export function pathOf(url: string): string {
  const u = urlParts(url);
  if (!u) return "/";
  return (u.path || "/") + (u.query !== null ? `?${u.query}` : "");
}

/** `location` resolved against the page at `path` (java.net.URI.resolve): a path of the preview's host, or another host. */
function resolve(path: string, location: string): { host: string | null; path: string } {
  const abs = urlParts(location);
  if (abs && /^[a-z]/i.test(location) && location.includes(":")) {
    if (abs.scheme !== "http" && abs.scheme !== "https") return { host: abs.scheme, path: "/" };
    return { host: abs.host, path: (abs.path.startsWith("/") ? abs.path : "/") + (abs.query !== null ? `?${abs.query}` : "") };
  }
  if (location.startsWith("//")) { const u = urlParts("https:" + location)!; return { host: u.host, path: (u.path || "/") + (u.query !== null ? `?${u.query}` : "") }; }
  const base = path.split("?")[0]!;
  const [rel, query] = location.split(/\?(.*)/s) as [string, string | undefined];
  let joined = rel.startsWith("/") ? rel : rel === "" ? base : base.substring(0, base.lastIndexOf("/") + 1) + rel;
  // Dot segments, as a URI resolves them.
  const out: string[] = [];
  for (const seg of joined.split("/")) { if (seg === "..") { if (out.length > 1) out.pop(); } else if (seg !== ".") out.push(seg); }
  joined = out.join("/");
  if (!joined.startsWith("/")) joined = "/" + joined;
  return { host: null, path: joined + (query !== undefined ? `?${query}` : rel === "" ? (path.includes("?") ? "?" + path.split("?")[1] : "") : "") };
}

/**
 * The preview host's cookies (the WebView's own CookieManager in the Android app): what the service sets kept, sent
 * along with what is asked of it.
 */
// NATIVE: the WebView's own cookie store (CookieManager) is not reachable from here (no cookies module): the preview's
// cookies are kept in this jar instead, which the page's document.cookie does not share.
export const PreviewCookies = new (class {
  readonly #jar = new Map<string, string>();
  getCookie(_url: string): string | null {
    const all = [...this.#jar].map(([k, v]) => `${k}=${v}`).join("; ");
    return all.length > 0 ? all : null;
  }
  setCookie(_url: string, header: string) {
    const [pair, ...attrs] = header.split(";");
    const at = pair!.indexOf("=");
    if (at <= 0) return;
    const name = pair!.substring(0, at).trim();
    const value = pair!.substring(at + 1).trim();
    const gone = attrs.some((a) => {
      const [k, v] = a.split("=").map((s) => s.trim()) as [string, string | undefined];
      if (/^max-age$/i.test(k) && v !== undefined && Number(v) <= 0) return true;
      if (/^expires$/i.test(k) && v !== undefined && Date.parse(v) < Date.now()) return true;
      return false;
    });
    if (gone) this.#jar.delete(name); else this.#jar.set(name, value);
  }
})();

/** What an answer of the page's own host is, as a WebView takes it (WebResourceResponse). */
export interface PreviewResponse {
  mime: string; charset: string | null; status: number; reason: string; headers: Record<string, string>;
  /** Read a piece at a time, as the WebView reads it; closed, it stops coming. */
  body: Readable;
}

/** A body read a piece at a time (java.io.InputStream): null at its end. */
export interface Readable {
  read(max: number): Promise<Uint8Array | null>;
  close(): void;
}

/** A WebView request of the page's own host (WebResourceRequest). */
export interface PreviewRequest { method: string; url: string; headers: Record<string, string>; isForMainFrame: boolean }

/** What a page's WebView can be asked to do (the Android WebView's methods the preview uses). */
export interface PreviewWebView {
  injectJavaScript(code: string): void;
  reload(): void;
  goBack(): void;
  goForward(): void;
  loadUrl(url: string): void;
  /** Its size in the app's pixels (dp), as it is laid out. */
  width: number;
  height: number;
}

/** An answer's head, its body to come (read from `body`, closed to stop it). */
class Head {
  constructor(readonly status: number, readonly headers: [string, string][], readonly body: Chunks) {}
}

/** Why a request got no answer from the service: said to the page with `status`. */
class Unanswered extends Error {
  constructor(readonly status: number, message: string) { super(message); }
}

/** An answer, where it came from in the end (after its redirects) and whether it was redirected there. */
class Answer {
  constructor(readonly head: Head, readonly path: string, readonly redirected: boolean) {}
}

/** The WebView wants a reason phrase with every status. */
const reason = (status: number) => (status >= 200 && status <= 299 ? "OK" : status === 404 ? "Not Found" : status >= 500 && status <= 599 ? "Error" : "Status");

const TOKEN = /^[!#$%&'*+.^_`|~0-9A-Za-z-]{1,256}$/;
const enc = (text: string) => { const out: number[] = []; for (const ch of unescape(encodeURIComponent(text))) out.push(ch.charCodeAt(0)); return new Uint8Array(out); };

/**
 * One preview's page: its WebView's requests, sockets and marks, for the service at `port` of `station`. Whatever is
 * under way is stopped with `close` (the page gone).
 */
export class PreviewLink {
  web: PreviewWebView | null = null;
  /** What the page's marking says (its JSON). */
  onMarked: (said: Record<string, unknown>) => void = () => undefined;
  /** What a visualization's page keeps (its widget's state), said through StillFailViz. */
  onViz: ((json: string) => void) | null = null;
  /**
   * Answers the page's requests here instead of the station (a visualization's page, which is a file, not a service:
   * web Preview.tsx FileFrame's `serve`): its method and path in, the answer out.
   */
  serve: ((method: string, path: string) => PreviewResponse) | null = null;
  /** A picture of what the page shows now (Preview.tsx takes it of the WebView), its file's uri and size in pixels. */
  shot: () => Promise<{ uri: string; width: number; height: number } | null> = async () => null;

  /** Requests' bodies the page left here, by the id its request carries. */
  readonly #bodies = new Map<string, { bytes: Uint8Array; type: string | null }>();
  /** The page's WebSockets still open, by the name the page gave each. */
  readonly #sockets = new Map<string, AbortController>();
  /** What the page sends on its sockets, in the order it sent it. */
  readonly #outgoing: Record<string, unknown>[] = [];
  #sending = false;
  #closed = false;
  /** Everything under way, stopped on close. */
  readonly #scope = new AbortController();
  /** The page's fetches under way, by the id the page gave each. */
  readonly #fetches = new Map<string, AbortController>();
  #fetchPort = false;
  readonly #evals = new Map<number, (v: string | null) => void>();
  #nextEval = 0;

  constructor(private readonly core: CoreClient, private readonly station: string, private readonly port: number, private readonly script: string) {}

  /** The page gone: everything under way stopped. */
  close(): void;
  /** The page's socket `sid` closed with `code` and `reason` (page.js's native.close). */
  close(sid: string, code: number, reason: string): void;
  close(sid?: string, code?: number, why?: string) {
    if (sid === undefined) {
      this.#closed = true;
      this.#outgoing.length = 0;
      this.#scope.abort();
      return;
    }
    if (!this.#sockets.has(sid)) return;
    this.#queue({ socket: sid, close: [code ?? 1000, why ?? ""] });
  }

  #queue(message: Record<string, unknown>) {
    if (this.#closed) return;
    this.#outgoing.push(message);
    if (this.#sending) return;
    this.#sending = true;
    void (async () => {
      while (this.#outgoing.length > 0 && !this.#closed) {
        const m = this.#outgoing.shift()!;
        try {
          await this.core.call("preview.socket.send", m);
        } catch {
          // Its station is gone: its close follows from the socket's own call. A close that did not get there stops
          // the socket's call instead, so nothing is left open for a page that let it go.
          if ("close" in m) this.#sockets.get(String(m.socket))?.abort();
        }
      }
      this.#sending = false;
    })();
  }

  /** A new page: the sockets of the one before go with it. */
  pageStarted() {
    for (const s of this.#sockets.values()) s.abort();
    this.#sockets.clear();
    this.#bodies.clear();
    this.#dropFetches();
  }

  #js(code: string) { this.web?.injectJavaScript(`${code};true;`); }
  #q(text: string) { return JSON.stringify(text); }

  /** What the page's script said through StillFailPreviewNative (as a message: the script put ahead of the page's). */
  said(data: string) {
    let m: Record<string, unknown>;
    try { m = JSON.parse(data) as Record<string, unknown>; } catch { return; }
    const s = (k: string) => (typeof m[k] === "string" ? (m[k] as string) : "");
    switch (m.m) {
      case "open": return this.open(s("sid"), s("path"), s("protocols"));
      case "send": return this.send(s("sid"), s("text"));
      case "sendBinary": return this.sendBinary(s("sid"), s("b"));
      case "close": return this.close(s("sid"), typeof m.code === "number" ? m.code : 1000, s("reason"));
      case "stash": return this.stash(s("id"), s("b"), s("type"));
      case "marked": return this.marked(s("json"));
      case "fetchPort": this.#fetchPort = true; return;
      case "fetch": if (this.#fetchPort) this.#fetchSaid(s("data")); return;
      case "viz": this.onViz?.(s("json")); return;
      case "eval": { const done = this.#evals.get(Number(m.id)); this.#evals.delete(Number(m.id)); done?.(typeof m.v === "string" ? m.v : null); return; }
    }
  }

  // ── the page's script calls these (StillFailPreviewNative) ──

  open(sid: string, path: string, protocols: string) {
    const event = (kind: string, args: string) => this.#js(`window.__stillfailSocketEvent&&__stillfailSocketEvent(${this.#q(sid)},${this.#q(kind)}${args})`);
    const stop = new AbortController();
    this.#scope.signal.addEventListener("abort", () => stop.abort(), { once: true });
    this.#sockets.set(sid, stop);
    void (async () => {
      let closed: Record<string, unknown> | null = null;
      try {
        closed = (await this.core.call("preview.socket", {
          station: this.station, port: this.port, path, socket: sid,
          headers: protocols.length > 0 ? [["sec-websocket-protocol", protocols]] : [],
        }, (v) => {
          const o = v as Record<string, unknown> | null;
          if (!o || typeof o !== "object") return;
          if (o.open && typeof o.open === "object") event("open", `,${this.#q(String((o.open as { protocol?: string }).protocol ?? ""))}`);
          else if (typeof o.text === "string") event("text", `,${JSON.stringify(o.text)}`);
          else if (typeof o.binary === "string") event("binary", `,${JSON.stringify(o.binary)}`);
        }, stop.signal)) as Record<string, unknown> | null;
      } catch (e) {
        if (stop.signal.aborted) { if (this.#sockets.get(sid) === stop) this.#sockets.delete(sid); return; }
        if (!(e instanceof CoreError)) throw e;
        closed = null;
      }
      const code = typeof closed?.code === "number" ? closed.code : 1006;
      const why = typeof closed?.reason === "string" ? closed.reason : "";
      event("close", `,${code},${this.#q(why)},${code === 1006}`);
      if (this.#sockets.get(sid) === stop) this.#sockets.delete(sid);
    })();
  }

  send(sid: string, text: string) { if (this.#sockets.has(sid)) this.#queue({ socket: sid, text }); }

  sendBinary(sid: string, base64: string) { if (this.#sockets.has(sid)) this.#queue({ socket: sid, binary: base64 }); }

  stash(id: string, base64: string, type: string) {
    this.#bodies.set(id, { bytes: fromBase64(base64), type: type.length > 0 ? type : null });
  }

  marked(json: string) {
    let said: Record<string, unknown>;
    try { said = JSON.parse(json) as Record<string, unknown>; } catch { return; }
    if (!said || typeof said !== "object") return;
    this.onMarked(said);
  }

  /** Runs the page's script, and hands back what it returned (as evaluateJavascript does: its value as JSON). */
  eval(code: string): Promise<string | null> {
    const id = ++this.#nextEval;
    return new Promise((done) => {
      this.#evals.set(id, done);
      this.#js(`(function(){var v;try{v=(${code});}catch(e){v=null;}if(v===undefined)v=null;window.ReactNativeWebView.postMessage(JSON.stringify({m:"eval",id:${id},v:JSON.stringify(v)}));})()`);
    });
  }

  // ── the page's fetch() (page.js), answered as it comes ──
  // A WebView hands the page what its request interceptor answers only once its buffer (2 KB) is full, so a body that
  // comes a line at a time would reach the page in lumps. The page's fetch() of its own host comes here instead, over
  // a message port only the page's top frame holds: its head, then each piece of its body as the station sends it.
  // It can only ask the service at `port` of `station`, like every other request of the page's.

  /** A new page: the port and fetches of the one before go with it. */
  #dropFetches() {
    this.#fetchPort = false;
    for (const f of this.#fetches.values()) f.abort();
    this.#fetches.clear();
  }

  /** What the page says on its port: `go` (a request), `stop` (one it gave up). Anything else is let go. */
  #fetchSaid(data: string) {
    let o: Record<string, unknown>;
    try { o = JSON.parse(data) as Record<string, unknown>; } catch { return; }
    if (!o || typeof o !== "object") return;
    const id = typeof o.id === "string" && o.id.length > 0 && o.id.length <= 64 ? o.id : null;
    if (id === null) return;
    if (o.t === "stop") { this.#fetches.get(id)?.abort(); this.#fetches.delete(id); return; }
    if (o.t !== "go") return;
    const tell = (reply: Record<string, unknown>) => { if (this.#fetchPort) this.#js(`window.__stillfailFetchReply&&__stillfailFetchReply(${JSON.stringify(JSON.stringify(reply))})`); };
    const failed = (message: string) => tell({ t: "error", id, message });
    const m = typeof o.method === "string" ? o.method.toUpperCase() : null;
    const method = m !== null && /^[A-Z]{1,16}$/.test(m) ? m : null;
    const p = typeof o.path === "string" ? o.path : null;
    // eslint-disable-next-line no-control-regex
    const path = p !== null && p.startsWith("/") && p.length <= 16384 && !/[\u0000- \u007f]/.test(p) ? p : null;
    let headers: [string, string][] | null;
    try {
      headers = ((Array.isArray(o.headers) ? o.headers : []) as unknown[]).slice(0, 200).map((pair) => {
        const a = pair as unknown[];
        return [String(a[0]), String(a[1])] as [string, string];
      }).filter(([k, v]) => TOKEN.test(k) && !/[\r\n]/.test(v) && k.toLowerCase() !== "host" && k.toLowerCase() !== BODY_HEADER);
    } catch { headers = null; }
    let body: Uint8Array | null = null;
    try { body = typeof o.body === "string" && o.body.length > 0 ? fromBase64(o.body) : null; } catch { return failed(t("android-chat.web.badBody")); }
    if (method === null || path === null || headers === null || this.#fetches.has(id)) return failed(t("android-chat.web.badRequest"));
    const follow = o.redirect !== "manual" && o.redirect !== "error";
    const withCookies = o.cookies !== false && o.cookies !== "false";
    const stop = new AbortController();
    this.#scope.signal.addEventListener("abort", () => stop.abort(), { once: true });
    this.#fetches.set(id, stop);
    void (async () => {
      try {
        let answer: Answer;
        try {
          answer = await this.#follow(method, path, headers, body, follow, stop.signal, withCookies);
        } catch (e) {
          if (!(e instanceof Unanswered)) throw e;
          // As the WebView's own requests have it (answer): said as the answer, in words.
          tell({ t: "head", id, status: e.status, statusText: reason(e.status), path, redirected: false, headers: [["content-type", "text/plain; charset=utf-8"]] });
          tell({ t: "chunk", id, b: toBase64(enc(e.message)) });
          tell({ t: "end", id });
          return;
        }
        const head = answer.head;
        tell({ t: "head", id, status: head.status, statusText: reason(head.status), path: answer.path, redirected: answer.redirected, headers: head.headers });
        // Each piece as it comes (a read gives what is there, never waiting for more).
        try {
          for (;;) {
            const piece = await head.body.read(256 << 10);
            if (piece === null) break;
            if (piece.length > 0) tell({ t: "chunk", id, b: toBase64(piece) });
          }
          head.body.close();
          tell({ t: "end", id });
        } catch (e) {
          failed((e instanceof Error ? e.message : "") || t("android-chat.web.cut"));
        }
      } catch {
        // Stopped (the page gave it up, or went).
      } finally {
        if (this.#fetches.get(id) === stop) this.#fetches.delete(id);
      }
    })();
  }

  // ── the WebView's requests ──

  /** Asks the station, and waits until the answer's head is there (a minute at most). */
  #ask(method: string, path: string, headers: [string, string][], body: Uint8Array | null, within: AbortSignal = this.#scope.signal): Promise<Head> {
    const chunks = new Chunks();
    const stop = new AbortController();
    const off = () => stop.abort();
    within.addEventListener("abort", off, { once: true });
    return new Promise<Head>((resolve, reject) => {
      let headed = false;
      const timer = setTimeout(() => {
        if (headed) return;
        stop.abort();
        reject(new Error(t("android-chat.web.timeout", { s: HEAD_WAIT_S })));
      }, HEAD_WAIT_S * 1000);
      // The page gave it up (read to its end, or let go), or left it unread too long: the station stops asking the service.
      chunks.onClose = () => stop.abort();
      this.core.call("station.preview", {
        station: this.station, port: this.port, method, path, stream: true,
        body: body ? toBase64(body) : "",
        headers,
      }, (v) => {
        const o = v as Record<string, unknown> | null;
        if (!o || typeof o !== "object") return;
        const h = o.head as { status: number; headers?: [string, string][] } | undefined;
        if (h && typeof h === "object") {
          headed = true;
          clearTimeout(timer);
          resolve(new Head(h.status, (h.headers ?? []).map(([k, v2]) => [String(k), String(v2)] as [string, string]), chunks));
        } else if (typeof o.chunk === "string") chunks.put(fromBase64(o.chunk));
      }, stop.signal).then(
        () => { chunks.end(null); clearTimeout(timer); if (!headed) reject(new Error(t("android-chat.web.noAnswer"))); },
        (e: unknown) => {
          clearTimeout(timer);
          within.removeEventListener("abort", off);
          if (stop.signal.aborted) { chunks.end(null); if (!headed) reject(new Error(t("android-chat.web.cancelled"))); return; }
          const message = e instanceof Error ? e.message : String(e);
          chunks.end(new Error(message));
          if (!headed) reject(e instanceof Error ? e : new Error(message));
        },
      );
    });
  }

  /**
   * Asks the station, following the service's redirects as a browser does (5 at most, to the service only), with the
   * preview's cookies (sent along, and what the service sets kept). `follow` false: a redirect is the answer (its
   * body closed). Throws Unanswered.
   */
  async #follow(method0: string, path0: string, headers0: [string, string][], body: Uint8Array | null, follow: boolean, within: AbortSignal = this.#scope.signal, withCookies = true): Promise<Answer> {
    let method = method0;
    let bytes = body;
    let path = path0;
    let headers = headers0;
    const given = !withCookies || headers.some(([k]) => k.toLowerCase() === "cookie");
    for (let hop = 0; hop < 6; hop++) {
      const url = `https://${PREVIEW_HOST}${path}`;
      const cookie = given ? null : PreviewCookies.getCookie(url);
      const asked: [string, string][] = cookie ? [...headers, ["Cookie", cookie]] : headers;
      let head: Head;
      try {
        head = await this.#ask(method, path, asked, bytes, within);
      } catch (e) {
        throw new Unanswered(502, t("android-chat.web.unreachable", { error: e instanceof Error ? e.message : String(e) }));
      }
      // Several cookies may come joined in one header (", " before the next name=): each is kept.
      if (withCookies) for (const [k, v] of head.headers) if (k.toLowerCase() === "set-cookie") for (const one of v.split(COOKIES_JOINED)) PreviewCookies.setCookie(url, one);
      const location = head.headers.find(([k]) => k.toLowerCase() === "location")?.[1];
      if (head.status < 300 || head.status > 399 || location === undefined) return new Answer(head, path, hop > 0);
      if (!follow) { head.body.close(); return new Answer(head, path, hop > 0); }
      head.body.close();
      if (hop === 5) throw new Unanswered(508, t("android-chat.web.redirects"));
      let next: { host: string | null; path: string };
      try { next = resolve(path, location.trim()); } catch { throw new Unanswered(502, t("android-chat.web.badRedirect", { location })); }
      if (next.host !== null && next.host !== "localhost" && next.host !== "127.0.0.1" && next.host !== PREVIEW_HOST) throw new Unanswered(502, t("android-chat.web.offsite", { location }));
      path = next.path.startsWith("/") ? next.path : "/";
      if (head.status === 303 || ((head.status === 301 || head.status === 302) && method === "POST")) {
        method = "GET"; bytes = null;
        headers = headers.filter(([k]) => k.toLowerCase() !== "content-type" && k.toLowerCase() !== "content-length");
      }
    }
    throw new Unanswered(508, t("android-chat.web.redirects"));
  }

  /**
   * Answers a request of the preview's host from the station (following redirects here: a WebView takes no 3xx).
   */
  // NATIVE: react-native-webview has no request interceptor (WebViewClient.shouldInterceptRequest): a native WebView
  // that hands each request of PREVIEW_HOST to `answer` and streams its body back as it reads it is missing. Until it
  // is there, Preview.tsx loads the page's own documents through `answer` (the page's fetch() goes through its port);
  // what a document asks of its host itself (its scripts, styles, pictures) does not load.
  async answer(request: PreviewRequest): Promise<PreviewResponse> {
    const path = pathOf(request.url);
    if (path.split("?")[0] === PAGE_JS) {
      return { mime: "text/javascript", charset: "utf-8", status: 200, reason: "OK", headers: { "Cache-Control": "no-store" }, body: once(enc(pageScript(this.script))) };
    }
    if (this.serve) return this.serve(request.method, path);
    const asked = { ...request.headers };
    const bodyKey = Object.keys(asked).find((k) => k.toLowerCase() === BODY_HEADER);
    let body: { bytes: Uint8Array; type: string | null } | undefined;
    if (bodyKey !== undefined) { const id = asked[bodyKey]!; delete asked[bodyKey]; body = this.#bodies.get(id); this.#bodies.delete(id); }
    if (body?.type && !Object.keys(asked).some((k) => k.toLowerCase() === "content-type")) asked["Content-Type"] = body.type;
    const page = request.isForMainFrame || Object.entries(asked).some(([k, v]) => k.toLowerCase() === "accept" && v.startsWith("text/html"));
    let head: Head;
    try {
      head = (await this.#follow(request.method, path, Object.entries(asked), body?.bytes ?? null, true)).head;
    } catch (e) {
      if (e instanceof Unanswered) return text(e.status, e.message);
      throw e;
    }
    const type = head.headers.find(([k]) => k.toLowerCase() === "content-type")?.[1] ?? "application/octet-stream";
    const mime = type.split(";")[0]!.trim();
    const charset = /charset=([^;]+)/.exec(type)?.[1]?.trim().replace(/^"|"$/g, "") ?? null;
    const encoded = head.headers.some(([k, v]) => k.toLowerCase() === "content-encoding" && v.toLowerCase() !== "identity");
    // A page of the service gets its script first (its sockets, its bodies, its marks).
    const tagged = page && mime === "text/html" && !encoded;
    head.body.events = mime === "text/event-stream" && !encoded;
    const out: Readable = tagged ? new WithTag(head.body) : head.body;
    const headers: Record<string, string> = {};
    for (const [k, v] of head.headers) {
      if (tagged && k.toLowerCase() === "content-length") continue;
      headers[k] = headers[k] !== undefined ? `${headers[k]}, ${v}` : v;
    }
    const status = head.status >= 200 && head.status <= 599 && !(head.status >= 300 && head.status <= 399) ? head.status : 200;
    return { mime, charset, status, reason: reason(status), headers, body: out };
  }
}

/** A body that is all here already. */
function once(bytes: Uint8Array): Readable {
  let given = false;
  return { read: async () => (given ? null : ((given = true), bytes)), close: () => undefined };
}

function text(status: number, message: string): PreviewResponse {
  return { mime: "text/plain", charset: "utf-8", status, reason: reason(status), headers: {}, body: once(enc(message)) };
}

/** A whole answer read to its end, as text (what Preview.tsx shows of a page's document while no interceptor serves it). */
export async function readAll(body: Readable): Promise<Uint8Array> {
  const parts: Uint8Array[] = [];
  let n = 0;
  for (;;) { const p = await body.read(256 << 10); if (p === null) break; parts.push(p); n += p.length; }
  body.close();
  const out = new Uint8Array(n);
  let at = 0;
  for (const p of parts) { out.set(p, at); at += p.length; }
  return out;
}

const END = Symbol("end");

/**
 * A body as the station sends it: pieces put here as they come, read by the WebView; closed, it stops coming. At most
 * BUFFERED_MAX of it waits: past that it is stopped (`onClose`) and its reader told so.
 */
class Chunks implements Readable {
  readonly #queue: (Uint8Array | Error | typeof END)[] = [];
  #wake: (() => void) | null = null;
  /** Bytes put and not yet taken by the reader. */
  #waiting = 0;
  #over = false;
  #current: Uint8Array | null = null;
  #at = 0;
  #done = false;
  #closed = false;
  #gave = false;
  #lastByte = 0;
  /** An event stream (text/event-stream): what comes goes to the page at once. */
  events = false;
  onClose: () => void = () => undefined;

  #offer(item: Uint8Array | Error | typeof END) { this.#queue.push(item); const w = this.#wake; this.#wake = null; w?.(); }

  put(bytes: Uint8Array) {
    if (bytes.length === 0 || this.#over || this.#closed) return;
    this.#waiting += bytes.length;
    if (this.#waiting > BUFFERED_MAX) {
      this.#over = true;
      this.#offer(new Error(t("android-chat.web.slow")));
      this.onClose();
      return;
    }
    this.#offer(bytes);
  }
  end(error: Error | null) { this.#offer(error ?? END); }

  async #next(): Promise<boolean> {
    while (this.#current === null || this.#at >= this.#current.length) {
      if (this.#done) return false;
      while (this.#queue.length === 0) await new Promise<void>((w) => { this.#wake = w; });
      const item = this.#queue.shift()!;
      if (item instanceof Uint8Array) { this.#current = item; this.#at = 0; this.#waiting -= item.length; }
      else if (item instanceof Error) { this.#done = true; throw item; }
      else { this.#done = true; return false; }
    }
    return true;
  }

  async read(len: number): Promise<Uint8Array | null> {
    if (len === 0) return new Uint8Array(0);
    // The WebView reads on until its buffer is full before it hands anything to the page. An event stream's events
    // are to come as they are sent: with nothing more here yet, after a piece that ended its line, the rest of the
    // buffer is filled with a comment (which the page's EventSource passes over).
    if (this.events && this.#gave && this.#lastByte === 0x0a && (this.#current === null || this.#at >= this.#current.length) && this.#queue.length === 0 && !this.#done && !this.#closed) {
      this.#gave = false;
      if (len === 1) return new Uint8Array([0x0a]);
      const b = new Uint8Array(len).fill(0x20);
      b[0] = 0x3a;
      b[len - 1] = 0x0a;
      return b;
    }
    if (this.#closed || !(await this.#next())) return null;
    const n = Math.min(len, this.#current!.length - this.#at);
    const out = this.#current!.subarray(this.#at, this.#at + n);
    this.#at += n;
    this.#gave = true;
    this.#lastByte = out[n - 1]!;
    return out;
  }

  available(): number { return this.#current ? this.#current.length - this.#at : 0; }

  close() {
    if (this.#closed) return;
    this.#closed = true;
    this.onClose();
  }
}

/**
 * A page's body with its script's tag in it (as the web's service worker puts it, cloud/src/previewSocket.ts
 * SOCKET_TAG_JS): after the <head> tag, else after <html>, else after the doctype, else first; the first bytes wait
 * until <head> or <html> is there (or 4 KB, or the end), so it never goes before a doctype cut in two.
 */
class WithTag implements Readable {
  static readonly TAG = enc(`<script src="${PAGE_JS}"></script>`);
  #start: Uint8Array | null = null;
  #at = 0;
  constructor(private readonly body: Readable) {}

  async #begin(): Promise<Uint8Array> {
    if (this.#start) return this.#start;
    let head = new Uint8Array(0);
    let whole = false;
    let place = -1;
    while (place < 0) {
      const n = await this.body.read(Math.max(1, 4096 - head.length));
      if (n === null) whole = true;
      else { const next = new Uint8Array(head.length + n.length); next.set(head); next.set(n, head.length); head = next; }
      const last = whole || head.length >= 4096;
      place = this.#tagAt(head, last);
      if (place < 0 && last) place = 0;
    }
    const out = new Uint8Array(head.length + WithTag.TAG.length);
    out.set(head.subarray(0, place));
    out.set(WithTag.TAG, place);
    out.set(head.subarray(place), place + WithTag.TAG.length);
    this.#start = out;
    return out;
  }

  #tagAt(bytes: Uint8Array, last: boolean): number {
    let s = "";
    for (let i = 0; i < Math.min(bytes.length, 4096); i++) s += String.fromCharCode(bytes[i]!);
    const lower = s.toLowerCase();
    const tags = last ? [/<head[\s>]/, /<html[\s>]/, /<!doctype[\s>]/] : [/<head[\s>]/, /<html[\s>]/];
    for (const tag of tags) {
      const found = tag.exec(lower);
      if (!found) continue;
      const end = lower.indexOf(">", found.index);
      if (end >= 0) return end + 1;
    }
    return -1;
  }

  async read(len: number): Promise<Uint8Array | null> {
    const s = await this.#begin();
    if (this.#at < s.length) {
      const n = Math.min(len, s.length - this.#at);
      const out = s.subarray(this.#at, this.#at + n);
      this.#at += n;
      return out;
    }
    return this.body.read(len);
  }

  close() { this.body.close(); }
}

/**
 * The script put in each page ahead of its own (main frame only): StillFailPreviewNative's calls said to the app as
 * messages, the page's fetch port made here in the page (a MessageChannel whose far end the app answers through
 * __stillfailFetchReply), and a visualization's StillFailViz. `served`: a file's page (it has no port: its requests
 * are answered here).
 */
export function nativeShim(served: boolean): string {
  return `(function(){
  if (window.StillFailPreviewNative) return;
  var post = function (m) { window.ReactNativeWebView.postMessage(JSON.stringify(m)); };
  var asked = false;
  window.StillFailPreviewNative = {
    open: function (sid, path, protocols) { post({ m: "open", sid: sid, path: path, protocols: protocols }); },
    send: function (sid, text) { post({ m: "send", sid: sid, text: text }); },
    sendBinary: function (sid, b) { post({ m: "sendBinary", sid: sid, b: b }); },
    close: function (sid, code, reason) { post({ m: "close", sid: sid, code: code, reason: reason }); },
    stash: function (id, b, type) { post({ m: "stash", id: id, b: b, type: type }); },
    marked: function (json) { post({ m: "marked", json: json }); },
    fetchPort: function (token) {
      if (${served ? "true" : "false"} || !token || token.length > 64) return false;
      if (asked) return true;
      asked = true;
      var ch = new MessageChannel();
      ch.port1.onmessage = function (e) { post({ m: "fetch", data: String(e.data) }); };
      window.__stillfailFetchReply = function (s) { ch.port1.postMessage(s); };
      post({ m: "fetchPort" });
      // As the app's own message: no window sent it.
      setTimeout(function () { window.dispatchEvent(new MessageEvent("message", { data: token, source: null, ports: [ch.port2] })); }, 0);
      return true;
    },
  };
  window.StillFailViz = { post: function (json) { post({ m: "viz", json: String(json) }); } };
})();true;`;
}

/**
 * Answers the WebView's requests for the preview's host from the station; anything else goes to the network. Only the
 * preview's host is a page here (it has StillFailPreviewNative): a link to anywhere else goes to `leave` (the app opens
 * it the way it opens links elsewhere). While the WebView has no request interceptor, the page's own documents are
 * loaded here (`load`) and handed to it with the host as their base, as `document` says.
 */
export class PreviewClient {
  /** The document the WebView shows now, loaded through the link (null: none yet). */
  document: { html: string; baseUrl: string } | null = null;
  /** Where each page went, for back and forward. */
  #history: string[] = [];
  #at = -1;
  #loading = 0;

  constructor(
    private readonly link: PreviewLink,
    private readonly moved: (at: string | null, canBack: boolean, canForward: boolean) => void,
    private readonly started: () => void,
    private readonly loaded: () => void,
    private readonly leave: (url: string) => void,
    private readonly shown: (doc: { html: string; baseUrl: string }) => void,
  ) {}

  get canGoBack() { return this.#at > 0; }
  get canGoForward() { return this.#at < this.#history.length - 1; }

  /** The page at `path` of the service (a navigation of the main frame): asked through the link, shown once it is here. */
  async load(path: string, push = true, method = "GET") {
    const n = ++this.#loading;
    this.link.pageStarted();
    this.started();
    if (push) { this.#history = this.#history.slice(0, this.#at + 1); this.#history.push(path); this.#at = this.#history.length - 1; }
    this.moved(path, this.canGoBack, this.canGoForward);
    let html: string;
    try {
      const got = await this.link.answer({ method, url: `https://${PREVIEW_HOST}${path}`, headers: { Accept: "text/html" }, isForMainFrame: true });
      const bytes = await readAll(got.body);
      html = decodeText(bytes);
    } catch (e) {
      html = e instanceof Error ? e.message : String(e);
    }
    if (n !== this.#loading) return;
    this.document = { html, baseUrl: `https://${PREVIEW_HOST}${path}` };
    this.shown(this.document);
  }
  reload() { const p = this.#history[this.#at]; if (p !== undefined) void this.load(p, false); }
  goBack() { if (this.canGoBack) { this.#at--; void this.load(this.#history[this.#at]!, false); } }
  goForward() { if (this.canGoForward) { this.#at++; void this.load(this.#history[this.#at]!, false); } }

  /** shouldOverrideUrlLoading: the preview's own pages loaded here; anything else of the main frame left to `leave`. */
  shouldOverrideUrlLoading = (request: ShouldStartLoadRequest): boolean => {
    const url = request.url;
    const u = urlParts(url);
    const main = request.isTopFrame !== false;
    if (u && u.host === PREVIEW_HOST && (u.scheme === "https" || u.scheme === "http")) {
      // The document handed over (its base is this URL) loads as it is; a link to another page of the host comes here.
      if (this.document && url === this.document.baseUrl && request.navigationType !== "click") return false;
      if (!main) return false;
      void this.load(pathOf(url));
      return true;
    }
    // A frame in the page may show what it likes; the page itself stays the preview's.
    if (!main) return false;
    if (u?.scheme === "about") return false;
    if (u && ["data", "blob", "javascript"].includes(u.scheme)) return true;
    this.leave(url);
    return true;
  };

  /** react-native-webview's onShouldStartLoadWithRequest: true lets the WebView load it. */
  onShouldStart = (request: ShouldStartLoadRequest) => !this.shouldOverrideUrlLoading(request);

  // Where it is, as the page moves (a link, its own history, a reload): for the bar.
  onNavigationStateChange = (v: WebViewNavigation) => {
    const u = urlParts(v.url);
    const at = u && u.host === PREVIEW_HOST ? pathOf(v.url) : v.url;
    this.moved(at, this.canGoBack || v.canGoBack, this.canGoForward || v.canGoForward);
  };
  onLoadEnd = () => { this.loaded(); };
}

/** A document's bytes as text (UTF-8, as the Kotlin's String does). */
function decodeText(bytes: Uint8Array): string {
  const D = (globalThis as { TextDecoder?: new (l?: string) => { decode(b: Uint8Array): string } }).TextDecoder;
  if (D) return new D("utf-8").decode(bytes);
  try { let s = ""; for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]!); return decodeURIComponent(escape(s)); } catch { return ""; }
}

/** A value the page's script returned (as JSON): the JSON string it returned, read. */
export function returned(value: string | null): unknown {
  if (value === null || value === "null") return null;
  try {
    const outer = JSON.parse(value) as unknown;
    const inner = typeof outer === "string" ? (JSON.parse(outer) as unknown) : outer;
    return inner ?? null;
  } catch {
    return null;
  }
}
