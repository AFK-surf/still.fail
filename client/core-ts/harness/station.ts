// A station for the side-by-side runs (harness/run.ts): its admin API at the fake cloud's origin, where both cores'
// stations answer over the host's fetch (Rust's testing::HostWire, the TS core's HostWire). Every station of the
// workspace is this one. Plain data, so a script can change it between steps; `event` sends on every open `/events`.
import type { IncomingMessage, ServerResponse } from "node:http";
import { T0 } from "./cloud.ts";

const session = (key: string) => ({
  key, connect: "ember", scope: "thread", title: null, createdBy: null, boundTo: [], creator: null, participants: [], runtime: "claude", profile: "p1",
  profilePinned: false, model: null, effort: null, runtimeSessionId: null, workspace: "/w", running: false, createdAt: T0 * 1000, lastActiveAt: T0 * 1000, archivedAt: null,
  process: "cold", turns: 0, pending: 0, firstText: null, lastTurn: null,
});

export type Entry = { thread: number; n: number; kind: string; target: number | null; ts: string; authorKind: string; author: string; authorName: string | null; text: string; at: number; attachments: unknown[]; quotes: unknown[]; declared: null };

export class FakeStation {
  readonly entries: Entry[] = [];
  readonly streams = new Set<ServerResponse>();
  read = 3;

  constructor() {
    for (let n = 1; n <= 3; n++) this.entries.push(this.#entry(n, n % 2 === 1 ? "person" : "agent", `第 ${n} 条`));
  }

  #entry(n: number, kind: string, text: string): Entry {
    const person = kind === "person";
    return { thread: 7, n, kind: "message", target: null, ts: `${T0 + n}.0`, authorKind: kind, author: person ? "alice@x.test" : "k1", authorName: person ? "Alice" : null, text, at: (T0 + n) * 1000, attachments: [], quotes: [], declared: null };
  }

  get last(): number {
    return this.entries.length;
  }

  #message(e: Entry) {
    return { seq: e.n, thread: 7, ts: e.ts, authorKind: e.authorKind, author: e.author, authorName: e.authorName, text: e.text, attachments: [], quotes: [], declared: null, createdAt: e.at, editedAt: null };
  }

  thread() {
    const last = this.entries.at(-1)!;
    return {
      id: 7, surface: "ember", channel: "EMBER", channelName: null, threadTs: "7.0", title: "部署", createdBy: "alice@x.test", creator: null, createdAt: T0 * 1000,
      sessions: [{ thread: 7, session: "k1", connect: "ember", joinedAt: T0 * 1000 }], last: this.last, lastMessage: this.#message(last), read: this.read, unread: Math.max(0, this.last - this.read), people: [], firstText: null,
    };
  }

  row() {
    const last = this.entries.at(-1)!;
    return {
      id: "7", thread: 7, session: "k1", title: "部署", mine: true, pinned: false, keep: false, createdAt: T0 * 1000, lastActiveAt: last.at,
      agents: [{ key: "k1", connect: "ember", runtime: "claude", profile: "p1", process: "cold", pending: 0, title: null, lastTurn: null }],
      last: this.#message(last), unread: this.read < this.last,
    };
  }

  /// A message said in the chat (an agent's reply, a person's elsewhere), told on every stream.
  say(kind: string, text: string): void {
    const e = this.#entry(this.last + 1, kind, text);
    this.entries.push(e);
    this.event("thread", { id: 7, entries: [e] });
    this.event("chat", this.row());
  }

  event(name: string, data: unknown): void {
    for (const res of this.streams) res.write(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`);
  }

  close(): void {
    for (const res of this.streams) res.end();
    this.streams.clear();
  }

  /// Answers `/admin/api/<path>`; false when it is no station's.
  handle(req: IncomingMessage, res: ServerResponse, url: URL, body: Record<string, unknown>): boolean {
    if (!url.pathname.startsWith("/admin/api/")) return false;
    const path = url.pathname.slice("/admin/api".length);
    const q = url.searchParams;
    const method = req.method ?? "GET";
    const send = (status: number, value: unknown) => {
      res.writeHead(status, { "content-type": "application/json" });
      res.end(JSON.stringify(value));
    };
    const page = (list: Entry[]) => send(200, { last: this.last, entries: list });
    if (path === "/events") {
      res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache" });
      res.write(": hello\n\n");
      this.streams.add(res);
      req.on("close", () => this.streams.delete(res));
      return true;
    }
    if (path === "/overview") {
      send(200, { viewer: { via: "mesh", email: "alice@x.test", admin: true }, connects: [{ id: "ember", name: "still.fail", team: null, enabled: true, kind: "ember", mode: "multi-session", requireMention: false, bind: { runtime: "claude", model: null, effort: null, profile: null }, slack: { appToken: "", botToken: "" }, connection: { state: "connected" }, createdBy: null, sessions: 1, session: null }], profiles: [], processes: [], counts: { sessions: 1, running: 0, warm: 0 }, mesh: null, slackUsers: [], slackTeams: [], slackApps: [], disk: null, logins: [] });
      return true;
    }
    if (path === "/sessions") return send(200, [session("k1")]), true;
    if (path === "/sessions/k1") return send(200, { session: session("k1"), threads: [this.thread()], turns: [], jobs: [] }), true;
    if (path === "/sessions/k1/timeline") return send(200, { start: 0, entries: [] }), true;
    if (path === "/threads" && method === "GET") return send(200, [this.thread()]), true;
    if (path === "/threads/7" && method === "GET") return send(200, this.thread()), true;
    if (path === "/chats") return send(200, q.get("archived") === "1" ? [] : [this.row()]), true;
    if (path === "/jobs") return send(200, []), true;
    if (path === "/footprint") return send(200, {}), true;
    if (path === "/usage") return send(200, { days: [], total: {} }), true;
    if (path === "/threads/7/entries") {
      const after = q.get("after");
      const before = q.get("before");
      const from = q.get("from");
      const limit = Number(q.get("limit") ?? 50);
      if (after !== null) return page(this.entries.filter((e) => e.n > Number(after))), true;
      if (from !== null) return page(this.entries.filter((e) => e.n >= Number(from) && e.n <= Number(q.get("to")))), true;
      const below = before !== null ? this.entries.filter((e) => e.n < Number(before)) : this.entries;
      return page(below.slice(-limit)), true;
    }
    if (path === "/threads/7/messages" && method === "POST") {
      const e = this.#entry(this.last + 1, "person", String(body.text ?? ""));
      this.entries.push(e);
      this.read = e.n;
      send(200, { n: e.n });
      this.event("thread", { id: 7, entries: [e] });
      this.event("chat", this.row());
      return true;
    }
    if (path === "/threads/7/read" && method === "PUT") {
      this.read = Math.max(this.read, Number(body.n ?? 0));
      send(200, { viewer: "alice@x.test", thread: 7, n: this.read });
      this.event("read", { viewer: "alice@x.test", thread: 7, n: this.read });
      return true;
    }
    if (/^\/profiles\/[^/]+\/check$/.test(path)) return send(200, {}), true;
    send(404, { error: "no such route" });
    return true;
  }
}
