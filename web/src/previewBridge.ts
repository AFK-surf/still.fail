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

/// The core's call with bytes (CoreClient.callBytes): a request's body beside it, a response's beside its answer and
/// each piece beside its value, never base64.
type Call = (name: string, params: unknown, bytes?: Uint8Array, onProgress?: (value: unknown, bytes?: Uint8Array) => void, signal?: AbortSignal) => Promise<{ value: unknown; bytes?: Uint8Array }>;

export interface Asked { cache?: RequestCache; id: number; method: string; path: string; headers: [string, string][]; body: Uint8Array | null }

/** One request of the frame's, answered whole. */
export interface Answer { status: number; headers: [string, string][]; body: Uint8Array }

/// Bytes the core gave as a buffer of their own, to hand on (transferred) to the frame.
const owned = (bytes: Uint8Array | undefined): Uint8Array<ArrayBuffer> =>
  bytes === undefined ? new Uint8Array() : bytes.byteOffset === 0 && bytes.byteLength === bytes.buffer.byteLength ? bytes as Uint8Array<ArrayBuffer> : bytes.slice();

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
        const got = await call("station.preview", { station, port: service, method: asked.method, path: asked.path, headers: asked.headers }, asked.body ?? undefined);
        const head = got.value as { status: number; headers: [string, string][] };
        return { status: head.status, headers: head.headers, body: owned(got.bytes) };
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
    const onProgress = (value: unknown, bytes?: Uint8Array) => {
      if (stop.signal.aborted) return;
      const v = value as { head?: Pick<Answer, "status" | "headers">; chunk?: boolean };
      if (v.head) {
        head = v.head;
        collect = cached.collect(head);
        revalidated = cached.revalidated(head);
        if (!revalidated) { cached.discard(); post({ id: asked.id, head }); }
      } else if (v.chunk === true && !revalidated) {
        const chunk = owned(bytes);
        length += chunk.length;
        if (collect && length <= cached.maxBody) chunks.push(chunk.slice());
        else chunks = [];
        post({ id: asked.id, chunk }, [chunk.buffer]);
      }
    };
    call("station.preview", { station, port: service, method: asked.method, path: asked.path, headers: cached.headers, stream: true }, asked.body ?? undefined, onProgress, stop.signal).then(
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
    const onProgress = (value: unknown, bytes?: Uint8Array) => {
      const v = value as { open?: { protocol: string }; text?: string; binary?: boolean };
      if (v.open) post({ type: "socket-open", sid, protocol: v.open.protocol });
      else if (typeof v.text === "string") post({ type: "socket-message", sid, text: v.text });
      else if (v.binary === true) {
        const binary = owned(bytes);
        post({ type: "socket-message", sid, binary }, [binary.buffer]);
      }
    };
    call("preview.socket", { station, port: service, path, headers, socket: sid }, undefined, onProgress, stop.signal).then(
      (closed) => {
        const { code, reason } = closed.value as { code: number; reason: string };
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
      // A binary frame's bytes beside the call (`binary: true`).
      const binary = data.binary instanceof Uint8Array ? data.binary as Uint8Array : undefined;
      const message = typeof data.text === "string" ? { text: data.text }
        : binary ? { binary: true }
        : Array.isArray(data.close) ? { close: [Number(data.close[0]) || 1000, String(data.close[1] ?? "")] }
        : null;
      if (!message) return;
      // A socket whose station is gone: its close follows from the socket's own call. A close that did not get there
      // stops the socket's call instead, so nothing is left open for a page that let it go.
      call("preview.socket.send", { socket: sid, ...message }, binary).catch(() => {
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
