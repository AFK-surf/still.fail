// The still.fail page's end of a preview frame's port (cloud/src/preview.ts): the service's requests and WebSockets, on to
// the station through the core, and their answers back.
//
// Frame → here: a request `{id, method, path, headers, body}`; `{type: "cancel", id}` when its page gave it up;
// `{type: "socket", sid, path, protocols}` for a WebSocket of the service, `{type: "socket-send", sid, text | binary |
// close: [code, reason]}` for what the page sends on it.
// Here → frame: with `streams` (a frame that says it takes them), a request's answer as it comes — `{id, head: {status,
// headers}}`, `{id, chunk}` for each piece of the body, `{id, end: true}`, or `{id, error}` — and a socket's
// `{type: "socket-open", sid, protocol}`, `{type: "socket-message", sid, text | binary}`, `{type: "socket-close", sid,
// code, reason, failed}`. An older frame gets the answer whole, `{id, status, headers, body}`, and asks for no socket.

import { PreviewCache } from "./previewCache.ts";
import { t } from "./i18n.ts";

type Call = (name: string, params?: unknown, onProgress?: (value: unknown) => void, signal?: AbortSignal) => Promise<unknown>;

export interface Asked { cache?: RequestCache; id: number; method: string; path: string; headers: [string, string][]; body: Uint8Array | null }

/** One request of the frame's, answered whole. */
export interface Answer { status: number; headers: [string, string][]; body: Uint8Array }

function toBase64(bytes: Uint8Array): string {
  let text = "";
  for (let i = 0; i < bytes.length; i += 0x8000) text += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(text);
}

const fromBase64 = (text: string) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));

const failure = (error: unknown) => t("web-main.preview.fetchFailed", { error: error instanceof Error ? error.message : String(error) });

/**
 * Serves `port` (the frame's) until the returned function is called, which stops whatever is still under way.
 * `serve` answers the requests here instead of the station (a visualization); `streams`: the frame takes answers as
 * they come and asks for sockets.
 */
export function bridge(port: MessagePort, { call, station, service, serve, streams }:
  { call: Call; station: string; service: number; serve?: () => ((asked: Asked) => Promise<Answer>) | undefined; streams: boolean }): () => void {
  // What is under way, by request id (`r<id>`) or socket (`s<sid>`): stopped when its page gives it up, or with the frame.
  const running = new Map<string, AbortController>();
  const cache = new PreviewCache();
  const post = (message: unknown, transfer: Transferable[] = []) => {
    try { port.postMessage(message, transfer); } catch { /* the frame went */ }
  };
  const whole = async (asked: Asked) => {
    try {
      const own = serve?.();
      const answer: Answer = own ? await own(asked) : await (async () => {
        const got = await call("station.preview", {
          station, port: service, method: asked.method, path: asked.path, headers: asked.headers, body: asked.body ? toBase64(asked.body) : "",
        }) as { status: number; headers: [string, string][]; body: string };
        return { status: got.status, headers: got.headers, body: fromBase64(got.body) };
      })();
      if (streams) {
        post({ id: asked.id, head: { status: answer.status, headers: answer.headers } });
        post({ id: asked.id, chunk: answer.body }, [answer.body.buffer]);
        post({ id: asked.id, end: true });
      } else {
        post({ id: asked.id, status: answer.status, headers: answer.headers, body: answer.body }, [answer.body.buffer]);
      }
    } catch (error) {
      post({ id: asked.id, error: failure(error) });
    }
  };
  const streamed = (asked: Asked) => {
    const cached = cache.prepare(asked);
    const complete = (answer: Answer) => {
      post({ id: asked.id, head: { status: answer.status, headers: answer.headers } });
      post({ id: asked.id, chunk: answer.body }, [answer.body.buffer]);
      post({ id: asked.id, end: true });
    };
    if (cached.fresh) { complete(cached.fresh); return; }
    const stop = new AbortController();
    const key = `r${asked.id}`;
    running.set(key, stop);
    let head: Pick<Answer, "status" | "headers"> | undefined;
    let revalidated: Answer | undefined;
    let chunks: Uint8Array[] = [];
    let length = 0;
    let collect = false;
    const onProgress = (value: unknown) => {
      if (stop.signal.aborted) return;
      const v = value as { head?: Pick<Answer, "status" | "headers">; chunk?: string };
      if (v.head) {
        head = v.head;
        collect = cached.collect(head);
        revalidated = cached.revalidated(head);
        if (!revalidated) { cached.discard(); post({ id: asked.id, head }); }
      } else if (typeof v.chunk === "string" && !revalidated) {
        const chunk = fromBase64(v.chunk);
        length += chunk.length;
        if (collect && length <= cached.maxBody) chunks.push(chunk.slice());
        else chunks = [];
        post({ id: asked.id, chunk }, [chunk.buffer]);
      }
    };
    call("station.preview", {
      station, port: service, method: asked.method, path: asked.path, headers: cached.headers, body: asked.body ? toBase64(asked.body) : "", stream: true,
    }, onProgress, stop.signal).then(
      () => {
        if (stop.signal.aborted) return;
        if (revalidated) { cached.save(revalidated); complete(revalidated); return; }
        if (collect && head && length <= cached.maxBody) {
          const body = new Uint8Array(length);
          let at = 0;
          for (const chunk of chunks) { body.set(chunk, at); at += chunk.length; }
          cached.save({ ...head, body });
        }
        post({ id: asked.id, end: true });
      },
      (error: unknown) => { if (!stop.signal.aborted) post({ id: asked.id, error: failure(error) }); },
    ).finally(() => running.delete(key));
  };
  const socket = (sid: string, path: string, protocols: string[]) => {
    const stop = new AbortController();
    const key = `s${sid}`;
    running.set(key, stop);
    const headers: [string, string][] = protocols.length ? [["sec-websocket-protocol", protocols.join(", ")]] : [];
    const onProgress = (value: unknown) => {
      const v = value as { open?: { protocol: string }; text?: string; binary?: string };
      if (v.open) post({ type: "socket-open", sid, protocol: v.open.protocol });
      else if (typeof v.text === "string") post({ type: "socket-message", sid, text: v.text });
      else if (typeof v.binary === "string") {
        const binary = fromBase64(v.binary);
        post({ type: "socket-message", sid, binary }, [binary.buffer]);
      }
    };
    call("preview.socket", { station, port: service, path, headers, socket: sid }, onProgress, stop.signal).then(
      (closed) => {
        const { code, reason } = closed as { code: number; reason: string };
        post({ type: "socket-close", sid, code, reason, failed: code === 1006 });
      },
      () => post({ type: "socket-close", sid, code: 1006, reason: "", failed: true }),
    ).finally(() => running.delete(key));
  };
  port.onmessage = ({ data }: MessageEvent) => {
    if (data?.type === "cancel") {
      running.get(`r${data.id}`)?.abort();
      return;
    }
    if (data?.type === "socket") {
      socket(String(data.sid), String(data.path), Array.isArray(data.protocols) ? data.protocols.map(String) : []);
      return;
    }
    if (data?.type === "socket-send") {
      const sid = String(data.sid);
      if (!running.has(`s${sid}`)) return;
      const message = typeof data.text === "string" ? { text: data.text }
        : data.binary instanceof Uint8Array ? { binary: toBase64(data.binary) }
        : Array.isArray(data.close) ? { close: [Number(data.close[0]) || 1000, String(data.close[1] ?? "")] }
        : null;
      if (!message) return;
      // A socket whose station is gone: its close follows from the socket's own call. A close that did not get there
      // stops the socket's call instead, so nothing is left open for a page that let it go.
      call("preview.socket.send", { socket: sid, ...message }).catch(() => {
        if ("close" in message) running.get(`s${sid}`)?.abort();
      });
      return;
    }
    const asked = data as Asked;
    if (streams && !serve?.()) streamed(asked);
    else void whole(asked);
  };
  return () => {
    port.onmessage = null;
    for (const stop of running.values()) stop.abort();
    running.clear();
    cache.clear();
    port.close();
  };
}
