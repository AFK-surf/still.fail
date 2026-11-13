// A station retired from a workspace (replica/retire.ts): its chats go on on the station picked, beside that one's own,
// with their agents' transcripts and their rooms (carry-worker.ts), a linked worktree made again there by git from its
// remote and its commits no remote has; a thread both stations followed stays the one there; the retired station's
// connects named as they are there, its accounts moved there first. Each side started again at each step goes on; one
// that failed is said, not tried again by itself; a cancel calls it off where it can, at once. What goes in one message
// or a worker's answer never grows with the files. On the test's mesh and clock, as replica-stations.test.ts, its buses
// sending a request naming a station that another took the place of to that one, as module.ts has them.
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
import { Retire, connectsThere, rebuildGits } from "../src/replica/retire.ts";
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
  /// A gathering that goes on until it is called off (a station with a million files).
  hang: boolean;
  /// Its own accounts, those that cannot move, and what happened in order (`account:<id>`, `connects`).
  accounts: { id: string; name: string }[]; unmovable: Set<string>; events: string[];
  /// What went in the messages and the workers' answers: the most entries in one, the largest answer.
  most: number; answer: number;
  homeIs: string;
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
    const node = { id: nid, data, store, bus, quieted: [], unquieted: [], retired: [], moved: [], connects: [], bindings: {}, took: [], down: false, free: 1e15, git: true, placeFails: 0, gathers: 0, restores: 0, gathered: null, hang: false, accounts: [], unmovable: new Set(), events: [], most: 0, answer: 0, homeIs: HOME } as unknown as Node;
    const count = (v: Json) => {
      for (const k of ["hashes", "lacking"]) if (Array.isArray(v?.[k])) node.most = Math.max(node.most, v[k].length);
    };
    bus.attach(async (to, ws, request) => {
      const there = this.nodes.get(to);
      if (there === undefined || there.down || node.down) throw new Error("station unreachable");
      count(request);
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
    const jobs = [{ session: "chat:a", name: "dev", command: "npm run dev" }];
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
      quiet: async (ws) => (node.quieted.push(ws), jobs),
      jobsIn: () => jobs,
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
        gather: async (dataDir, db, ws, home, scratch, signal) => {
          if (node.hang) {
            return new Promise<Gathered>((_, reject) => signal?.addEventListener("abort", () => reject(new Error("called off"))));
          }
          const g = answered(gather(dataDir, db, ws, home, scratch));
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

test("a copy B could not put in is not put in again by itself: said to A, which can cancel, its chats going on there", async () => {
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
