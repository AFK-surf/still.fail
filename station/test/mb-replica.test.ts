// The MoonBit program in the copies' export and restore threads' place (station/mb, src/replica; replica/runner.ts
// `exportThread`, restore.ts `takeBackSoon`) does as export.ts and restore.ts do: read the same station step by step,
// told the same, its answers, its state (export.db), its batches line for line and its heads are the TypeScript
// exporter's (what is random, the time a batch is compressed by and the zstd frame's bytes aside); a copy taken back by
// it makes the same database, files and outcome as one taken back by restore.ts, from either's copy.
import assert from "node:assert/strict";
import { copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, statSync, utimesSync, writeFileSync } from "node:fs";
import { join, sep } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { after, test } from "node:test";
import { MbProcess, mbReaderBinary } from "../src/read/mb-reader.ts";
import { tell } from "../src/replica/copies.ts";
import { Exporter, type Told, genDir, nothingTold, ownDir } from "../src/replica/export.ts";
import { type Head, decodeBatch } from "../src/replica/format.ts";
import { takeBack, takeBackSoon } from "../src/replica/restore.ts";
import { WorkerRunner, exportThread } from "../src/replica/runner.ts";
import { Store } from "../src/store/store.ts";
import { HOME, ORIGIN, OTHER, attach, chat, dataDir, station } from "./replica-fakes.ts";
import { testClock } from "./hub-fakes.ts";

type Json = any;
const binary = mbReaderBinary();
const skip = binary === null ? "the MoonBit program is not built here (station/mb/build.sh)" : false;
const places = { home: HOME, workspaces: [{ workspace: HOME, name: "laptop" }, { workspace: OTHER, name: "laptop there" }] };
const NOW = 1_700_000_000_000;
/// The programs started, ended after the tests whatever came of them (one a failed assertion left running would keep
/// the test's process waiting).
const started = new Set<MbProcess>();
after(() => Promise.all([...started].map((p) => p.terminate())));

/// The program's export, asked as the runner asks it, the time said with each ask (the test's).
class MbExport {
  readonly #p: MbProcess;
  readonly #waiting = new Map<number, { resolve: (v: Json) => void; reject: (e: Error) => void }>();
  #next = 0;
  now = NOW;

  constructor(db: string, replica: string, data: string, options: { batchBytes?: number; fold?: boolean }) {
    const args = ["--builder", "replica-export", "--db", db, "--replica", replica, "--data-dir", data, "--origin", ORIGIN, "--sep", sep];
    if (options.batchBytes !== undefined) args.push("--batch-bytes", String(options.batchBytes));
    if (options.fold === false) args.push("--no-fold");
    this.#p = new MbProcess(binary!, args);
    started.add(this.#p);
    this.#p.on("message", (m: Json) => {
      const w = this.#waiting.get(m.id);
      this.#waiting.delete(m.id);
      if (m.error !== undefined) w?.reject(new Error(m.error));
      else w?.resolve(m.answer);
    });
    this.#p.on("exit", () => {
      for (const w of this.#waiting.values()) w.reject(new Error("the program ended"));
      this.#waiting.clear();
    });
  }

  ask(m: Json): Promise<Json> {
    const id = ++this.#next;
    return new Promise((resolve, reject) => {
      this.#waiting.set(id, { resolve, reject });
      this.#p.postMessage({ ...m, id, now: this.now });
    });
  }
}

/// Both exporters on one station's database, each its own replica directory, asked the same in turn.
class Both {
  ts: Exporter;
  mb: MbExport;
  readonly made: ReturnType<typeof station>;
  readonly options: { batchBytes?: number; fold?: boolean };
  now = NOW;
  told: Told = nothingTold();
  passes = 0;

  constructor(made: ReturnType<typeof station>, options: { batchBytes?: number; fold?: boolean } = {}) {
    this.made = made;
    this.options = options;
    made.store.subscribe((c) => void tell(this.told, c));
    this.ts = this.#ts();
    this.mb = new MbExport(made.db, this.replica("mb"), made.data, options);
  }

  replica(which: "ts" | "mb") {
    return join(this.made.data, `replica-${which}`);
  }

  #ts() {
    const e = new Exporter({ db: this.made.db, replica: this.replica("ts"), dataDir: this.made.data, origin: ORIGIN, now: () => this.now, ...this.options });
    e.setPlaces(places);
    return e;
  }

  async start() {
    this.mb.now = this.now;
    await this.mb.ask({ type: "places", places });
  }

  /// Both started again after they were closed (as a station does): their first pass reads the small tables whole.
  async reopen() {
    this.ts = this.#ts();
    this.mb = new MbExport(this.made.db, this.replica("mb"), this.made.data, this.options);
    await this.start();
  }

  /// A pass of each, told what the store said since the last; the answers compared, then what each wrote.
  async pass(told = this.take()): Promise<Json> {
    this.mb.now = this.now;
    const ts = { ...this.ts.pass(told), empty: this.ts.empty() };
    const mb = await this.mb.ask({ type: "pass", told });
    this.passes++;
    assert.deepEqual(normal(mb), normal(ts), `pass ${this.passes}: the answers`);
    this.same(`pass ${this.passes}`);
    return ts;
  }

  /// Passes until neither has more.
  async drain(told = this.take()) {
    let p = await this.pass(told);
    while (p.more) p = await this.pass(nothingTold());
    return p;
  }

  take(): Told {
    const t = this.told;
    this.told = nothingTold();
    return t;
  }

  /// What each wrote: its state, its generations' heads and batches, line for line.
  same(when: string) {
    assert.deepEqual(state(this.replica("mb")), state(this.replica("ts")), `${when}: export.db`);
    assert.deepEqual(written(this.replica("mb")), written(this.replica("ts")), `${when}: the generations`);
  }

  async close() {
    this.ts.close();
    await this.mb.ask({ type: "close" });
  }
}

/// A generation's name with its random part left out (its time kept).
const genOf = (g: string) => g.replace(/-[0-9a-f]{8}$/, "-*");
/// A batch's name with its bytes' hash left out: zstd's frame of the same lines differs between Node's and the shell's.
const batchOf = (b: string) => b.replace(/-[0-9a-f]{8}\.ndjson\.zst$/, "-*.ndjson.zst");

/// What a head says, its random parts (the generation's, each run's) left out.
function headOf(h: Head | Json): Json {
  return { ...h, gen: genOf(h.gen), batches: h.batches.map(batchOf), runs: h.runs.map((r: Json) => ({ ...r, run: "*" })), bytes: "(compressed)" };
}

function normal(passed: Json): Json {
  return { ...passed, heads: Object.fromEntries(Object.entries(passed.heads).map(([ws, h]) => [ws, headOf(h)])) };
}

/// The exporter's state: every row of export.db, generations' names without their random part.
function state(replica: string): Json {
  const d = new DatabaseSync(join(replica, "export.db"), { readOnly: true });
  const out: Json = {};
  for (const t of ["meta", "digests", "threads", "files", "sent", "entering"]) {
    out[t] = d.prepare(`SELECT * FROM ${t} ORDER BY 1, 2`).all().map((r: Json) => (t === "meta" && String(r.k).startsWith("gen:") ? { ...r, v: genOf(r.v) } : { ...r }));
  }
  d.close();
  return out;
}

/// Each workspace's generations under own/: the head (its text, as it is written, and what it says) and each batch's
/// header and lines; nothing else there.
function written(replica: string): Json {
  const own = ownDir(replica);
  const out: Json = {};
  if (!existsSync(own)) return out;
  for (const ws of readdirSync(own).sort()) {
    for (const gen of readdirSync(join(own, ws)).sort()) {
      const dir = join(own, ws, gen);
      const text = readFileSync(join(dir, "head.json"), "utf8");
      const head = JSON.parse(text) as Head;
      const log = existsSync(join(dir, "log")) ? readdirSync(join(dir, "log")).sort() : [];
      // (two generations of one time would be one key here: each test names them apart)
      assert.equal(out[`${ws}/${genOf(gen)}`], undefined, `two generations of ${ws} at one time`);
      out[`${ws}/${genOf(gen)}`] = {
        head: headOf(head),
        // (written by JSON.stringify(head, null, 1): the same text, its random parts and size aside)
        text: text.replaceAll(head.gen, genOf(head.gen)).replace(/"run": "[0-9a-f]{8}"/g, '"run": "*"').replace(/"bytes": \d+/, '"bytes": 0').replace(/-[0-9a-f]{8}\.ndjson\.zst/g, "-*.ndjson.zst"),
        log: log.map(batchOf),
        batches: head.batches.map((b) => {
          const { header, lines } = decodeBatch(readFileSync(join(dir, "log", b)));
          return { header: { ...header, gen: genOf(header.gen) }, lines: [...lines] };
        }),
      };
    }
  }
  return out;
}

/// What a station did after its copies were first made: messages, edits, turns, marks, a chat archived and back, a file
/// attached and another changed, then a chat deleted.
function work(made: ReturnType<typeof station>, round: number) {
  const s = made.store;
  const a = s.sessionThreads("chat:a")[0]!.thread.id;
  const b = s.sessionThreads("chat:b")[0]!.thread.id;
  s.startTurnFor(`turn-${round}`, "chat:a", "message", { profile: "cc", person: "p@x", thread: a });
  for (let i = 0; i < 3; i++) s.insertMessage({ thread: a, ts: `r${round}.${i}`, authorKind: "person", author: "p@x", text: `round ${round} 中文 ${i} "quoted"   😀` });
  // (long lines of characters outside the BMP and of CJK: a batch is cut by their bytes in UTF-8)
  for (let i = 0; i < 4; i++) s.insertMessage({ thread: a, ts: `r${round}.long${i}`, authorKind: "agent", author: "chat:a", text: "\ud83d\ude00".repeat(300 + i * 7) + "长".repeat(200) });
  s.endTurn(`turn-${round}`, "completed", null, "all_done", null);
  s.setRead("p@x", a, 30 + round);
  s.setRead("q@x", b, round);
  s.setPin("p@x", "chat:a", round % 2 === 0);
  s.setThreadHidden(b, round % 2 === 1, "p@x");
  if (round === 1) s.editMessage("ember", "C", "ts-chat:a", "r1.1", "round 1, edited");
  if (round === 2) s.setArchived("chat:b", false, "p@x");
  if (round === 2) s.setThreadTitle(a, "Renamed 改名");
  if (round === 3) {
    const doc = attach(made.data, "chat:a", "doc.txt", "a document");
    s.insertMessage({ thread: a, ts: "r3.doc", authorKind: "person", author: "p@x", text: "a doc", attachments: [doc] });
    s.insertLetter({ thread: a, ts: "r3.letter", authorKind: "agent", author: "chat:a", text: "dear o", letter: { way: "out", title: "Chat o", link: null } });
  }
  if (round === 4) {
    // (the picture written again: the same size, another time and other bytes, hashed again)
    const pic = Object.keys(made.files)[0]!;
    writeFileSync(pic, "a pictur2");
    utimesSync(pic, new Date(1_600_000_000_000), new Date(1_600_000_000_000));
  }
  if (round === 8) s.deleteSession(made.deleted);
}

test("the MoonBit export writes what export.ts writes, pass by pass: answers, state, heads and batches", { skip }, async () => {
  for (const options of [{}, { fold: false }, { batchBytes: 2048 }]) {
    const made = station();
    const both = new Both(made, options);
    await both.start();
    // the first passes: every chat entered, the small tables read whole
    both.take();
    const first = await both.drain();
    assert.equal(first.heads[HOME].chats, 3);
    // nothing changed: nothing written
    assert.equal((await both.pass(nothingTold())).wrote, 0);
    for (let round = 1; round <= 8; round++) {
      both.now += 60_000;
      work(made, round);
      await both.drain();
    }
    // a long chat: pages of entries past what a pass reads, a batch's worth past what one holds
    const big = chat(made.store, made.data, "chat:big", OTHER, 1_200);
    void big;
    both.now += 60_000;
    await both.drain();
    // stopped while a chat went and marks changed, nothing told: found as they start again
    await both.close();
    made.store.deleteSession("chat:o");
    made.store.setRead("z@x", made.store.sessionThreads("chat:a")[0]!.thread.id, 3);
    both.told = nothingTold();
    await both.reopen();
    await both.drain(nothingTold());
    // where the files are, for a place that lacks them
    const hashes = [...Object.keys(both.ts.heads()[HOME]!.files), "f".repeat(64)];
    const ts = Object.fromEntries(hashes.flatMap((h) => { const s = both.ts.sourceOf(h); return s === null ? [] : [[h, s]]; }));
    assert.deepEqual(await both.mb.ask({ type: "sources", hashes }), ts);
    // a new generation of each workspace, after one held elsewhere: everything written again
    both.ts.newGenerations(NOW + 10_000_000);
    await both.mb.ask({ type: "newGenerations", after: NOW + 10_000_000 });
    await both.drain(nothingTold());
    await both.close();
    made.store.close();
  }
});

test("the MoonBit export fails a pass as export.ts does, and takes up from the same place", { skip }, async () => {
  const made = station();
  const both = new Both(made);
  await both.start();
  both.take();
  await both.drain();
  made.store.insertMessage({ thread: made.store.sessionThreads("chat:a")[0]!.thread.id, ts: "lost?", authorKind: "person", author: "p@x", text: "said as the pass failed" });
  // each one's head cannot be written (a directory where it goes): the batch is written, the pass fails
  const heads = (which: "ts" | "mb") => {
    const own = ownDir(both.replica(which));
    const gen = readdirSync(join(own, HOME))[0]!;
    return join(own, HOME, gen);
  };
  for (const w of ["ts", "mb"] as const) {
    renameSync(join(heads(w), "head.json"), join(heads(w), "head.kept"));
    mkdirSync(join(heads(w), "head.json"));
  }
  const told = both.take();
  assert.throws(() => both.ts.pass(told));
  await assert.rejects(both.mb.ask({ type: "pass", told }));
  for (const w of ["ts", "mb"] as const) {
    rmSync(join(heads(w), "head.json"), { recursive: true });
    renameSync(join(heads(w), "head.kept"), join(heads(w), "head.json"));
  }
  await both.drain(nothingTold());
  await both.close();
  made.store.close();
});

test("the MoonBit export finds a database rolled back under it as export.ts does: written again", { skip }, async () => {
  const made = station();
  const backup = join(made.data, "backup.db");
  made.store.close();
  copyFileSync(made.db, backup);
  made.store = Store.open(made.db, join(made.data, "archive"));
  const both = new Both(made);
  await both.start();
  for (let i = 0; i < 40; i++) made.store.insertMessage({ thread: made.store.sessionThreads("chat:a")[0]!.thread.id, ts: `later.${i}`, authorKind: "person", author: "p@x", text: `later ${i}` });
  both.take();
  await both.drain();
  await both.close();
  made.store.close();
  for (const end of ["-wal", "-shm"]) rmSync(made.db + end, { force: true });
  copyFileSync(backup, made.db);
  made.store = Store.open(made.db, join(made.data, "archive"));
  // (a minute on: the generations written again are named after another time than those before)
  both.now += 60_000;
  await both.reopen();
  both.take();
  await both.drain(nothingTold());
  await both.close();
  made.store.close();
});

test("the export's runner runs the MoonBit program where it is built, its time the station's", { skip }, async () => {
  const made = station();
  const replica = join(made.data, "replica");
  const runner = new WorkerRunner({ db: made.db, replica, dataDir: made.data, origin: ORIGIN }, exportThread);
  await runner.places(places);
  let p = await runner.pass(nothingTold());
  while (p.more) p = await runner.pass(nothingTold());
  assert.equal(p.heads[HOME]!.chats, 3);
  assert.equal(p.empty, false);
  assert.ok(existsSync(join(genDir(ownDir(replica), HOME, p.heads[HOME]!.gen), "head.json")));
  await runner.close();
  made.store.close();
});

/// Everything of a database a restore made (the tables a copy holds, those the store's triggers derive from them, what
/// the restore keeps of itself), its rows in order; what each database draws as it is made left out.
function everything(db: string): Record<string, unknown[]> {
  const d = new DatabaseSync(db, { readOnly: true });
  const out: Record<string, unknown[]> = {};
  for (const { name } of d.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_stat%' ORDER BY name").all() as { name: string }[]) {
    if (name === "archive_last_meta") continue;
    const n = (d.prepare(`SELECT COUNT(*) AS n FROM pragma_table_info('${name}')`).get() as { n: number }).n;
    out[name] = d.prepare(`SELECT * FROM "${name}" ORDER BY ${Array.from({ length: n }, (_, i) => i + 1).join(", ")}`).all();
  }
  d.close();
  return out;
}

/// Every file under `dir`, by its path from there, with what it holds.
function filesUnder(dir: string, at = ""): Record<string, string> {
  const out: Record<string, string> = {};
  if (!existsSync(join(dir, at))) return out;
  for (const name of readdirSync(join(dir, at)).sort()) {
    const p = join(at, name);
    if (statSync(join(dir, p)).isDirectory()) Object.assign(out, filesUnder(dir, p));
    else out[p] = readFileSync(join(dir, p), "utf8");
  }
  return out;
}

/// A new station with the copy of `ws` in `replica` brought to it as a restore brings it, ready to be put in.
function brought(made: ReturnType<typeof station>, replica: string, ws: string, clock: ReturnType<typeof testClock>, ready: Json = {}) {
  const head = JSON.parse(readFileSync(join(genDir(ownDir(replica), ws, readdirSync(join(ownDir(replica), ws))[0]!), "head.json"), "utf8")) as Head;
  const dir = genDir(ownDir(replica), ws, head.gen);
  const to = dataDir("new");
  Store.open(join(to, "stillfail.db"), join(to, "archive"), clock.clock).close();
  const copy = join(to, "restore", "copy");
  mkdirSync(join(copy, "files"), { recursive: true });
  cpSync(dir, join(copy, head.gen), { recursive: true });
  const src = new Exporter({ db: made.db, replica, dataDir: made.data, origin: ORIGIN, now: () => 1 });
  for (const hash of Object.keys(head.files)) copyFileSync(src.sourceOf(hash)!, join(copy, "files", hash));
  src.close();
  writeFileSync(join(to, "restore", "ready.json"), JSON.stringify({ origin: ORIGIN, workspace: ws, gen: head.gen, name: "laptop", from: "x", ...ready }));
  return { to, head };
}

/// What a restore left: its database, the files it placed, what it said of itself, and whether what it brought stayed.
function leftBy(to: string): Json {
  // (each station's own directory said as one, what its rows' paths were moved to)
  return JSON.parse(JSON.stringify({
    db: everything(join(to, "stillfail.db")),
    sessions: filesUnder(join(to, "sessions")),
    restored: existsSync(join(to, "replica", "restored.json")) ? JSON.parse(readFileSync(join(to, "replica", "restored.json"), "utf8")) : null,
    formerly: existsSync(join(to, "replica", "formerly.json")) ? readFileSync(join(to, "replica", "formerly.json"), "utf8") : null,
    kept: filesUnder(join(to, "restore")),
  }).replaceAll(to, "<to>"));
}

test("a copy taken back by the MoonBit program makes what restore.ts makes, from either's copy; refused and half placed alike", { skip }, async () => {
  const made = station();
  // (a session copied while it ran: taken back at rest)
  made.store.setRunning("chat:a", true);
  made.store.setRunning("chat:o", true);
  const both = new Both(made);
  await both.start();
  both.take();
  await both.drain();
  for (let round = 1; round <= 8; round++) {
    work(made, round);
    await both.drain();
  }
  await both.close();
  const clock = testClock();
  for (const ws of [HOME, OTHER]) {
    // restore.ts and the program, each from the TypeScript export's copy, and the program from its own
    const byTs = brought(made, both.replica("ts"), ws, clock);
    const byMb = brought(made, both.replica("ts"), ws, clock);
    const ofMb = brought(made, both.replica("mb"), ws, clock);
    const ready = takeBack(byTs.to, join(byTs.to, "stillfail.db"), 5);
    assert.deepEqual(await takeBackSoon(byMb.to, join(byMb.to, "stillfail.db"), 5, binary), ready);
    assert.deepEqual(await takeBackSoon(ofMb.to, join(ofMb.to, "stillfail.db"), 5, binary), { ...ready!, gen: ofMb.head.gen });
    const want = leftBy(byTs.to);
    assert.equal(want.restored.error, null);
    assert.ok(Object.keys(want.sessions).length > 0 || ws === OTHER, "its files placed");
    assert.deepEqual(leftBy(byMb.to), want, `${ws}: the same, from the same copy`);
    const theirs = leftBy(ofMb.to);
    // (the program's copy is another generation: its name in what the restore keeps of itself)
    theirs.db.replica_restored = theirs.db.replica_restored.map((r: Json) => ({ ...r, gen: byTs.head.gen }));
    assert.deepEqual(theirs, want, `${ws}: the same, from the program's copy`);
    // into the station that now has chats: refused, said, let go
    for (const to of [byTs.to, byMb.to]) {
      const again = join(to, "restore", "copy");
      mkdirSync(again, { recursive: true });
      cpSync(join(genDir(ownDir(both.replica("ts")), ws, byTs.head.gen)), join(again, "1-00000000"), { recursive: true });
      writeFileSync(join(again, "1-00000000", "head.json"), JSON.stringify({ ...byTs.head, gen: "1-00000000" }));
      writeFileSync(join(to, "restore", "ready.json"), JSON.stringify({ origin: "b".repeat(64), workspace: ws, gen: "1-00000000", name: "other", from: "x" }));
    }
    takeBack(byTs.to, join(byTs.to, "stillfail.db"), 6);
    await takeBackSoon(byMb.to, join(byMb.to, "stillfail.db"), 6, binary);
    assert.equal(leftBy(byTs.to).restored.reason, "notEmpty");
    assert.deepEqual(leftBy(byMb.to), leftBy(byTs.to), `${ws}: refused alike`);
  }
  // where the picture goes cannot be made: the rows in, the files pending, what was brought kept; then placed
  const pending = [brought(made, both.replica("ts"), HOME, clock), brought(made, both.replica("ts"), HOME, clock)];
  for (const { to } of pending) {
    const uploads = join(to, "sessions", "chat", "chat:a", "workspace", "uploads");
    mkdirSync(join(uploads, ".."), { recursive: true });
    writeFileSync(uploads, "in the way");
  }
  takeBack(pending[0]!.to, join(pending[0]!.to, "stillfail.db"), 7);
  await takeBackSoon(pending[1]!.to, join(pending[1]!.to, "stillfail.db"), 7, binary);
  const [x, y] = pending.map(({ to }) => leftBy(to));
  assert.equal(x.restored.pending, true);
  // (what failed is said in each one's words: Node's and Rust's)
  assert.match(y.restored.error, /^the chats are in; 2 of their files not placed yet: /);
  for (const r of [x, y]) r.restored.error = r.restored.error.replace(/yet: .*/, "yet: (said)");
  assert.deepEqual(y, x, "pending alike");
  for (const { to } of pending) rmSync(join(to, "sessions", "chat", "chat:a", "workspace", "uploads"));
  takeBack(pending[0]!.to, join(pending[0]!.to, "stillfail.db"), 8);
  await takeBackSoon(pending[1]!.to, join(pending[1]!.to, "stillfail.db"), 8, binary);
  assert.deepEqual(leftBy(pending[1]!.to), leftBy(pending[0]!.to), "placed alike");
  // nothing waiting: nothing said
  assert.equal(await takeBackSoon(pending[1]!.to, join(pending[1]!.to, "stillfail.db"), 9, binary), null);
  made.store.close();
});
