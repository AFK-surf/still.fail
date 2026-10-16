// A connection to Chrome's DevTools protocol (CDP) over its WebSocket: requests answered by id, events heard, sessions
// of targets flattened onto it (`sessionId`). The station's browser holds one to watch the tabs, and each screen view
// one of its own, so neither is in the way of the agents' own connections (docs/remote-screens.md).
import WebSocket from "ws";
import { wall } from "../ops/fibers.ts";

export type CdpEvent = { method: string; params: any; sessionId?: string };

export interface Cdp {
  /// A command's result; fails with Chrome's error message, or when the connection is gone.
  send(method: string, params?: object, sessionId?: string): Promise<any>;
  /// Hears every event; the returned function stops hearing.
  on(listener: (event: CdpEvent) => void): () => void;
  /// Settled once the connection is gone, whichever side ended it.
  readonly closed: Promise<void>;
  close(): void;
}

/// How long a connection is given to open, and a command to be answered (Chrome's time: the machine's clock).
const OPEN_MS = 10_000;
const ANSWER_MS = 30_000;

export async function connectCdp(url: string): Promise<Cdp> {
  const ws = new WebSocket(url, { perMessageDeflate: false, maxPayload: 256 * 1024 * 1024 });
  await wall.within(
    OPEN_MS,
    new Promise<void>((resolve, reject) => {
      ws.once("open", () => resolve());
      ws.once("error", reject);
    }),
    `the browser's DevTools did not answer at ${url}`,
  ).catch((e) => {
    ws.terminate();
    throw e;
  });
  let next = 0;
  const pending = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }>();
  const listeners = new Set<(event: CdpEvent) => void>();
  let gone = false;
  let ended!: () => void;
  const closed = new Promise<void>((r) => (ended = r));
  const end = () => {
    if (gone) return;
    gone = true;
    for (const p of pending.values()) p.reject(new Error("the browser's DevTools connection closed"));
    pending.clear();
    ended();
  };
  ws.on("close", end);
  ws.on("error", end);
  ws.on("message", (raw) => {
    let message: any;
    try {
      message = JSON.parse(raw.toString());
    } catch {
      return;
    }
    if (typeof message.id === "number") {
      const p = pending.get(message.id);
      if (p === undefined) return;
      pending.delete(message.id);
      if (message.error) p.reject(new Error(`${message.error.message ?? "CDP error"}${message.error.data ? `: ${message.error.data}` : ""}`));
      else p.resolve(message.result ?? {});
    } else if (typeof message.method === "string") {
      for (const listener of [...listeners]) listener({ method: message.method, params: message.params ?? {}, sessionId: message.sessionId });
    }
  });
  return {
    send(method, params = {}, sessionId) {
      if (gone) return Promise.reject(new Error("the browser's DevTools connection closed"));
      const id = ++next;
      const answer = new Promise<any>((resolve, reject) => pending.set(id, { resolve, reject }));
      ws.send(JSON.stringify(sessionId === undefined ? { id, method, params } : { id, method, params, sessionId }));
      return wall.within(ANSWER_MS, answer, `the browser did not answer ${method}`).finally(() => pending.delete(id));
    },
    on(listener) {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    closed,
    close() {
      if (!gone) ws.close();
      end();
    },
  };
}
