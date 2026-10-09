// A station for the core's tests (station.test.ts, core-flows.test.ts): `ws/st` answering its admin API from a table
// ("GET /path" → JSON) over the host's fetch, its events stream fed by `push`.
import { Effect, Queue } from "effect";
import { zstdCompressSync } from "node:zlib";
import { Core } from "../src/core.ts";
import type { HttpRequest, HttpResponse, Pull } from "../src/host.ts";
import { HostWire, type StationWire } from "../src/station/wire.ts";
import { FakeHost, jsonResponse } from "../src/testing.ts";
import { HostError } from "../src/error.ts";
import { digest } from "../src/digest.ts";
import { signIn } from "./helpers.ts";

export type Answers = Record<string, unknown>;

/// A station `ws/st` answering `answers` ("GET /path" → JSON), and its events stream fed by `push`.
/// An answer with a status of its own (a station reply that is not 200).
export class Status {
  readonly code: number;
  readonly body: unknown;
  constructor(code: number, body: unknown) {
    this.code = code;
    this.body = body;
  }
}
export const status = (code: number, body: unknown) => new Status(code, body);

/// Station answers a test gives by code, before the table (`undefined`: the table's; a `Status`: that status).
const replies = new WeakMap<FakeHost, (req: HttpRequest) => unknown>();
export function stationReplies(host: FakeHost, reply: (req: HttpRequest) => unknown): void {
  replies.set(host, reply);
}

/// Whether a request asks its answer compressed, as the core's do (requests.ts ZSTD).
const asksCompressed = (req: HttpRequest) => req.headers.some(([k, v]) => k.toLowerCase() === "accept-encoding" && v.split(",").some((e) => e.trim() === "zstd"));

/// An answer as the station sends it to a core that asks (station/src/mesh/compress.ts): JSON from 512 bytes compressed.
function compressedFor(req: HttpRequest, res: HttpResponse): HttpResponse {
  if (!asksCompressed(req) || res.body.length < 512) return res;
  return { ...res, headers: [...res.headers, ["content-encoding", "zstd"]], body: new Uint8Array(zstdCompressSync(res.body)) };
}

/// A stream's chunks as zstd, made at once (the clock here does not wait on a compressor): one frame, each chunk a raw
/// block of it, so it is read as it comes as the station's is (station/test/compress.test.ts compresses it for real).
function zstdBlocks(): (chunk: Uint8Array) => Uint8Array {
  let started = false;
  return (chunk) => {
    const parts: Uint8Array[] = started ? [] : [new Uint8Array([0x28, 0xb5, 0x2f, 0xfd, 0x00, 0x50])];
    started = true;
    for (let at = 0; at < chunk.length; at += 128 * 1024) {
      const data = chunk.subarray(at, at + 128 * 1024);
      const head = data.length << 3;
      parts.push(new Uint8Array([head & 255, (head >> 8) & 255, (head >> 16) & 255]), data);
    }
    return new Uint8Array(Buffer.concat(parts));
  };
}

/// What changed of a list as the station answers it (station/src/read/digest.ts `changedOf`): the list as its GET
/// answers, its order, and its rows whose digest is not the one held.
function changedOf(whole: HttpResponse, id: string, req: HttpRequest): HttpResponse {
  if (whole.status !== 200) return whole;
  const rows = JSON.parse(new TextDecoder().decode(whole.body)) as Record<string, unknown>[];
  const held = (JSON.parse(new TextDecoder().decode(req.body ?? new Uint8Array())) as { held: Record<string, string> }).held;
  return jsonResponse(200, { order: rows.map((r) => r[id]), rows: rows.filter((r) => held[String(r[id])] !== digest(r)) });
}

export function stationHost(answers: Answers) {
  const host = new FakeHost();
  signIn(host);
  const streams: { path: string; queue: Queue.Queue<Uint8Array | null>; closed: boolean }[] = [];
  host.onFetch((req: HttpRequest) => compressedFor(req, answer(req)));
  // How it answers what changed of a list (POST /changed/<list>) and several reads in one (POST /batch): `false`, as a
  // station from before (no such route).
  const changes = { on: true };
  const batches = { on: true };
  // Whether still.fail cloud lists the station as online.
  const cloud = { online: true };
  const answer = (req: HttpRequest): HttpResponse => {
    const path = req.url.replace("https://stillfail.test", "");
    if (path === "/v1/me") return jsonResponse(200, { workspaces: [{ id: "ws", name: "W" }], invitations: [], relay_url: null });
    if (path === "/v1/workspaces/ws") return jsonResponse(200, { id: "ws", stations: [{ id: "st", name: "studio", online: cloud.online, last_seen: null }] });
    const said = replies.get(host)?.(req);
    if (said instanceof Status) return jsonResponse(said.code, said.body);
    if (said !== undefined) return jsonResponse(200, said);
    if (req.method === "POST" && path === "/admin/api/batch") {
      if (!batches.on) return jsonResponse(404, { error: "no route POST /batch" });
      const gets = (JSON.parse(new TextDecoder().decode(req.body ?? new Uint8Array())) as { gets: string[] }).gets;
      const answers = gets.map((g) => {
        const a = answer({ ...req, method: "GET", url: `https://stillfail.test/admin/api${g}`, body: null });
        return { status: a.status, body: a.body.length > 0 ? JSON.parse(new TextDecoder().decode(a.body)) : null };
      });
      return jsonResponse(200, { answers });
    }
    const list = /^\/admin\/api\/changed\/(chats|threads|sessions)(\?|$)/.exec(path);
    if (req.method === "POST" && list) {
      if (!changes.on) return jsonResponse(404, { error: `no route POST ${path.replace("/admin/api", "").split("?")[0]}` });
      return changedOf(answer({ ...req, method: "GET", url: req.url.replace("/admin/api/changed/", "/admin/api/"), body: null }), list[1] === "sessions" ? "key" : "id", req);
    }
    const key = `${req.method} ${path.replace("/admin/api", "")}`;
    if (key in answers) return answers[key] instanceof Status ? jsonResponse((answers[key] as Status).code, (answers[key] as Status).body) : jsonResponse(200, answers[key]);
    if (path.startsWith("/admin/api/threads/") && path.includes("/entries")) return jsonResponse(200, { last: 0, entries: [] });
    return jsonResponse(404, { error: "no" });
  };
  // How its events stream answers: opens, fails (the station is not reached), hangs (a try that takes long), or a
  // status of its own; `resumes`: one asked `since` an event says it was told first what came after it.
  const gate: { stream: "open" | "fail" | "hang" | number; resumes: boolean } = { stream: "open", resumes: false };
  host.onFetchStream((req) =>
    Effect.gen(function* () {
      if (gate.stream === "fail") return yield* Effect.fail(new HostError("连不上"));
      if (gate.stream === "hang") return yield* Effect.never;
      if (typeof gate.stream === "number") {
        const said = new TextEncoder().encode('{"error":"没有权限"}');
        let given = false;
        return { status: gate.stream, headers: [], body: { take: Effect.sync(() => (given ? null : ((given = true), said))) } };
      }
      const queue = yield* Queue.unbounded<Uint8Array | null>();
      const path = req.url.replace("https://stillfail.test/admin/api", "");
      const open = { path, queue, closed: false };
      yield* Effect.addFinalizer(() => Effect.sync(() => (open.closed = true)));
      streams.push(open);
      // It opens as the station's does (a reader of zstd starts once it has 18 bytes), and asked compressed, each chunk
      // goes as it comes.
      Queue.offerUnsafe(queue, new TextEncoder().encode("retry: 3000\n\n"));
      const compress = asksCompressed(req) ? zstdBlocks() : null;
      const body: Pull<Uint8Array> = { take: Effect.map(Queue.take(queue), (c) => (c && compress ? compress(c) : c)) };
      const headers: [string, string][] = [...(gate.resumes && path.includes("since=") ? [["stillfail-resumed", "1"] as [string, string]] : []), ...(compress ? [["content-encoding", "zstd"] as [string, string]] : [])];
      return { status: 200, headers, body };
    }),
  );
  /// Sends an event on the newest open stream.
  const push = (name: string, data: unknown) => {
    const s = [...streams].reverse().find((x) => !x.closed)!;
    Queue.offerUnsafe(s.queue, new TextEncoder().encode(`event: ${name}\ndata: ${JSON.stringify(data)}\n\n`));
  };
  const end = () => {
    const s = streams[streams.length - 1];
    Queue.offerUnsafe(s.queue, null);
  };
  return { host, streams, push, end, gate, changes, batches, cloud };
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
    "GET /sessions/k1/timeline?before=1000000000000000&limit=200&brief=1": { start: 0, entries: [] },
  };
}

export async function started(answers = base(), sample = 0, wire?: (host: FakeHost) => StationWire, before?: (s: ReturnType<typeof stationHost>) => void) {
  const s = stationHost(answers);
  before?.(s);
  const core = await Core.create(s.host, { clock: s.host.time.clock, sample, wire: () => (wire ? wire(s.host) : new HostWire(s.host)) });
  await s.host.time.pass(500);
  return { ...s, core };
}

