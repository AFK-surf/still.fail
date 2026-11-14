// A station retired from a workspace (replica/retire.ts): its chats go on on the station picked, beside that one's own,
// with their agents' transcripts and their rooms (carry-worker.ts), a linked worktree made again there by git from its
// remote and its commits no remote has; a thread both stations followed stays the one there; the retired station's
// connects named as they are there, its accounts moved there first. Each side started again at each step goes on; one
// that failed is said, not tried again by itself; a cancel calls it off where it can, at once. What goes in one message
// or a worker's answer never grows with the files. On the test's mesh and clock, as replica-stations.test.ts, its buses
// sending a request naming a station that another took the place of to that one, as module.ts has them. Its jobs started
// again on the station the chats went to, once; a hand-over that fails puts the chats back to work and rests at `sent`;
// one an agent asked for (station_retire) waits there for a person's confirmation, which counts only as an owner's or
// an admin's in the app; who asked is told each step, after the chats moved on the station they went to; the agent
// home goes along, merged into the other's.
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { appendFileSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, statSync, symlinkSync, readlinkSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { afterEach, test } from "node:test";
import { Effect, Exit, Scope, type Clock } from "effect";
import { TestClock } from "effect/testing";
import { PeerBus, Refused, bytesOf, withBytes } from "../src/mesh/bus.ts";
import { Fibers } from "../src/ops/fibers.ts";
import { claudeProject } from "../src/read/transcript.ts";
import { type CarriedFile, type CarryIndex, type Gathered, gather, hashFile, linesOf, place, preview } from "../src/replica/carry-worker.ts";
import { Copies } from "../src/replica/copies.ts";
import { Exporter, genDir, nothingTold, ownDir } from "../src/replica/export.ts";
import { keepers } from "../src/replica/peers.ts";
import { build, takeBack, takeBackSoon } from "../src/replica/restore.ts";
import { QUIET_UNREACHED_MS, RETRY_MOST_MS, RETRY_MS, Retire, connectsThere, rebuildGits } from "../src/replica/retire.ts";
import { RetireAsks, chatCards, confirmLabel, declineLabel } from "../src/replica/retire-asks.ts";
import { hold, holding } from "../src/updates/holds.ts";
import { stationLang, tr } from "../src/ops/i18n.ts";
import { memoryMark } from "../src/replica/agent-carry.ts";
import type { CarriedJob } from "../src/replica/carry-worker.ts";
import { Admin } from "../src/api/admin.ts";
import type { Request } from "../src/api/request.ts";
import { StationParts } from "../src/parts.ts";
import { newMessage } from "../src/store/store.ts";
import { InlineRunner } from "../src/replica/runner.ts";
import { Retiring, sessionKey } from "../src/sessions/hub.ts";
import { WorkspaceConnects } from "../src/connects/workspace.ts";
import { EVENT, TAKE } from "../src/connects/remote.ts";
import { Store } from "../src/store/store.ts";
import { mbReaderBinary } from "../src/read/mb-reader.ts";
import { HOME, ORIGIN, OTHER, chat, dataDir, station } from "./replica-fakes.ts";
import { Rig, matches, message, reply, settle } from "./hub-fakes.ts";

type Json = any;
const scopes: Scope.Closeable[] = [];
const closing: (() => Promise<void>)[] = [];
afterEach(async () => {
  for (const c of closing.splice(0).reverse()) await c().catch(() => {});
  for (const s of scopes.splice(0)) await Effect.runPromise(Scope.close(s, Exit.void));
});

function testClock(): Clock.Clock {
  const scope = Effect.runSync(Scope.make());
  scopes.push(scope);
  return Effect.runSync(Scope.provide(TestClock.make(), scope));
}

function across(v: Json): Json {
  const bytes = bytesOf(v);
  const copy = JSON.parse(JSON.stringify(v));
  return bytes === null ? copy : withBytes(copy, bytes);
}

const id = (c: string) => c.repeat(64);
const gitEnv = () => ({ ...process.env, GIT_AUTHOR_NAME: "t", GIT_AUTHOR_EMAIL: "t@x", GIT_COMMITTER_NAME: "t", GIT_COMMITTER_EMAIL: "t@x", GIT_CONFIG_NOSYSTEM: "1", HOME: dataDir("gh") });
const git = (dir: string, ...args: string[]) => execFileSync("git", ["-C", dir, ...args], { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"], env: gitEnv() }).trim();
const gitAsync = async (dir: string, args: string[]) => git(dir, ...args);

type Node = {
  id: string; data: string; store: Store; copies: Copies; retire: Retire; bus: PeerBus; fibers: Fibers; runner: InlineRunner; off: () => void;
  quieted: string[]; unquieted: string[]; retired: string[]; moved: string[][]; connects: string[]; bindings: Record<string, string>;
  took: { bindings: Record<string, string>; notes: { session: string; text: string }[] }[];
  down: boolean; free: number; git: boolean; placeFails: number; gathers: number; restores: number; gathered: ((g: Gathered, n: number) => void) | null;
  /// A gathering that goes on until it is called off (a station with a million files), and who is told as one begins.
  hang: boolean;
  hanging: (() => void) | null;
  /// What its answers to `retire.lacking` wait for (none: they do not), and who is told as one waits.
  gate: Promise<void> | null;
  gated: (() => void) | null;
  /// Its own accounts, those that cannot move, and what happened in order (`account:<id>`, `connects`).
  accounts: { id: string; name: string }[]; unmovable: Set<string>; events: string[];
  /// What went in the messages and the workers' answers: the most entries in one, the largest answer.
  most: number; answer: number;
  homeIs: string;
  /// The jobs of its chats up now (what `quiet` stops), those started (by `jobs.start`), those whose start fails (why),
  /// and what its agents were told: by the jobs (`said`), by the station (`told`).
  up: CarriedJob[]; started: (CarriedJob & { id: string })[]; startFails: Map<string, string>; said: [string, string][]; told: [string, string][];
  /// Its agent home, station_retire there, the cards it posted and whether the last still waits, and its retire.puts.
  agent: string; asks: RetireAsks; cards: { session: string; text: string; card: Json }[]; cardState: "same" | "other" | "none"; puts: number;
  /// The holds on its updating itself it has now (updates/holds.ts, through which each goes too).
  held: number;
};

/// The most hashes a message of the test's stations asks of (the stations' own is LACK_MOST).
const BATCH = 50;

class Mesh {
  readonly nodes = new Map<string, Node>();
  readonly roster: string[] = [];
  readonly clock = testClock();

  add(nid: string, made?: { data: string; store: Store }): Node {
    const data = made?.data ?? dataDir(nid.slice(0, 4));
    const store = made?.store ?? Store.open(join(data, "stillfail.db"), join(data, "archive"));
    const bus = new PeerBus({ sleep: async () => {} });
    const node = {
      id: nid, data, store, bus, quieted: [], unquieted: [], retired: [], moved: [], connects: [], bindings: {}, took: [], down: false, free: 1e15, git: true, placeFails: 0, gathers: 0, restores: 0, gathered: null, hang: false, accounts: [], unmovable: new Set(), events: [], most: 0, answer: 0, homeIs: HOME,
      up: [{ session: "chat:a", name: "dev", command: "npm run dev" }], started: [], startFails: new Map(), said: [], told: [], agent: join(data, "agent"), cards: [], cardState: "same", puts: 0, held: 0, hanging: null, gate: null, gated: null,
    } as unknown as Node;
    const count = (v: Json) => {
      for (const k of ["hashes", "lacking"]) if (Array.isArray(v?.[k])) node.most = Math.max(node.most, v[k].length);
    };
    bus.attach(async (to, ws, request) => {
      const there = this.nodes.get(to);
      if (there === undefined || there.down || node.down) throw new Error("station unreachable");
      count(request);
      if (request?.method === "retire.put") node.puts++;
      if (request?.method === "retire.lacking" && there.gate !== null) {
        there.gated?.();
        await there.gate;
      }
      const answer = across(await there.bus.handle(ws ?? "", nid, across(request)));
      count(answer);
      return answer;
    });
    // (a request naming a station another took the place of goes to that one, as module.ts has it)
    bus.formerly((station, ws) => node.copies.now(ws, station), nid);
    this.parts(node);
    this.roster.push(nid);
    this.nodes.set(nid, node);
    closing.push(async () => {
      await this.stop(node);
      try { node.store.close(); } catch {}
    });
    return node;
  }

  /// A node's copies and retirement as a station that starts makes them.
  parts(node: Node): void {
    const { data, bus } = node;
    const nid = node.id;
    node.fibers = new Fibers("copies", this.clock);
    node.runner = new InlineRunner({ db: join(data, "stillfail.db"), replica: join(data, "replica"), dataDir: data, origin: nid, now: () => this.clock.currentTimeMillisUnsafe() });
    const roster = () => this.roster.map((s) => ({ id: s, name: s.slice(0, 4) }));
    node.copies = new Copies({
      data,
      here: () => nid,
      places: () => ({ home: HOME, workspaces: [{ workspace: HOME, name: nid.slice(0, 4) }] }),
      roster,
      ask: (s, r) => bus.ask(s, r),
      runner: node.runner,
      fibers: node.fibers,
      changed: () => {},
      restart: async () => {
        node.restores++;
        return null;
      },
      taking: () => node.retire.takingNow(),
    });
    const answered = <T>(v: T): T => ((node.answer = Math.max(node.answer, JSON.stringify(v).length)), v);
    node.retire = new Retire({
      data,
      here: () => nid,
      home: () => node.homeIs,
      roster: () => roster(),
      ask: (s, r) => bus.ask(s, r),
      askItself: (s, r) => bus.askItself(s, r),
      fibers: node.fibers,
      changed: () => {},
      copies: node.copies,
      quiet: async (ws) => (node.quieted.push(ws), node.up),
      jobsIn: () => node.up,
      tell: (session, text) => void node.told.push([session, text]),
      jobs: {
        start: (session, j) => {
          const why = node.startFails.get(j.name);
          if (why !== undefined) throw new Error(why);
          const made = { session, ...j, id: `job_${node.id.slice(0, 2)}${node.started.length}` };
          node.started.push(made);
          return { id: made.id, name: j.name, port: j.port };
        },
        running: (session, name, command) => node.started.some((j) => j.session === session && j.name === name && j.command === command),
        say: (session, text) => void node.said.push([session, text]),
      },
      agentHome: () => node.agent,
      drives: (station, session) => node.asks.drives(station, session),
      ofWorkspace: () => true,
      // (each counted here as well as held for real; let go of twice fails the test)
      hold: () => {
        const letGo = hold();
        node.held++;
        let gone = false;
        return () => {
          if (gone) throw new Error("a hold let go of twice");
          gone = true;
          node.held--;
          letGo();
        };
      },
      unquiet: (ws) => void node.unquieted.push(ws),
      retired: (ws) => void node.retired.push(ws),
      accounts: {
        own: () => node.accounts,
        move: async (pid) => {
          if (node.unmovable.has(pid)) throw new Error("that station did not take it");
          node.accounts = node.accounts.filter((p) => p.id !== pid);
          node.events.push(`account:${pid}`);
          return { id: pid };
        },
      },
      connectsOf: () => node.connects,
      connectsNamed: () => node.connects.map((c) => ({ id: c, name: c, kind: "slack" })),
      bindingsOf: (c) => Object.fromEntries(c.filter((x) => node.bindings[x] !== undefined).map((x) => [x, node.bindings[x]!])),
      moveConnects: async (ws, to) => void (node.moved.push([ws, to]), node.events.push("connects")),
      took: (t) => void node.took.push(t),
      reposDir: join(data, "repos"),
      room: async () => ({ free: node.free, clones: true }),
      hasGit: async () => node.git,
      git: gitAsync,
      lackMost: BATCH,
      work: {
        gather: async (dataDir, db, ws, home, scratch, signal, agent) => {
          if (node.hang) {
            const going = new Promise<Gathered>((_, reject) => signal?.addEventListener("abort", () => reject(new Error("called off"))));
            node.hanging?.();
            return going;
          }
          const g = answered(gather(dataDir, db, ws, home, scratch, agent ?? null));
          node.gathers++;
          node.gathered?.(g, node.gathers);
          return g;
        },
        place: async (...a) => {
          if (node.placeFails > 0) {
            node.placeFails--;
            throw new Error("the disk said no");
          }
          return answered(place(...a));
        },
        preview: async (...a) => preview(...a),
      },
    });
    node.asks = new RetireAsks({
      data, here: () => nid, roster, wsOf: () => HOME, retire: node.retire, ask: (s, r) => bus.ask(s, r),
      cards: {
        post: async (session, text, card) => (node.cards.push({ session, text, card }), { thread: 1, ts: String(node.cards.length) }),
        state: () => node.cardState,
      },
      notify: (session, text) => void node.told.push([session, text]),
      now: () => this.clock.currentTimeMillisUnsafe(),
    });
    bus.on("replica.", node.copies.answers());
    bus.on("retire.", node.retire.answers((peer) => this.roster.includes(peer)));
    node.off = node.store.subscribe((c) => node.copies.told(c));
  }

  async stop(node: Node): Promise<void> {
    node.off();
    await node.retire.close();
    await node.copies.close();
    await node.runner.close();
    await node.fibers.close();
  }

  /// A node started again: its parts made anew from what is on disk (`restore`: what waits to be put in, put in before
  /// its store opens, as main.ts does).
  async restart(nid: string, restore = false): Promise<void> {
    const node = this.nodes.get(nid)!;
    await this.stop(node);
    if (restore) {
      node.store.close();
      takeBack(node.data, join(node.data, "stillfail.db"), 0);
      node.store = Store.open(join(node.data, "stillfail.db"), join(node.data, "archive"));
    }
    this.parts(node);
    await node.copies.start();
    await node.retire.start();
  }

  async settle(): Promise<void> {
    for (let i = 0; i < 4; i++) {
      for (const n of this.nodes.values()) {
        await n.asks.settle();
        await n.retire.settle();
        await n.copies.settle();
      }
    }
  }
}

/// Station A (station()'s chats, chat:a's transcript and working files, a build's output, two accounts of its own), B
/// the one picked (chats of its own, more threads than A so that A's ids are B's too; not one of those that keep A's
/// copies, so that it would hand A's copy over were it not taking it), and two more.
async function setup() {
  const mesh = new Mesh();
  const all = [id("a"), id("b"), id("c"), id("d")];
  const A = all[0]!;
  const B = all.find((s) => s !== A && !keepers(HOME, A, all).includes(s))!;
  const made = station();
  const ws = (made.store.getSession("chat:a") as Json).workspace as string;
  made.store.setRuntimeSessionId("chat:a", "run-1");
  const transcript = join(made.data, "transcripts", "claude", claudeProject(ws)!, "run-1.jsonl");
  mkdirSync(join(transcript, ".."), { recursive: true });
  writeFileSync(transcript, '{"type":"user"}\n');
  writeFileSync(join(ws, "notes.md"), "what I was doing");
  mkdirSync(join(ws, "node_modules"), { recursive: true });
  writeFileSync(join(ws, "node_modules", "big.js"), "made again by an install");
  const a = mesh.add(A, made);
  a.connects.push("bot");
  a.accounts = [{ id: "max", name: "Claude Max" }, { id: "kept", name: "Kept" }];
  const bData = dataDir("b");
  const bStore = Store.open(join(bData, "stillfail.db"), join(bData, "archive"));
  for (const k of ["chat:m1", "chat:m2", "chat:m3", "chat:m4", "chat:m5"]) chat(bStore, bData, k, null, 2);
  const b = mesh.add(B, { data: bData, store: bStore });
  for (const s of all) if (s !== A && s !== B) mesh.add(s);
  for (const n of mesh.nodes.values()) await n.copies.start();
  await mesh.settle();
  const before = new DatabaseSync(made.db, { readOnly: true });
  const aEntries = (before.prepare("SELECT COUNT(*) AS n FROM entries e JOIN thread_sessions t ON t.thread = e.thread WHERE t.session = 'chat:a'").get() as { n: number }).n;
  before.close();
  const C = all.find((s) => s !== A && s !== B)!;
  return { mesh, A, B, C, a, b, ws, made, bData, aEntries, there: join(bData, "sessions", "chat", "chat:a", "workspace") };
}

const step = (n: Node) => (n.retire.overview(HOME).retiring?.step ?? null);
const takingStep = (n: Node) => (n.retire.overview(HOME).taking[0]?.step ?? null);
const indexOf = (g: Gathered) => JSON.parse(readFileSync(g.index, "utf8")) as CarryIndex;
/// Every file a gathering's lists name.
function listedOf(g: Gathered): CarriedFile[] {
  const out: CarriedFile[] = [];
  for (const s of indexOf(g).sessions) for (const line of linesOf(s.at)) out.push(JSON.parse(line));
  return out;
}

test("a station retired: its chats, transcripts and rooms go on on the station picked, beside its own; a file changed as it is sent is sent again; it tells the retired station itself it took them; its accounts, then its connects move; it stays quiet; the preview said all of it", async () => {
  const { mesh, A, B, C, a, b, ws, bData, aEntries, there } = await setup();
  a.unmovable.add("kept");
  // What the app shows first, held to what the retirement then does.
  const shown = await a.retire.preview(HOME);
  let index: CarryIndex | null = null;
  // (notes.md changes as it is sent while the chats work, and again after it is gathered once they stopped)
  a.gathered = (g, n) => {
    index = indexOf(g);
    if (n === 1) writeFileSync(join(ws, "notes.md"), "what I was doing, more");
    if (n === 2) writeFileSync(join(ws, "notes.md"), "what I was doing, more and more");
  };
  await a.retire.retire(HOME, B, "p@x");
  await assert.rejects(a.retire.retire(HOME, C, "p@x"), (e) => e instanceof Refused && /being retired already/.test(e.message), "one retirement at a time");
  await mesh.settle();
  // B refused the file whose bytes changed: the step tried again, gathered again
  const failed = a.retire.overview(HOME).retiring!;
  assert.equal(failed.step, "quiet");
  assert.match(failed.error ?? "", /changed/);
  assert.equal(failed.retriable, true);
  assert.equal(failed.cancellable, true);
  await a.retire.again(HOME);
  await mesh.settle();
  assert.ok(a.quieted.length > 0 && a.quieted.every((w) => w === HOME), "A's chats of the workspace stopped");
  assert.equal(step(a), "handing");
  assert.equal(takingStep(b), "restart");
  assert.equal(b.restores, 1);
  // (what goes along is in place on B before it starts again; what an install makes is not)
  assert.equal(readFileSync(join(there, "notes.md"), "utf8"), "what I was doing, more and more");
  assert.equal(statSync(join(there, "notes.md")).nlink, 1, "a copy, not a link to what was sent");
  assert.equal(existsSync(join(there, "node_modules")), false, "a build's output stays behind");
  assert.equal(readFileSync(join(bData, "transcripts", "claude", claudeProject(ws)!, "run-1.jsonl"), "utf8"), '{"type":"user"}\n');

  // B started again before it put them in (as if it stopped then): it goes on, and keeps A's copy meanwhile, though it is
  // not one of those that keep it
  await mesh.restart(B);
  await mesh.settle();
  assert.ok(existsSync(join(bData, "replicas", HOME, A)), "A's copy not handed over while B takes A's chats");
  assert.equal(takingStep(b), "restart");
  // A started again while B puts them in: it asks B again, which goes on with the same
  const quietBefore = a.quieted.length;
  await mesh.restart(A);
  await mesh.settle();
  assert.equal(step(a), "handing");
  assert.equal(a.quieted.length, quietBefore + 2, "quiet again as it starts again (before it serves, and as it goes on)");

  // B starts again: A's chats put in beside its own; it says so to A itself (B is A too now: a request naming A, sent
  // as any other, would be answered by B)
  await mesh.restart(B, true);
  await mesh.settle();
  const after = new DatabaseSync(join(bData, "stillfail.db"), { readOnly: true });
  const sessions = (after.prepare("SELECT key FROM sessions ORDER BY key").all() as { key: string }[]).map((r) => r.key);
  for (const k of ["chat:a", "chat:b", "chat:m1", "chat:m5"]) assert.ok(sessions.includes(k), k);
  assert.ok(!sessions.includes("chat:o"), "another workspace's chat stays");
  const moved = (after.prepare("SELECT COUNT(*) AS n FROM entries e JOIN thread_sessions t ON t.thread = e.thread WHERE t.session = 'chat:a'").get() as { n: number }).n;
  assert.equal(moved, aEntries, "chat:a's messages, in the thread it has here");
  assert.equal((after.prepare("SELECT COUNT(*) AS n FROM entries e JOIN thread_sessions t ON t.thread = e.thread WHERE t.session = 'chat:m1'").get() as { n: number }).n, 2, "B's own as they were");
  assert.equal((after.prepare("SELECT workspace FROM sessions WHERE key = 'chat:a'").get() as { workspace: string }).workspace, there);
  assert.equal((after.prepare("SELECT ws FROM sessions WHERE key = 'chat:a'").get() as { ws: string | null }).ws, null, "of B's home workspace, as there");
  after.close();
  assert.deepEqual(JSON.parse(readFileSync(join(bData, "replica", "formerly.json"), "utf8")), [A]);
  // each moved chat's agent is told once where it came from and what did not move
  const note = b.took[0]!.notes.find((n) => n.session === "chat:a")!.text;
  for (const part of [A.slice(0, 4), a.data, bData, "git worktree repair", "npm run dev"]) assert.ok(note.includes(part), part);

  // A heard it: its chats there out of sight, its accounts moved (one that could not, said), then its connects, done
  assert.equal(step(a), "done");
  assert.deepEqual(a.retired, [HOME]);
  assert.deepEqual(a.events, ["account:max", "connects"], "the accounts before the connects");
  assert.deepEqual(a.retire.overview(HOME).retiring!.accountsLeft.map((x) => [x.id, x.name]), [["kept", "Kept"]]);
  assert.deepEqual(a.moved, [[HOME, B]]);
  assert.deepEqual(b.retire.overview(HOME).taking, [], "B was answered: nothing more kept of it");
  assert.equal(a.retire.overview(HOME).retiring!.cancellable, false);
  await assert.rejects(a.retire.cancel(HOME), Refused);
  // the preview said what it did
  const idx = index as CarryIndex | null;
  assert.ok(idx !== null);
  assert.equal(shown.home, true);
  assert.equal(shown.chats + shown.archived, idx.sessions.length);
  assert.equal(shown.archived, 1, "chat:b");
  assert.equal(shown.outside, idx.skipped.length);
  assert.deepEqual(shown.accounts.map((x) => x.id).sort(), ["kept", "max"]);
  assert.deepEqual(shown.accountsStay, []);
  assert.deepEqual(shown.jobs, [{ name: "dev", session: "chat:a" }]);
  assert.deepEqual(shown.connects.map((c) => c.id), a.connects);
  // B's own copy holds the chats it took
  await b.copies.settle();
  assert.ok((b.copies.overview(HOME) as Json).chats >= 5 + 2, "B's export has A's chats beside its own");
  // A started again once done: still quiet there, and done
  const quiets = a.quieted.length;
  await mesh.restart(A);
  await mesh.settle();
  assert.equal(a.quieted.length, quiets + 2);
  assert.equal(step(a), "done");
});

test("retired from a workspace that is not its home one, a station keeps its accounts", async () => {
  const { mesh, B, a, b } = await setup();
  a.homeIs = OTHER;
  const shown = await a.retire.preview(HOME);
  assert.equal(shown.home, false);
  assert.deepEqual(shown.accounts, []);
  assert.deepEqual(shown.accountsStay.map((x) => x.id).sort(), ["kept", "max"]);
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  await mesh.restart(B, true);
  await mesh.settle();
  assert.equal(step(a), "done");
  assert.deepEqual(a.events, ["connects"]);
  assert.equal(a.accounts.length, 2);
  void b;
});

test("what goes between the stations never grows with the files: a session's list in several messages, each a bounded batch of hashes", async () => {
  const { mesh, B, a, b, made } = await setup();
  // (more files a session than one message asks of; the same bytes in each session, sent once)
  const n = BATCH * 3 + 20;
  for (const key of ["chat:a", "chat:b", "chat:gone"]) {
    const dir = join(made.data, "sessions", "chat", key, "workspace", "many");
    mkdirSync(dir, { recursive: true });
    for (let i = 0; i < n; i++) writeFileSync(join(dir, `f${i}.txt`), `file ${i}\n`);
  }
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  assert.equal(step(a), "handing");
  assert.equal(a.most, BATCH, `at most ${BATCH} hashes a message, each session's list in more than one`);
  assert.ok(b.most <= BATCH);
  assert.ok(a.answer < 2_000, `a gathering's answer is a few numbers (${a.answer} bytes)`);
  assert.ok(b.answer < 2_000, `a placing's too (${b.answer} bytes)`);
  for (const key of ["chat:a", "chat:b", "chat:gone"]) {
    assert.equal(readdirSync(join(b.data, "sessions", "chat", key, "workspace", "many")).length, n, key);
  }
});

test("each side started again where it stopped goes on: the station retired at quiet, the one picked at placing", async () => {
  const { mesh, B, a, b, there } = await setup();
  // (B not reached once A's chats stopped)
  a.gathered = (_g, n) => {
    if (n === 2) b.down = true;
  };
  b.placeFails = 1;
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  assert.equal(step(a), "quiet");
  assert.equal(a.retire.overview(HOME).retiring!.reason, "offline");
  const quiets = a.quieted.length;
  await mesh.restart(a.id);
  await mesh.settle();
  assert.equal(step(a), "quiet");
  assert.ok(a.quieted.length >= quiets + 2, "quiet again as it starts again");
  b.down = false;
  await a.retire.again(HOME);
  await mesh.settle();
  assert.equal(step(a), "handing");
  // B's placing failed once: started again, it places them
  assert.equal(takingStep(b), "placing");
  await mesh.restart(B);
  await mesh.settle();
  assert.equal(takingStep(b), "restart");
  assert.ok(existsSync(join(there, "notes.md")));
  await mesh.restart(B, true);
  await mesh.settle();
  assert.equal(step(a), "done");
});

test("a copy B could not put in is not put in again by itself: said to A, whose chats work again, which can cancel", async () => {
  const { mesh, B, a, b, bData } = await setup();
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  assert.equal(takingStep(b), "restart");
  // (what was brought for the restart broken: the restore fails)
  const copy = join(bData, "restore", "copy");
  for (const gen of readdirSync(copy)) if (gen !== "files") rmSync(join(copy, gen, "log"), { recursive: true, force: true });
  await mesh.restart(B, true);
  await mesh.settle();
  assert.equal(takingStep(b), "failed");
  const r = a.retire.overview(HOME).retiring!;
  assert.equal(r.reason, "failed");
  assert.equal(r.retriable, true);
  assert.equal(r.cancellable, true);
  // (its chats work again here meanwhile: the hand-over fell back to `sent`; nothing holds either station's updating)
  assert.equal(r.step, "sent");
  assert.deepEqual(a.unquieted, [HOME]);
  assert.equal(a.held, 0);
  assert.equal(b.held, 0);
  // started again, neither tries it again by itself
  const restores = b.restores;
  await mesh.restart(B);
  await mesh.restart(a.id);
  await mesh.settle();
  assert.equal(b.restores, restores);
  assert.equal(takingStep(b), "failed");
  assert.equal(existsSync(join(bData, "restore", "ready.json")), false);
  // called off: B drops what it was sent, A's chats go on
  await a.retire.cancel(HOME);
  await mesh.settle();
  assert.equal(a.retire.overview(HOME).retiring, null);
  assert.deepEqual(a.unquieted, [HOME]);
  assert.deepEqual(b.retire.overview(HOME).taking, []);
  assert.equal(existsSync(join(bData, "replica", "carry", HOME, a.id)), false);
  assert.equal(existsSync(join(bData, "sessions", "chat", "chat:a")), false, "the rooms put there for it gone");
});

test("a restore whose own process dies each time is not started again and again: after two starts it is said to have failed", async () => {
  const { mesh, B, a, b } = await setup();
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  assert.equal(b.restores, 1);
  // (B starts again, the restore said nothing: no outcome, what was brought still waiting)
  await mesh.restart(B);
  await mesh.settle();
  assert.equal(b.restores, 2);
  assert.equal(takingStep(b), "restart");
  await mesh.restart(B);
  await mesh.settle();
  assert.equal(b.restores, 2, "not asked for a third time");
  assert.equal(takingStep(b), "failed");
  assert.equal(a.retire.overview(HOME).retiring!.reason, "failed");
});

test("a cancel once B took the chats is refused, and the move finishes", async () => {
  const { mesh, B, a, b } = await setup();
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  // (A not reached as B says it took them)
  a.down = true;
  await mesh.restart(B, true);
  await mesh.settle();
  a.down = false;
  assert.equal(step(a), "handing");
  await assert.rejects(a.retire.cancel(HOME), (e) => e instanceof Refused && /took this station's chats already/.test(e.message));
  await mesh.settle();
  assert.equal(step(a), "done");
  assert.deepEqual(a.moved, [[HOME, B]]);
  assert.deepEqual(a.unquieted, []);
  void b;
});

test("a cancel answers at once, its gathering ended; one made while the station picked is not reached is called off here and told it once it is up", async () => {
  const { mesh, B, a, b } = await setup();
  a.hang = true;
  await a.retire.retire(HOME, B, "p@x");
  assert.equal(takingStep(b), "coming");
  // (the gathering would go on for good: the cancel ends it)
  await a.retire.cancel(HOME);
  assert.equal(a.retire.overview(HOME).retiring, null);
  assert.deepEqual(b.retire.overview(HOME).taking, [], "B dropped it");
  // At quiet, B not reached: called off here, B told once it is up.
  a.hang = false;
  a.gathered = (_g, n) => {
    if (n === 2) b.down = true;
  };
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  assert.equal(step(a), "quiet");
  await a.retire.cancel(HOME);
  assert.equal(a.retire.overview(HOME).retiring, null);
  assert.deepEqual(a.unquieted, [HOME]);
  b.down = false;
  assert.equal(takingStep(b), "coming", "B not told yet");
  await mesh.restart(a.id);
  await mesh.settle();
  assert.deepEqual(b.retire.overview(HOME).taking, [], "told once it is up");
});

test("refused where the station picked has not the room for what goes along, or no git for the worktrees to be made there", async () => {
  const { mesh, B, a, b } = await setup();
  b.free = 1000;
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  const r = a.retire.overview(HOME).retiring!;
  assert.equal(r.step, "sending");
  assert.equal(r.reason, "full");
  assert.match(r.error ?? "", /free/);
  assert.deepEqual(a.quieted, [], "nothing stopped");
  await a.retire.cancel(HOME);
  assert.equal(a.retire.overview(HOME).retiring, null);
  // (no git there, and a worktree here to be made again)
  b.free = 1e15;
  b.git = false;
  a.gathered = (g) => void (g.gits = 1);
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  const g = a.retire.overview(HOME).retiring!;
  assert.equal(g.step, "sending");
  assert.match(g.error ?? "", /install git/);
  assert.deepEqual(a.quieted, [], "nothing stopped");
});

test("quiet stops a home workspace's chat with a turn running, takes no new turn, and unquiet resumes it", async () => {
  const r = new Rig({ workspaces: ["home"] });
  try {
    const m = message();
    await r.accept(m);
    await settle();
    const key = sessionKey("cl", "C1", m.threadTs);
    const s = r.claude.last();
    assert.ok(s.busy());
    assert.equal(r.store.sessionWs(key), null, "of the home workspace");
    await r.hub.quiet("home");
    assert.ok(s.disposed, "its runtime ended");
    assert.ok(r.session(key).running, "kept for when it goes on");
    await assert.rejects(r.accept(reply(m, "9999.5", "more")), Retiring);
    await settle();
    assert.equal(r.claude.count(), 1, "no turn while quiet");
    r.hub.unquiet("home");
    await settle();
    assert.equal(r.claude.count(), 2);
    assert.equal(r.claude.last().options.resume, s.sessionId, "the turn cut off goes on");
  } finally {
    await r.close();
  }
});

test("a chat moved here: its agent is told once, with what it is next handed", async () => {
  const r = new Rig({ workspaces: ["home"], maxNudges: 0 });
  try {
    const m = message();
    await r.accept(m);
    await settle();
    const key = sessionKey("cl", "C1", m.threadTs);
    r.claude.last().complete();
    await settle();
    r.store.setMovedNotes([{ session: key, text: "<chat-moved>it moved</chat-moved>" }]);
    for (const [ts, text] of [["9999.8", "and now?"], ["9999.9", "again"]] as const) {
      await r.accept(reply(m, ts, `<@UBOT> ${text}`, { addressed: true }));
      await settle();
      const s = r.claude.last();
      if (s.busy()) s.complete();
      await settle();
    }
    const said = r.claude.sessions.flatMap((s) => [...s.prompts, ...s.steers]);
    assert.equal(said.filter((p) => p.includes("<chat-moved>it moved</chat-moved>")).length, 1, "said once");
    assert.ok(matches(said.find((p) => p.includes("chat-moved"))!, ["<chat-moved>it moved</chat-moved>", "and now?"]), "before what it is handed");
    assert.equal(r.store.untoldMovedNote(key), null);
  } finally {
    await r.close();
  }
});

test("what a platform says while a workspace is quiet is kept, and goes to the station its chats went to in order before the connect moves", async () => {
  const r = new Rig({ workspaces: ["home"] });
  try {
    const asked: [string, string, string | undefined][] = [];
    const wc = new WorkspaceConnects({
      data: r.dir, hub: () => r.hub, store: r.store, config: { raw: () => r.raw, update: (f) => f(r.raw) },
      here: () => "A", home: () => "home", stations: () => [{ id: "A", name: "a" }, { id: "B", name: "b" }],
      bus: { ask: async (s, req) => (asked.push([s, req.method, req.event?.message?.text]), { ok: true }), on: () => {} },
      names: () => null,
    });
    await r.hub.quiet("home");
    const m = message({ text: "<@UBOT> one" });
    await wc.receive("cl", { type: "message", message: m });
    await wc.receive("cl", { type: "message", message: reply(m, "9999.7", "two") });
    await settle();
    assert.equal(asked.length, 0, "kept here, taken by nobody yet");
    assert.equal(r.claude.count(), 0);
    await wc.moveAll("home", "B");
    // (the kept events first, in order, then each of its connects of the workspace moved)
    assert.deepEqual(asked.slice(0, 2), [["B", EVENT, "<@UBOT> one"], ["B", EVENT, "two"]]);
    assert.deepEqual(asked.slice(2), ["cl", "gpt", "team"].map(() => ["B", TAKE, undefined]));
    assert.deepEqual(r.raw.connects, [], "they moved");
    assert.equal(readFileSync(join(r.dir, "replica", "held-events.jsonl"), "utf8"), "");
  } finally {
    await r.close();
  }
});

test("what goes along: an archived chat's room whole, nothing of a directory not the station's own, nothing outside sessions and transcripts; a link to the old place names the new", () => {
  const made = station();
  const { data, db, store } = made;
  // chat:b archived: its workspace packed in its room, its directory empty
  const room = join(data, "sessions", "chat", "chat:b");
  mkdirSync(join(room, "workspace"), { recursive: true });
  for (const [name, text] of [["workspace.tar.zst", "packed"], ["cold", "workspace and history may be compressed\n"], ["workspace-locks.json", "[]"], ["archive.lock", ""], ["workspace.tar.zst.writing", "half"]]) writeFileSync(join(room, name!), text!);
  // a chat working in a person's project, and one whose directory is the data directory itself
  const project = join(data, "elsewhere", "proj");
  mkdirSync(project, { recursive: true });
  writeFileSync(join(project, "mine.txt"), "a person's");
  writeFileSync(join(data, "station.key"), "the station's own key");
  store.insertSession({ key: "chat:out", connect: "chat", runtime: "claude", profile: "cc", workspace: project, token: "t-out", createdAt: 1, lastActiveAt: 1, ws: null });
  store.insertSession({ key: "chat:data", connect: "chat", runtime: "claude", profile: "cc", workspace: data, token: "t-data", createdAt: 1, lastActiveAt: 1, ws: null });
  const aws = join(data, "sessions", "chat", "chat:a", "workspace");
  symlinkSync(join(aws, "uploads", "pic.png"), join(aws, "pic-link"));
  store.close();
  const g = gather(data, db, HOME, true, join(data, "replica", "carrying"));
  const index = indexOf(g);
  const paths = listedOf(g).map((f) => f.path.slice(data.length + 1));
  for (const want of ["workspace.tar.zst", "chat:b/cold", "workspace-locks.json"]) assert.ok(paths.some((p) => p.endsWith(want)), want);
  for (const not of ["archive.lock", ".writing", "mine.txt", "station.key", "stillfail.db"]) assert.ok(!paths.some((p) => p.includes(not)), not);
  assert.ok(paths.every((p) => p.startsWith("sessions/") || p.startsWith("transcripts")), "only sessions and transcripts");
  assert.deepEqual(index.skipped.sort(), ["chat:data", "chat:out"]);
  assert.equal(index.sessions.find((s) => s.key === "chat:b")!.room, room);
  // the preview counts the same of it, no directory walked
  assert.equal(preview(data, db, HOME, true).outside, index.skipped.length);
  // put in on another station: a path a list says outside sessions and transcripts is put nowhere
  const to = dataDir("to");
  const files = sent(g);
  const keyHash = hashFile(join(data, "station.key"));
  cpSync(join(data, "station.key"), join(files, keyHash));
  appendFileSync(join(files, index.sessions.find((s) => s.key === "chat:a")!.list), `${JSON.stringify({ path: join(data, "station.key"), hash: keyHash, size: 21, mode: 0o600, mtimeMs: 1 })}\n`);
  const placed = place(to, g.index, files);
  assert.equal(placed.missing, 0);
  assert.equal(existsSync(join(to, "station.key")), false);
  assert.equal(readFileSync(join(to, "sessions", "chat", "chat:b", "workspace.tar.zst"), "utf8"), "packed");
  assert.equal(readlinkSync(join(to, "sessions", "chat", "chat:a", "workspace", "pic-link")), join(to, "sessions", "chat", "chat:a", "workspace", "uploads", "pic.png"));
  // (copied from what was sent, never linked to it: what was sent stays until the taking is done)
  assert.equal(statSync(join(to, "sessions", "chat", "chat:b", "workspace.tar.zst")).nlink, 1);
  // put in again (started again after it): what is there with the same bytes stays
  const again = place(to, g.index, files);
  assert.equal(again.placed, 0);
  assert.equal(again.missing, 0);
});

/// A remote and a clone of it in `dir`: one commit on the remote, one more that no remote has on another branch, a
/// tracked file changed, one untracked, one ignored, and what an install makes.
function checkoutIn(dir: string, remote: string) {
  mkdirSync(remote, { recursive: true });
  git(remote, "init", "-q", "--bare", "-b", "main");
  const seed = dataDir("seed");
  git(seed, "init", "-q", "-b", "main");
  writeFileSync(join(seed, "a.txt"), "one\n");
  writeFileSync(join(seed, ".gitignore"), "ignored.log\n");
  git(seed, "add", "-A");
  git(seed, "commit", "-q", "-m", "first");
  git(seed, "remote", "add", "origin", remote);
  git(seed, "push", "-q", "origin", "main");
  mkdirSync(dir, { recursive: true });
  execFileSync("git", ["clone", "-q", "-b", "main", remote, dir], { stdio: "ignore", env: gitEnv() });
  git(dir, "checkout", "-q", "-b", "work");
  writeFileSync(join(dir, "b.txt"), "mine\n");
  git(dir, "add", "b.txt");
  git(dir, "commit", "-q", "-m", "not pushed");
  writeFileSync(join(dir, "a.txt"), "changed\n");
  writeFileSync(join(dir, "new.txt"), "untracked\n");
  writeFileSync(join(dir, "ignored.log"), "ignored\n");
  mkdirSync(join(dir, "node_modules", "x"), { recursive: true });
  writeFileSync(join(dir, "node_modules", "x", "i.js"), "built\n");
  return { head: git(dir, "rev-parse", "HEAD"), seed };
}

/// What a gathering names, as the station it goes to holds it once sent: each file's bytes, each list and bundle, by
/// their hashes.
function sent(g: Gathered): string {
  const dir = join(dataDir("sent"), "files");
  mkdirSync(dir, { recursive: true });
  const index = indexOf(g);
  for (const f of listedOf(g)) if ("hash" in f && !existsSync(join(dir, f.hash))) cpSync(f.path, join(dir, f.hash));
  for (const s of index.sessions) cpSync(s.at, join(dir, s.list));
  for (const [hash, path] of Object.entries(index.bundles)) cpSync(path, join(dir, hash));
  return dir;
}

test("a clone goes along with its own repository (its other branches too), and a repository inside it with its own", () => {
  const from = dataDir("from");
  const db = join(from, "stillfail.db");
  const store = Store.open(db, join(from, "archive"));
  chat(store, from, "chat:g", null, 1);
  const ws = (store.getSession("chat:g") as Json).workspace as string;
  store.close();
  const repo = join(ws, "repo");
  const { head } = checkoutIn(repo, join(dataDir("remote"), "r.git"));
  // (a repository of its own inside it, git does not list its files)
  const inner = join(repo, "inner");
  mkdirSync(inner);
  git(inner, "init", "-q", "-b", "main");
  writeFileSync(join(inner, "i.txt"), "inner\n");
  git(inner, "add", "-A");
  git(inner, "commit", "-q", "-m", "inner");
  writeFileSync(join(inner, "n.txt"), "inner, untracked\n");
  const g = gather(from, db, HOME, true, join(from, "scratch"));
  const paths = listedOf(g).map((f) => f.path.slice(from.length + 1));
  for (const want of ["repo/a.txt", "repo/b.txt", "repo/new.txt", "repo/.gitignore", "repo/.git/HEAD", "repo/inner/i.txt", "repo/inner/n.txt", "repo/inner/.git/HEAD"]) assert.ok(paths.some((p) => p.endsWith(want)), want);
  for (const not of ["ignored.log", "node_modules"]) assert.ok(!paths.some((p) => p.includes(not)), not);
  assert.equal(g.gits, 0, "its repository goes as its files: nothing made again");
  const to = dataDir("to");
  place(to, g.index, sent(g));
  const there = join(to, repo.slice(from.length + 1));
  assert.equal(git(there, "rev-parse", "HEAD"), head);
  assert.deepEqual(git(there, "branch", "--format=%(refname:short)").split("\n").sort(), ["main", "work"]);
  assert.deepEqual(git(there, "diff", "HEAD", "--name-only").split("\n"), ["a.txt"]);
  assert.equal(git(join(there, "inner"), "log", "--format=%s"), "inner");
});

test("a linked worktree whose branch was deleted on its remote is made again with its commits", async () => {
  const from = dataDir("from");
  const db = join(from, "stillfail.db");
  const store = Store.open(db, join(from, "archive"));
  chat(store, from, "chat:w", null, 1);
  const ws = (store.getSession("chat:w") as Json).workspace as string;
  store.close();
  const remote = join(dataDir("remote"), "r.git");
  // (the station's clone in its repository cache, a worktree of it in the chat's directory)
  const { seed } = checkoutIn(join(dataDir("other"), "c"), remote);
  const main = join(from, "repos", "r");
  mkdirSync(join(from, "repos"), { recursive: true });
  execFileSync("git", ["clone", "-q", remote, main], { stdio: "ignore", env: gitEnv() });
  mkdirSync(ws, { recursive: true });
  const wt = join(ws, "wt");
  git(main, "worktree", "add", "-q", "-b", "feat", wt);
  writeFileSync(join(wt, "x.txt"), "pushed, then its branch deleted\n");
  git(wt, "add", "x.txt");
  git(wt, "commit", "-q", "-m", "x");
  const x = git(wt, "rev-parse", "HEAD");
  git(wt, "push", "-q", "origin", "feat");
  git(seed, "push", "-q", "origin", "--delete", "feat");
  writeFileSync(join(wt, "y.txt"), "never pushed\n");
  git(wt, "add", "y.txt");
  git(wt, "commit", "-q", "-m", "y");
  const y = git(wt, "rev-parse", "HEAD");
  const g = gather(from, db, HOME, true, join(from, "scratch"));
  const index = indexOf(g);
  assert.equal(index.gits.length, 1);
  assert.equal(index.gits[0]!.branch, "feat");
  assert.equal(index.gits[0]!.head, y);
  assert.ok(!listedOf(g).some((f) => f.path === join(wt, ".git")), "its .git is made again there, not carried");
  const to = dataDir("to");
  const files = sent(g);
  place(to, g.index, files);
  assert.deepEqual(await rebuildGits(to, join(to, "repos"), index, files, gitAsync), { made: 1, failed: 0 });
  const there = join(to, wt.slice(from.length + 1));
  assert.equal(git(there, "rev-parse", "HEAD"), y);
  assert.equal(git(there, "symbolic-ref", "--short", "HEAD"), "feat");
  git(there, "cat-file", "-e", `${x}^{commit}`);
  assert.equal(git(there, "status", "--porcelain"), "");
});

test("a copy put in beside a station's own chats: its threads given ids there, a platform's thread both followed is the one there, a still.fail chat of the same ts is its own; the connects named and the sessions' workspace as there", async () => {
  const made = station();
  // (a session of a connect of A's, in a thread B follows too)
  made.store.insertSession({ key: "bot:C9:ts1", connect: "bot", runtime: "claude", profile: "cc", workspace: join(made.data, "sessions", "bot", "x", "workspace"), token: "tok-bot", createdAt: 1, lastActiveAt: 1, ws: null });
  const both = made.store.openThread("slack", "C9", "ts1", "both", "p@x").id;
  made.store.joinThread(both, "bot:C9:ts1", "bot");
  for (let i = 0; i < 4; i++) made.store.insertMessage({ thread: both, ts: `s.${i}`, authorKind: "person", author: "p@x", text: `A saw ${i}` });
  made.store.setRead("p@x", both, 4);
  made.store.startTurnFor("turn-both", "bot:C9:ts1", "message", { profile: "cc", person: "p@x", thread: both });
  made.store.setAbout("turn-both", [both, 2, "s.1"]);
  const aThread = (made.store.db.prepare("SELECT thread FROM thread_sessions WHERE session = 'chat:a'").get() as Json).thread;
  made.store.setAbout("turn-a", [aThread, 3, "chat:a.2"]);
  const aCount = (made.store.db.prepare("SELECT COUNT(*) AS n FROM entries WHERE thread = ?").get(aThread) as Json).n;
  const e = new Exporter({ db: made.db, replica: join(made.data, "replica"), dataDir: made.data, origin: ORIGIN, now: () => 1 });
  e.setPlaces({ home: HOME, workspaces: [{ workspace: HOME, name: "a" }, { workspace: OTHER, name: "a" }] });
  let p = e.pass(nothingTold());
  while (p.more) p = e.pass(nothingTold());
  const head = e.heads()[HOME]!;
  const files = join(dataDir("files"), "files");
  mkdirSync(files, { recursive: true });
  e.close();
  const dir = genDir(ownDir(join(made.data, "replica")), HOME, head.gen);
  // (the station it goes to: chats of its own, the same Slack thread followed by a bot of its own, and a still.fail chat
  // of its own whose ts A's chat:a has too)
  const to = dataDir("to");
  const s = Store.open(join(to, "stillfail.db"), join(to, "archive"));
  for (const k of ["chat:m1", "chat:m2", "chat:m3"]) chat(s, to, k, null, 2);
  s.insertSession({ key: "mine:C9:ts1", connect: "mine", runtime: "claude", profile: "cc", workspace: join(to, "w"), token: "tok-mine", createdAt: 1, lastActiveAt: 1, ws: null });
  const here = s.openThread("slack", "C9", "ts1", "both", "p@x").id;
  s.joinThread(here, "mine:C9:ts1", "mine");
  s.insertMessage({ thread: here, ts: "s.0", authorKind: "person", author: "p@x", text: "B saw it" });
  s.setRead("p@x", here, 1);
  s.insertSession({ key: "chat:same", connect: "chat", runtime: "claude", profile: "cc", workspace: join(to, "same"), token: "tok-same", createdAt: 1, lastActiveAt: 1, ws: null });
  const same = s.openThread("ember", "C", "ts-chat:a", "B's own", "p@x").id;
  s.joinThread(same, "chat:same", "chat");
  s.insertMessage({ thread: same, ts: "b.0", authorKind: "person", author: "p@x", text: "B's own chat" });
  s.close();
  // refused without `merge`, as before
  assert.throws(() => build(join(to, "stillfail.db"), dir, files, to), /chats of its own/);
  const connects = connectsThere(["bot"], ["chat", "bot"], ORIGIN, id("b"));
  assert.deepEqual(connects, { bot: `bot@${ORIGIN}` });
  // (copied as it is, to run the program on the same)
  const twin = dataDir("twin");
  cpSync(to, twin, { recursive: true });
  const built = build(join(to, "stillfail.db"), dir, files, to, 1, true, connects, "wsjoined");
  assert.ok(built.rows.threads! > 0);
  const d = new DatabaseSync(join(to, "stillfail.db"));
  const one = (sql: string, ...v: unknown[]) => d.prepare(sql).get(...(v as never[])) as Json;
  // B's own as they were
  assert.equal(one("SELECT COUNT(*) AS n FROM entries WHERE thread = ?", here).n, 1, "the thread both followed keeps its log here");
  assert.equal(one("SELECT n FROM reads WHERE viewer = 'p@x' AND thread = ?", here).n, 1, "and its reads");
  assert.equal(one("SELECT COUNT(*) AS n FROM threads WHERE surface = 'slack' AND channel = 'C9' AND thread_ts = 'ts1'").n, 1);
  assert.equal(one("SELECT COUNT(*) AS n FROM entries WHERE thread = ?", same).n, 1, "B's still.fail chat as it was");
  // A's session joined it, its connect named as it is here, what its turn was about let go
  assert.equal(one("SELECT connect FROM thread_sessions WHERE thread = ? AND session = 'bot:C9:ts1'", here).connect, `bot@${ORIGIN}`);
  assert.equal(one("SELECT connect FROM sessions WHERE key = 'bot:C9:ts1'").connect, `bot@${ORIGIN}`);
  assert.equal(one("SELECT about_thread FROM turns WHERE id = 'turn-both'").about_thread, null);
  // A's own chat in a thread of its own here, the next free ts, with all its messages, its turn about it
  const t = one("SELECT thread FROM thread_sessions WHERE session = 'chat:a'").thread;
  assert.notEqual(t, same);
  assert.equal(one("SELECT thread_ts FROM threads WHERE id = ?", t).thread_ts, "ts-chat:a1");
  assert.equal(one("SELECT COUNT(*) AS n FROM entries WHERE thread = ?", t).n, aCount);
  assert.equal(one("SELECT about_thread FROM turns WHERE id = 'turn-a'").about_thread, t);
  assert.equal(one("SELECT COUNT(*) AS n FROM thread_sessions WHERE session = 'chat:m1'").n, 1);
  // its sessions of the workspace as this station says it, B's own as they were
  assert.equal(one("SELECT ws FROM sessions WHERE key = 'chat:a'").ws, "wsjoined");
  assert.equal(one("SELECT ws FROM sessions WHERE key = 'bot:C9:ts1'").ws, "wsjoined");
  assert.equal(one("SELECT ws FROM sessions WHERE key = 'chat:m1'").ws, null);
  // put in once: run again, nothing more
  const rows = one("SELECT COUNT(*) AS n FROM entries").n;
  d.close();
  build(join(to, "stillfail.db"), dir, files, to, 2, true, connects, "wsjoined");
  const again = new DatabaseSync(join(to, "stillfail.db"));
  assert.equal((again.prepare("SELECT COUNT(*) AS n FROM entries").get() as Json).n, rows);
  again.close();
  // the MoonBit program makes the same of it
  const binary = mbReaderBinary();
  if (binary !== null) {
    const copy = join(twin, "restore", "copy");
    mkdirSync(copy, { recursive: true });
    cpSync(dir, join(copy, head.gen), { recursive: true });
    cpSync(files, join(copy, "files"), { recursive: true });
    writeFileSync(join(twin, "restore", "ready.json"), JSON.stringify({ origin: ORIGIN, workspace: HOME, gen: head.gen, name: "a", from: "x", merge: true, connects, ws: "wsjoined" }));
    await takeBackSoon(twin, join(twin, "stillfail.db"), 1, binary);
    const x = new DatabaseSync(join(twin, "stillfail.db"));
    const y = new DatabaseSync(join(to, "stillfail.db"));
    for (const table of ["threads", "sessions", "thread_sessions", "entries", "letters", "turns", "reads", "pins"]) {
      const all = (db: DatabaseSync) => JSON.stringify(db.prepare(`SELECT * FROM ${table} ORDER BY rowid`).all().map((r: Json) => ({ ...r, workspace: undefined, cwd: undefined, attachments: undefined })));
      assert.equal(all(x), all(y), table);
    }
    x.close();
    y.close();
  }
  made.store.close();
});

/// The test's clock moved on (what waits on it, run).
const advance = (mesh: Mesh, ms: number) => Effect.runPromise((mesh.clock as unknown as { adjust(d: string): Effect.Effect<void> }).adjust(`${ms} millis`));
/// Where a node's last card is, as its fake chat posted it.
const lastAt = (n: Node) => ({ thread: 1, n: n.cards.length, ts: String(n.cards.length) });
const OWNERS_ONLY = () => tr(stationLang(), "station.retire.ownersOnly");
const toldTo = (n: Node, session: string) => n.told.filter(([s]) => s === session).map(([, t]) => t);

test("the jobs a moved chat had running are started again on the station it went to, in its directory there, once; one in a directory that stayed is not; its agent told at once", async () => {
  const { mesh, B, a, b, ws, there } = await setup();
  const project = dataDir("proj");
  a.up = [
    { session: "chat:a", name: "dev", command: "npm run dev", cwd: ws, port: 5173, watch: false },
    { session: "chat:a", name: "watch", command: "tail -f log", cwd: join(ws, "sub"), port: null, watch: true },
    { session: "chat:a", name: "theirs", command: "make serve", cwd: project, port: null, watch: false },
  ];
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  assert.equal(step(a), "handing");
  // (A not reached as B puts them in and starts again after: B goes on, and starts no job twice)
  a.down = true;
  await mesh.restart(B, true);
  await mesh.settle();
  await mesh.restart(B);
  await mesh.settle();
  a.down = false;
  await mesh.restart(B);
  await mesh.settle();
  assert.equal(step(a), "done");
  assert.deepEqual(b.started.map((j) => [j.session, j.name, j.cwd, j.port, j.watch]), [["chat:a", "dev", there, 5173, false], ["chat:a", "watch", join(there, "sub"), null, true]], "started once each, under B's data directory");
  assert.equal(b.took.length, 1);
  const note = b.took[0]!.notes.find((n) => n.session === "chat:a")!.text;
  for (const part of ["were started again here", "dev", "watch", "theirs", "not the retired station's own"]) assert.ok(note.includes(part), part);
  assert.ok(!note.includes("did not move and are not running"));
  const said = b.said.filter(([s]) => s === "chat:a").map(([, t]) => t);
  assert.equal(said.length, 1, "told once, at once");
  assert.match(said[0]!, /This chat moved here from station .*; Service "dev" \(job_.*, port 5173\) was started again\./);
  assert.match(said[0]!, /Job "theirs" could not be started again: it ran in .* which was not the retired station's own/);
  // A heard what came of them
  assert.deepEqual(a.retire.overview(HOME).retiring && (await a.retire.agentAsk(HOME, { op: "status" })).status.retiring.jobsThere.map((j: Json) => [j.name, j.started]), [["dev", true], ["watch", true], ["theirs", false]]);
  assert.deepEqual((await b.retire.agentAsk(HOME, { op: "status" })).status.taken[0].jobs.map((j: Json) => j.name), ["dev", "watch", "theirs"], "B's status says it too");
});

test("a station from before jobs moved (its jobs only named): none started there, its agents told they did not move", async () => {
  const { mesh, B, a, b } = await setup();
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  await mesh.restart(B, true);
  await mesh.settle();
  assert.equal(step(a), "done");
  assert.deepEqual(b.started, []);
  assert.deepEqual(b.said, []);
  assert.match(b.took[0]!.notes.find((n) => n.session === "chat:a")!.text, /dev \(`npm run dev`\)\. Start again those still needed/);
});

test("a hand-over whose station is not reached for a minute after the chats stopped puts them back to work, their jobs too, and rests at sent; asked again, it sends only what changed and goes on", async () => {
  const { mesh, B, a, ws, there } = await setup();
  a.up = [{ session: "chat:a", name: "dev", command: "npm run dev", cwd: ws, port: null, watch: false }];
  for (let i = 0; i < 20; i++) writeFileSync(join(ws, `f${i}.txt`), `file ${i}\n`);
  const b = mesh.nodes.get(B)!;
  let lists = 0;
  a.gathered = (g, n) => {
    lists = indexOf(g).sessions.length;
    if (n === 2) b.down = true;
  };
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  assert.equal(step(a), "quiet");
  assert.equal(a.retire.overview(HOME).retiring!.reason, "offline");
  const first = a.puts;
  // (tried again as the backoff gives it, still stopped, until a minute has gone by unreached)
  let waited = 0;
  for (const wait of [RETRY_MS, 2 * RETRY_MS]) {
    await advance(mesh, wait);
    waited += wait;
    await mesh.settle();
    assert.equal(step(a), "quiet", `still stopped after ${waited} ms`);
  }
  assert.ok(waited < QUIET_UNREACHED_MS);
  await advance(mesh, 4 * RETRY_MS);
  await mesh.settle();
  const r = a.retire.overview(HOME).retiring!;
  assert.equal(r.step, "sent");
  assert.equal(r.reason, "offline");
  assert.match(r.error ?? "", /unreachable/);
  assert.equal(r.retriable, true);
  assert.equal(r.cancellable, true);
  assert.deepEqual(a.unquieted, [HOME], "its chats work again");
  assert.deepEqual(a.started.map((j) => [j.name, j.cwd]), [["dev", ws]], "and their jobs");
  assert.match(a.said.find(([s]) => s === "chat:a")![1], /did not go through.*was started again/);
  // nothing goes on by itself, started again either
  const gathers = a.gathers;
  await mesh.restart(a.id);
  await advance(mesh, RETRY_MOST_MS);
  await mesh.settle();
  assert.equal(step(a), "sent");
  assert.equal(a.gathers, gathers);
  // asked again in the app: only what changed goes
  b.down = false;
  writeFileSync(join(ws, "notes.md"), "changed while the chats worked again");
  const before = a.puts;
  await a.retire.again(HOME);
  await mesh.settle();
  assert.equal(step(a), "handing");
  assert.ok(first > 20, `the first sending sent the files (${first})`);
  // (the file that changed, the sessions' lists, which go only once the chats stop, and the index)
  assert.ok(a.puts - before <= 1 + lists + 1, `the second sent what changed, the lists and the index (${a.puts - before} of ${first})`);
  await mesh.restart(B, true);
  await mesh.settle();
  assert.equal(step(a), "done");
  assert.equal(readFileSync(join(there, "notes.md"), "utf8"), "changed while the chats worked again");
});

test("a hand-over B could not put in puts A's chats back to work at sent, B putting in nothing by itself; asked again, only what changed is sent and it goes in", async () => {
  const { mesh, B, a, b, bData, ws, there } = await setup();
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  const copy = join(bData, "restore", "copy");
  for (const gen of readdirSync(copy)) if (gen !== "files") rmSync(join(copy, gen, "log"), { recursive: true, force: true });
  await mesh.restart(B, true);
  await mesh.settle();
  const r = a.retire.overview(HOME).retiring!;
  assert.equal(r.step, "sent");
  assert.equal(r.reason, "failed");
  assert.deepEqual(a.unquieted, [HOME]);
  assert.equal(takingStep(b), "failed");
  assert.equal(existsSync(join(bData, "restore", "ready.json")), false);
  const restores = b.restores;
  writeFileSync(join(ws, "notes.md"), "changed after it fell back");
  const before = a.puts;
  await a.retire.again(HOME);
  await mesh.settle();
  assert.equal(step(a), "handing");
  assert.equal(b.restores, restores + 1, "put in again, as asked");
  assert.ok(a.puts - before <= 4, `only what changed sent again (${a.puts - before})`);
  await mesh.restart(B, true);
  await mesh.settle();
  assert.equal(step(a), "done");
  assert.equal(readFileSync(join(there, "notes.md"), "utf8"), "changed after it fell back");
});

test("a retirement an agent asked for starts only as its card is confirmed, waits at sent for the hand-over's, and the agent on a third station is told each step", async () => {
  const { mesh, A, B, C, a } = await setup();
  const c = mesh.nodes.get(C)!;
  a.unmovable.add("kept");
  const asked = { action: "start", station: A.slice(0, 4), to: B.slice(0, 4) };
  assert.equal((await c.asks.tool("chat:c1", asked)).card, "posted");
  const one = c.cards.at(-1)!;
  assert.equal(one.card.retire.kind, "start");
  assert.deepEqual(one.card.options.map((o: Json) => [o.label, o.action]), [[confirmLabel("start"), "close"], [declineLabel("start"), "close"]]);
  assert.match(one.text, /会搬过去：2 个对话/);
  assert.equal(a.retire.overview(HOME).retiring, null, "nothing until a person confirms");
  // asked again while its card waits: not posted twice
  assert.equal((await c.asks.tool("chat:c1", asked)).card, "waiting");
  assert.equal(c.cards.length, 1);
  c.asks.chosen({ email: "o@x" } as Json, one.card, confirmLabel("start"), lastAt(c));
  c.asks.chosen({ email: "o@x" } as Json, one.card, confirmLabel("start"), lastAt(c));
  await mesh.settle();
  const r = a.retire.overview(HOME).retiring!;
  assert.equal(r.step, "sent");
  assert.equal(r.by, "o@x");
  assert.deepEqual(a.quieted, [], "the chats still work");
  const told = () => toldTo(c, "chat:c1");
  assert.ok(told().some((t) => t.includes("o@x confirmed it in the app")));
  assert.ok(told().some((t) => /everything that goes along is on .* files/.test(t)), told().join("\n"));
  // `again` never hands over; started again it waits there still
  await assert.rejects(c.asks.tool("chat:c1", { action: "again", station: A.slice(0, 4) }), /hand_over/);
  await mesh.restart(a.id);
  await mesh.settle();
  assert.equal(step(a), "sent");
  assert.deepEqual(a.quieted, []);
  assert.equal((await c.asks.tool("chat:c1", { action: "hand_over", station: A.slice(0, 4) })).card, "posted");
  const two = c.cards.at(-1)!;
  assert.equal(two.card.retire.kind, "hand_over");
  assert.match(two.text, /个文件/);
  c.asks.chosen({ email: "o@x" } as Json, two.card, confirmLabel("hand_over"), lastAt(c));
  await mesh.settle();
  assert.equal(step(a), "handing");
  assert.ok(a.quieted.length > 0);
  await mesh.restart(B, true);
  await mesh.settle();
  assert.equal(step(a), "done");
  for (const said of ["took its chats", "these accounts did not move", "Kept", "is done", "a person's own step in the app"]) assert.ok(told().some((t) => t.includes(said)), said);
  // (asked of the retired station, a request goes to the one that took its place, which says so)
  const status = (await c.asks.tool("chat:c1", { action: "status", station: A.slice(0, 4) })).say;
  assert.match(status, /took the chats of station .* and is that station too now; jobs: dev not started/);
  assert.ok(status.includes("移出工作区"), status);
});

test("the agent that asked being one of the chats moved: told on the station they went to that they were taken there with its jobs, then what is left", async () => {
  const { mesh, B, a, b, ws } = await setup();
  a.unmovable.add("kept");
  a.up = [{ session: "chat:a", name: "dev", command: "npm run dev", cwd: ws, port: null, watch: false }];
  await a.asks.tool("chat:a", { action: "start", to: B.slice(0, 4) });
  a.asks.chosen({ email: "o@x" } as Json, a.cards.at(-1)!.card, confirmLabel("start"), lastAt(a));
  await mesh.settle();
  assert.equal(step(a), "sent");
  assert.ok(toldTo(a, "chat:a").some((t) => t.includes("everything that goes along")), "told here before it moved");
  await a.asks.tool("chat:a", { action: "hand_over" });
  a.asks.chosen({ email: "o@x" } as Json, a.cards.at(-1)!.card, confirmLabel("hand_over"), lastAt(a));
  await mesh.settle();
  await mesh.restart(B, true);
  await mesh.settle();
  assert.equal(step(a), "done");
  const there = toldTo(b, "chat:a");
  assert.match(there[0]!, /its chats were taken here, this chat with them.*Jobs started again there: dev/);
  assert.ok(there.some((t) => t.includes("these accounts did not move")), there.join("\n"));
  assert.ok(there.some((t) => t.includes("is done")));
  assert.ok(!toldTo(a, "chat:a").some((t) => t.includes("took its chats") || t.includes("is done")), "not told on the station it left");
});

test("retired from its home workspace, its agent home goes along: its memory added under where it came from, presets by id (the other's win), a skill put where none of its name is, the station's own skills not", async () => {
  const { mesh, A, B, a, b } = await setup();
  const write = (path: string, text: string) => (mkdirSync(join(path, ".."), { recursive: true }), writeFileSync(path, text));
  write(join(a.agent, "MEMORY.md"), "- remember A's things\n");
  write(join(a.agent, "presets.json"), JSON.stringify({ presets: [{ id: "p1", name: "A's p1" }, { id: "p2", name: "A's p2" }] }));
  write(join(a.agent, "skills", "mine", "SKILL.md"), "---\nname: mine\n---\n");
  write(join(a.agent, "skills", "mine", "scripts", "run.sh"), "echo mine\n");
  write(join(a.agent, "skills", "both", "SKILL.md"), "A's\n");
  write(join(a.agent, "skills", "stillfail-jobs", "SKILL.md"), "the station's own\n");
  write(join(a.agent, "skills", ".system", "x", "SKILL.md"), "a runtime's\n");
  write(join(a.agent, "skills", "synced", "s", "SKILL.md"), "a sync's\n");
  write(join(b.agent, "MEMORY.md"), "- B's own memory\n");
  write(join(b.agent, "presets.json"), JSON.stringify({ presets: [{ id: "p1", name: "B's p1" }] }));
  write(join(b.agent, "skills", "both", "SKILL.md"), "B's\n");
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  await mesh.restart(B, true);
  await mesh.settle();
  assert.equal(step(a), "done");
  const memory = readFileSync(join(b.agent, "MEMORY.md"), "utf8");
  assert.ok(memory.startsWith("- B's own memory\n"), memory);
  assert.match(memory, new RegExp(`## From station ${A.slice(0, 4)} \\(retired into this one on \\d{4}-\\d\\d-\\d\\d\\)`));
  assert.ok(memory.includes(memoryMark(A)) && memory.trimEnd().endsWith("- remember A's things"));
  assert.deepEqual(JSON.parse(readFileSync(join(b.agent, "presets.json"), "utf8")).presets.map((p: Json) => [p.id, p.name]), [["p1", "B's p1"], ["p2", "A's p2"]]);
  assert.equal(readFileSync(join(b.agent, "skills", "mine", "scripts", "run.sh"), "utf8"), "echo mine\n");
  assert.equal(readFileSync(join(b.agent, "skills", "both", "SKILL.md"), "utf8"), "B's\n", "one of the same name stays as it is");
  for (const not of ["stillfail-jobs", ".system", "synced"]) assert.equal(existsSync(join(b.agent, "skills", not)), false, not);
  // (started again after: nothing put in twice)
  await mesh.restart(B);
  await mesh.settle();
  assert.equal(readFileSync(join(b.agent, "MEMORY.md"), "utf8").split(memoryMark(A)).length, 2);
});

test("a station_retire card counts only as an owner or admin of its workspace chooses it in the app: not a member's, not another workspace's admin's, not a message saying yes, not a Slack chat's, not twice; its agent is told", async () => {
  const store = Store.open(":memory:", null);
  store.insertSession({ key: "s1", connect: "chat", runtime: "claude", profile: "cc", workspace: "/w/s1", token: "t1", createdAt: 1, lastActiveAt: 1 });
  store.insertSession({ key: "s2", connect: "bot", runtime: "claude", profile: "cc", workspace: "/w/s2", token: "t2", createdAt: 1, lastActiveAt: 1 });
  const chatThread = store.openThread("ember", "CHAT", "1.1", null, "o@x");
  store.joinThread(chatThread.id, "s1", "chat");
  store.insertMessage(newMessage(chatThread.id, "1.2", "person", "o@x", "retire this station, please"));
  const slack = store.openThread("slack", "C1", "2.2", null, null);
  store.joinThread(slack.id, "s2", "bot");
  store.insertMessage(newMessage(slack.id, "2.3", "person", "o@x", "retire it"));
  let posted = 0;
  const hub = { store, chat: () => ({ post: async () => `9.${++posted}` }), shared: () => {} };
  const calls: Json[] = [];
  const told: string[] = [];
  const retire = {
    agentAsk: async (_ws: string, r: Json) => {
      calls.push(r);
      return r.op === "preview"
        ? { station: { name: "aaaa" }, preview: { chats: 2, archived: 0, outside: 0, connects: [], accounts: [], accountsStay: [], jobs: [] }, status: { retiring: null }, to: { reached: true, git: true, free: 1e12, name: "bbbb" } }
        : { status: { retiring: null } };
    },
  } as unknown as Retire;
  const asks = new RetireAsks({
    data: dataDir("asks"), here: () => id("a"), roster: () => [{ id: id("a"), name: "aaaa" }, { id: id("b"), name: "bbbb" }], wsOf: () => HOME, retire,
    ask: async () => { throw new Error("no other station here"); }, cards: chatCards(hub as Json), notify: (_s, t) => void told.push(t), now: () => 1,
  });
  const parts = new StationParts();
  parts.cardChoice("retire", { may: (v, c, at) => asks.may(v, c, at), chosen: (v, c, o, at) => asks.chosen(v, c, o, at) });
  const admin = new Admin({ names: new Map(), read: async () => "{}" } as Json, { store, parts });
  const cardN = () => store.entriesBetween(chatThread.id, 1, 1_000_000).filter((e) => e.card != null).at(-1)!.n;
  const close = async (role: string, workspace: string, email = "o@x", n = cardN()) => {
    const r = { method: "PUT", path: `/threads/${chatThread.id}/closed-card`, query: [], headers: {}, body: Buffer.from(JSON.stringify({ n, option: confirmLabel("start") })), viewer: { sub: email, email, name: email, role, workspace, device: "d" }, lang: "zh" } as unknown as Request;
    const a = await admin.handle(r);
    await asks.settle();
    return [a.status, JSON.parse(String(a.body))] as const;
  };
  const starts = () => calls.filter((c) => c.op === "start");
  // (a Slack chat's agent is posted no card: the app is where it is confirmed)
  await assert.rejects(asks.tool("s2", { action: "start", to: "bbbb" }), /still\.fail app/);
  assert.equal(posted, 0);
  assert.equal((await asks.tool("s1", { action: "start", to: "bbbb" })).card, "posted");
  assert.deepEqual(await close("member", HOME), [403, { error: OWNERS_ONLY() }]);
  assert.deepEqual(await close("admin", OTHER), [403, { error: OWNERS_ONLY() }]);
  assert.notEqual(store.pendingCardHeader(chatThread.id), null, "the card still waits");
  assert.deepEqual(starts(), []);
  // a message saying yes ends the card and decides nothing
  store.insertMessage(newMessage(chatThread.id, "1.9", "person", "o@x", `yes, ${confirmLabel("start")}`));
  assert.equal((await close("owner", HOME))[0], 409);
  assert.deepEqual(starts(), []);
  // asked again: a card anew, for the same ask
  assert.equal((await asks.tool("s1", { action: "start", to: "bbbb" })).card, "posted");
  assert.equal(posted, 2);
  assert.equal((await close("admin", HOME, "ad@x"))[0], 200);
  assert.deepEqual(starts(), [{ op: "start", to: id("b"), by: "ad@x", driver: { station: id("a"), session: "s1" } }]);
  assert.ok(told.at(-1)!.startsWith("ad@x confirmed it in the app"));
  assert.equal(store.untoldCardChoices("s1").length, 1, "the choice is told it with what it is next handed too");
  // chosen again: nothing more
  assert.equal((await close("owner", HOME))[0], 200);
  assert.equal(starts().length, 1);
  // a card that is not the station's own, naming a waiting ask under other words, is refused and starts nothing
  store.insertSession({ key: "s3", connect: "chat", runtime: "claude", profile: "cc", workspace: "/w/s3", token: "t3", createdAt: 1, lastActiveAt: 1 });
  const other = store.openThread("ember", "CHAT", "3.1", null, "o@x");
  store.joinThread(other.id, "s3", "chat");
  store.insertMessage(newMessage(other.id, "3.2", "person", "o@x", "retire it"));
  const waiting = await asks.tool("s3", { action: "start", to: "bbbb" });
  assert.equal(waiting.card, "posted");
  store.insertMessage({ ...newMessage(other.id, "3.9", "agent", "s3", "随便点一下就好"), card: { type: "options", options: [{ label: confirmLabel("start"), action: "close" }], retire: { ask: waiting.ask } } });
  const forged = store.entriesBetween(other.id, 1, 1_000_000).filter((e) => e.card != null).at(-1)!;
  assert.equal(forged.ts, "3.9");
  const at = (r: Request) => admin.handle(r).then(async (a) => (await asks.settle(), [a.status, JSON.parse(String(a.body))] as const));
  assert.deepEqual(await at({ method: "PUT", path: `/threads/${other.id}/closed-card`, query: [], headers: {}, body: Buffer.from(JSON.stringify({ n: forged.n, option: confirmLabel("start") })), viewer: { sub: "o", email: "o@x", name: "o", role: "owner", workspace: HOME, device: "d" }, lang: "zh" } as unknown as Request), [403, { error: tr(stationLang(), "station.retire.askGone") }]);
  assert.notEqual(store.pendingCardHeader(other.id), null, "it stays open");
  asks.chosen({ email: "o@x" } as Json, forged.card, confirmLabel("start"), { thread: other.id, n: forged.n, ts: forged.ts });
  await asks.settle();
  assert.equal(starts().length, 1, "nothing started by it");
  assert.equal(asks.get(waiting.ask)!.state, "asked");
  store.close();
});

test("a station's updating itself is held while an update would cut the retirement: on the station retired while it sends and from its chats stopping until they were taken, on the one taking them from the take until it took them, across its restart; never at sent, nor once done", async () => {
  const { mesh, A, B, C, a, b } = await setup();
  const c = mesh.nodes.get(C)!;
  const seen: number[] = [];
  a.gathered = (_g, n) => void seen.push(n === 1 ? a.held : a.held * 10);
  await c.asks.tool("chat:c1", { action: "start", station: A.slice(0, 4), to: B.slice(0, 4) });
  c.asks.chosen({ email: "o@x" } as Json, c.cards.at(-1)!.card, confirmLabel("start"), lastAt(c));
  await mesh.settle();
  assert.equal(step(a), "sent");
  assert.equal(a.held, 0, "not at sent");
  assert.equal(b.held, 0, "nothing taken yet");
  await c.asks.tool("chat:c1", { action: "hand_over", station: A.slice(0, 4) });
  c.asks.chosen({ email: "o@x" } as Json, c.cards.at(-1)!.card, confirmLabel("hand_over"), lastAt(c));
  await mesh.settle();
  assert.deepEqual(seen, [1, 10], "held while sending, and once the chats stopped");
  assert.equal(step(a), "handing");
  assert.equal(takingStep(b), "restart");
  assert.equal(a.held, 1);
  assert.equal(b.held, 1);
  // B started again (not by an update: its own, or a crash) before it put them in: held again as it starts
  await mesh.restart(B);
  assert.equal(b.held, 1);
  await mesh.settle();
  // A started again in `handing`: held again
  await mesh.restart(a.id);
  assert.equal(a.held, 1);
  await mesh.settle();
  await mesh.restart(B, true);
  await mesh.settle();
  assert.equal(step(a), "done");
  assert.equal(a.held, 0, "let go once the other took them");
  assert.equal(b.held, 0);
  await mesh.restart(a.id);
  await mesh.restart(B);
  await mesh.settle();
  assert.equal(a.held + b.held, 0, "never once done");
  assert.equal(holding(), 0);
});

test("a hold on updating let go of as a retirement is called off with its chats stopped, and as a take B could not put in fails", async () => {
  const { mesh, B, a, b, bData } = await setup();
  // (the second gathering, its chats stopped, goes on until it is called off: the cancel made once it began)
  a.gathered = (_g, n) => {
    if (n === 1) a.hang = true;
  };
  const begun = new Promise<void>((r) => void (a.hanging = r));
  await a.retire.retire(HOME, B, "p@x");
  await begun;
  assert.equal(step(a), "quiet");
  assert.equal(a.held, 1);
  // (answered without the clock moved: nothing of it waits on a timer)
  const at = mesh.clock.currentTimeMillisUnsafe();
  await a.retire.cancel(HOME);
  assert.equal(mesh.clock.currentTimeMillisUnsafe(), at);
  a.hanging = null;
  await mesh.settle();
  assert.equal(a.retire.overview(HOME).retiring, null);
  assert.equal(a.held, 0);
  a.hang = false;
  a.gathered = null;
  // taken by B, which cannot put it in: both let go (A falls back to `sent`, B rests failed)
  await a.retire.retire(HOME, B, "p@x");
  await mesh.settle();
  assert.equal(b.held, 1);
  const copy = join(bData, "restore", "copy");
  for (const gen of readdirSync(copy)) if (gen !== "files") rmSync(join(copy, gen, "log"), { recursive: true, force: true });
  await mesh.restart(B, true);
  await mesh.settle();
  assert.equal(takingStep(b), "failed");
  assert.equal(step(a), "sent");
  assert.equal(a.held + b.held, 0);
  // dropped by a cancel there too: nothing held
  await a.retire.cancel(HOME);
  await mesh.settle();
  assert.equal(a.held + b.held, 0);
  assert.equal(holding(), 0);
});

test("a sending failure that is tried again by itself is not told to who asked until it has failed for RETRY_MOST_MS in a row, then once, saying how long", async () => {
  const { mesh, A, B, C, a, b } = await setup();
  const c = mesh.nodes.get(C)!;
  // (B not reached from the first gathering on: the sending fails, and is tried again)
  a.gathered = (_g, n) => {
    if (n === 1) b.down = true;
  };
  await c.asks.tool("chat:c1", { action: "start", station: A.slice(0, 4), to: B.slice(0, 4) });
  c.asks.chosen({ email: "o@x" } as Json, c.cards.at(-1)!.card, confirmLabel("start"), lastAt(c));
  await mesh.settle();
  assert.equal(step(a), "sending");
  assert.equal(a.retire.overview(HOME).retiring!.reason, "offline");
  const failing = () => toldTo(c, "chat:c1").filter((t) => t.includes("sending the files"));
  assert.deepEqual(failing(), [], "not told of a failure tried again by itself");
  assert.equal(a.held, 0, "not held while sending to a station not reached");
  for (let i = 0; i < 3; i++) {
    await advance(mesh, RETRY_MOST_MS);
    await mesh.settle();
  }
  assert.equal(failing().length, 1, failing().join("\n"));
  assert.match(failing()[0]!, /has been failing for \d+ min \(offline\)/);
  // (what does not go on by itself is told at once: B's disk too small)
  b.down = false;
  b.free = 1000;
  await advance(mesh, RETRY_MOST_MS);
  await mesh.settle();
  assert.equal(a.retire.overview(HOME).retiring!.reason, "full");
  assert.equal(failing().length, 2);
  assert.match(failing()[1]!, /failed \(full\)/);
});

test("a cancel made while the chats stop answers at each point the step passes through: before the gathering answers, while what changed is sent; the hold let go of each time", async () => {
  const { mesh, B, a, b } = await setup();
  // during the send: the other station holds back its answer to what it lacks until the cancel was made
  let release: () => void = () => {};
  a.gathered = (_g, n) => {
    if (n === 2) b.gate = new Promise<void>((r) => void (release = r));
  };
  const waiting = new Promise<void>((r) => void (b.gated = r));
  await a.retire.retire(HOME, B, "p@x");
  await waiting;
  assert.equal(step(a), "quiet");
  assert.equal(a.held, 1);
  const cancelled = a.retire.cancel(HOME);
  // (the request in flight answers; the run stops before the next file, and the cancel goes on)
  b.gate = null;
  release();
  await cancelled;
  assert.equal(a.retire.overview(HOME).retiring, null);
  assert.equal(a.held, 0);
  assert.deepEqual(a.unquieted, [HOME]);
  await mesh.settle();
  assert.deepEqual(b.retire.overview(HOME).taking, []);
  assert.equal(holding(), 0);
});

test("a station that stops while its chats' gathering goes on ends it at once: its process hands over without waiting for it, and the next goes on from where it stood", async () => {
  const { mesh, B, a, b } = await setup();
  a.gathered = (_g, n) => {
    if (n === 1) a.hang = true;
  };
  const begun = new Promise<void>((r) => void (a.hanging = r));
  await a.retire.retire(HOME, B, "p@x");
  await begun;
  assert.equal(step(a), "quiet");
  const at = mesh.clock.currentTimeMillisUnsafe();
  await a.retire.close();
  assert.equal(mesh.clock.currentTimeMillisUnsafe(), at);
  assert.equal(a.held, 0, "let go as it closed");
  // started again: still quiet, held again, and it goes on
  a.hang = false;
  a.hanging = null;
  await mesh.restart(a.id);
  assert.equal(a.held, 1);
  await mesh.settle();
  assert.equal(step(a), "handing");
  await mesh.restart(B, true);
  await mesh.settle();
  assert.equal(step(a), "done");
  assert.equal(a.held + b.held, 0);
});
