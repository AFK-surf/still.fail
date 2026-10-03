// A station for the core's tests (station.test.ts, core-flows.test.ts): `ws/st` answering its admin API from a table
// ("GET /path" → JSON) over the host's fetch, its events stream fed by `push`.
import { Effect, Queue } from "effect";
import { Core } from "../src/core.ts";
import type { HttpRequest, Pull } from "../src/host.ts";
import { HostWire, type StationWire } from "../src/station/wire.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { signIn } from "./helpers.ts";

export type Answers = Record<string, unknown>;

/// A station `ws/st` answering `answers` ("GET /path" → JSON), and its events stream fed by `push`.
/// Station answers a test gives by code, before the table (`undefined`: the table's).
const replies = new WeakMap<FakeHost, (req: HttpRequest) => unknown>();
export function stationReplies(host: FakeHost, reply: (req: HttpRequest) => unknown): void {
  replies.set(host, reply);
}

export function stationHost(answers: Answers) {
  const host = new FakeHost();
  signIn(host);
  const streams: { path: string; queue: Queue.Queue<Uint8Array | null> }[] = [];
  host.onFetch((req: HttpRequest) => {
    const path = req.url.replace("https://stillfail.test", "");
    if (path === "/v1/me") return jsonResponse(200, { workspaces: [{ id: "ws", name: "W" }], invitations: [], relay_url: null });
    if (path === "/v1/workspaces/ws") return jsonResponse(200, { id: "ws", stations: [{ id: "st", name: "studio", online: true, last_seen: null }] });
    const said = replies.get(host)?.(req);
    if (said !== undefined) return jsonResponse(200, said);
    const key = `${req.method} ${path.replace("/admin/api", "")}`;
    if (key in answers) return jsonResponse(200, answers[key]);
    if (path.startsWith("/admin/api/threads/") && path.includes("/entries")) return jsonResponse(200, { last: 0, entries: [] });
    return jsonResponse(404, { error: "no" });
  });
  host.onFetchStream((req) =>
    Effect.gen(function* () {
      const queue = yield* Queue.unbounded<Uint8Array | null>();
      streams.push({ path: req.url.replace("https://stillfail.test/admin/api", ""), queue });
      const body: Pull<Uint8Array> = { take: Queue.take(queue) };
      return { status: 200, headers: [], body };
    }),
  );
  const push = (name: string, data: unknown) => {
    const s = streams[streams.length - 1];
    Queue.offerUnsafe(s.queue, new TextEncoder().encode(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`));
  };
  const end = () => {
    const s = streams[streams.length - 1];
    Queue.offerUnsafe(s.queue, null);
  };
  return { host, streams, push, end };
}

/// A session as the station lists it (core/tests.rs `session`).
export const session = (key: string, turns = 0) => ({
  key, connect: "ember", scope: "thread", title: null, createdBy: null, boundTo: [], creator: null, participants: [], runtime: "claude", profile: "p1",
  profilePinned: false, model: null, effort: null, runtimeSessionId: null, workspace: "/w", running: false, createdAt: 1, lastActiveAt: 1, archivedAt: null,
  process: "cold", turns, pending: 0, firstText: null, lastTurn: null,
});
export const overview = { viewer: { via: "local" }, connects: [], profiles: [], processes: [], counts: { sessions: 1, running: 0, warm: 0 }, mesh: null, slackUsers: [], slackTeams: [], slackApps: [], disk: null, logins: [] };
export const entry = (n: number, text: string) => ({ thread: 7, n, kind: "message", target: null, ts: `${n}.0`, authorKind: "person", author: "a@x.com", text, at: n });
export const entries = (from: number, to: number) => Array.from({ length: to - from + 1 }, (_, i) => entry(from + i, `m${from + i}`));
export const threadView = (id: number, last: number, read = last, unread = 0) => ({
  id, surface: "ember", channel: "EMBER", channelName: null, threadTs: `${id}.0`, title: null, createdBy: null, creator: null, createdAt: id,
  sessions: [{ thread: id, session: "k1", connect: "ember", joinedAt: 1 }], last, lastMessage: last > 0 ? { seq: last, thread: id, ts: `${last}.0`, authorKind: "agent", author: "k1", authorName: null, text: "…", attachments: [], quotes: [], declared: null, createdAt: last, editedAt: null } : null, read, unread, people: [], firstText: null,
});

export function base(): Answers {
  return {
    "GET /overview": overview,
    "GET /sessions": [session("k1")],
    "GET /sessions/k1": { session: session("k1"), threads: [], turns: [], jobs: [] },
    "GET /threads": [threadView(7, 3)],
    "GET /chats": [{ id: "7", thread: 7, session: "k1", title: "部署", agents: [], lastActiveAt: 1 }],
    "GET /chats?archived=1": [],
    "GET /jobs": [],
    "GET /footprint": {},
    "GET /threads/7/entries?limit=50": { last: 3, entries: entries(1, 3) },
    "GET /sessions/k1/timeline?before=1000000000000000&limit=200": { start: 0, entries: [] },
  };
}

export async function started(answers = base(), sample = 0, wire?: (host: FakeHost) => StationWire) {
  const s = stationHost(answers);
  const core = await Core.create(s.host, { clock: s.host.time.clock, sample, wire: () => (wire ? wire(s.host) : new HostWire(s.host)) });
  await s.host.time.pass(500);
  return { ...s, core };
}

