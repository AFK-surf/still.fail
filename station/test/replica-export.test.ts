// What a station's copy holds (replica/export.ts, format.ts) and what a restore makes of it (restore.ts): the rows of
// the tables that must survive, equal, the attached files by their hash, a deleted chat deleted.
import assert from "node:assert/strict";
import { copyFileSync, cpSync, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import { test } from "node:test";
import { Exporter, genDir, nothingTold, ownDir } from "../src/replica/export.ts";
import { tell } from "../src/replica/copies.ts";
import { decodeBatch } from "../src/replica/format.ts";
import { build, readCopy, takeBack } from "../src/replica/restore.ts";
import { Store } from "../src/store/store.ts";
import { HOME, ORIGIN, OTHER, dataDir, rowsOf, station } from "./replica-fakes.ts";
import { testClock } from "./hub-fakes.ts";

const places = { home: HOME, workspaces: [{ workspace: HOME, name: "laptop" }, { workspace: OTHER, name: "laptop there" }] };

function exporter(data: string, db: string, now = () => 1_000) {
  const e = new Exporter({ db, replica: join(data, "replica"), dataDir: data, origin: ORIGIN, now });
  e.setPlaces(places);
  return e;
}

/// Passes until nothing more is waiting.
function drain(e: Exporter, told = nothingTold()) {
  let p = e.pass(told);
  while (p.more) p = e.pass(nothingTold());
  return p;
}

/// The generation of `ws` restored into a new station's database: its rows, and where its files went.
function restored(from: string, ws: string, origin = ORIGIN) {
  const head = readHeads(from, ws);
  const dir = genDir(ownDir(join(from, "replica")), ws, head.gen);
  const files = join(dataDir("files"), "files");
  mkdirSync(files, { recursive: true });
  const e = new Exporter({ db: join(from, "stillfail.db"), replica: join(from, "replica"), dataDir: from, origin, now: () => 1 });
  for (const hash of Object.keys(head.files)) copyFileSync(e.sourceOf(hash)!, join(files, hash));
  e.close();
  const to = dataDir("new");
  Store.open(join(to, "stillfail.db"), join(to, "archive")).close();
  const built = build(join(to, "stillfail.db"), dir, files, to);
  return { to, built, head };
}

function readHeads(from: string, ws: string) {
  const e = exporter(from, join(from, "stillfail.db"));
  const h = e.heads()[ws]!;
  e.close();
  return h;
}

test("a station's chats of a workspace come back from its copy as they were: rows, files, an archived chat", () => {
  const made = station();
  made.store.deleteSession(made.deleted);
  const e = exporter(made.data, made.db);
  const p = drain(e);
  e.close();
  assert.equal(p.heads[HOME]!.chats, 2, "the home workspace's two chats left");
  assert.equal(p.heads[OTHER]!.chats, 1);
  const { to, built } = restored(made.data, HOME);
  assert.equal(built.missing, 0);
  const before = rowsOf(made.store.db, null, made.data, to);
  const after = new DatabaseSync(join(to, "stillfail.db"));
  const now = rowsOf(after, null);
  for (const table of Object.keys(before)) assert.deepEqual([...now[table]!.entries()].sort(), [...before[table]!.entries()].sort(), table);
  // the other workspace's chat is not in this one's copy
  assert.equal(after.prepare("SELECT COUNT(*) AS n FROM sessions WHERE key = 'chat:o'").get()!.n, 0);
  // its file, where its message says, as it was
  const path = (JSON.parse((after.prepare("SELECT attachments FROM entries WHERE ts = 'a.pic'").get() as { attachments: string }).attachments) as { path: string }[])[0]!.path;
  assert.ok(path.startsWith(to));
  assert.equal(readFileSync(path, "utf8"), "a picture");
  after.close();
  made.store.close();
});

test("a chat deleted after it was copied is deleted in the copy, its file with it", () => {
  const made = station();
  const e = exporter(made.data, made.db);
  drain(e);
  const goneThread = made.store.sessionThreads(made.deleted)[0]!.thread.id;
  made.store.deleteSession(made.deleted);
  const told = nothingTold();
  told.removedSessions.push({ key: made.deleted, ws: null });
  told.removedThreads.push({ id: goneThread, ws: null });
  const p = drain(e, told);
  e.close();
  const head = p.heads[HOME]!;
  // folded at once: one batch, nothing of the deleted chat in it
  assert.equal(head.batches.length, 1);
  const { folded } = readCopy(genDir(ownDir(join(made.data, "replica")), HOME, head.gen));
  assert.equal(folded.table("sessions").some((r) => r.key === "chat:gone"), false);
  assert.equal(folded.table("entries").some((r) => r.thread === goneThread), false);
  const text = JSON.stringify(folded.records());
  assert.equal(text.includes("chat:gone says"), false);
  made.store.close();
});

test("what changes after a copy is made is in the next batch, and nothing is written when nothing changed", () => {
  const made = station();
  const e = exporter(made.data, made.db);
  const first = drain(e);
  const before = first.heads[HOME]!.to;
  assert.equal(e.pass(nothingTold()).wrote, 0);
  const thread = made.store.sessionThreads("chat:a")[0]!.thread.id;
  made.store.insertMessage({ thread, ts: "later", authorKind: "person", author: "p@x", text: "one more" });
  made.store.setThreadTitle(thread, "Renamed");
  const told = nothingTold();
  told.threads.push(thread);
  const p = e.pass(told);
  assert.equal(p.wrote, 1);
  assert.equal(p.heads[HOME]!.to, before + 1);
  const { folded } = readCopy(genDir(ownDir(join(made.data, "replica")), HOME, p.heads[HOME]!.gen));
  assert.ok(folded.table("entries").some((r) => r.text === "one more"));
  assert.equal(folded.table("threads").find((r) => r.id === thread)!.title, "Renamed");
  e.close();
  made.store.close();
  assert.ok(existsSync(join(made.data, "replica", "export.db")));
});

test("a pass that fails after it read leaves the exporter where it was: the next pass's copy holds every row", () => {
  const made = station();
  const e = exporter(made.data, made.db);
  drain(e);
  const head = e.heads()[HOME]!;
  const dir = genDir(ownDir(join(made.data, "replica")), HOME, head.gen);
  const thread = made.store.sessionThreads("chat:a")[0]!.thread.id;
  made.store.insertMessage({ thread, ts: "lost?", authorKind: "person", author: "p@x", text: "said as the pass failed" });
  // its head cannot be written (a directory where it goes): the batch is written, the pass throws
  renameSync(join(dir, "head.json"), join(dir, "head.kept"));
  mkdirSync(join(dir, "head.json"));
  assert.throws(() => e.pass(nothingTold()));
  rmSync(join(dir, "head.json"), { recursive: true });
  renameSync(join(dir, "head.kept"), join(dir, "head.json"));
  const p = drain(e);
  const { folded } = readCopy(genDir(ownDir(join(made.data, "replica")), HOME, p.heads[HOME]!.gen));
  assert.ok(folded.table("entries").some((r) => r.text === "said as the pass failed"), "the row read by the failed pass is in the copy");
  assert.equal(p.heads[HOME]!.to, head.to + 1, "numbered on from the head that was written");
  e.close();
  made.store.close();
});

test("a restore stopped after its rows went in, run again, does not refuse them as chats of the station's own; one into a station with chats says why and lets its copy go", () => {
  const made = station();
  const e = exporter(made.data, made.db);
  drain(e);
  e.close();
  const head = readHeads(made.data, HOME);
  const dir = genDir(ownDir(join(made.data, "replica")), HOME, head.gen);
  const files = join(dataDir("files"), "files");
  mkdirSync(files, { recursive: true });
  const src = new Exporter({ db: made.db, replica: join(made.data, "replica"), dataDir: made.data, origin: ORIGIN, now: () => 1 });
  for (const hash of Object.keys(head.files)) copyFileSync(src.sourceOf(hash)!, join(files, hash));
  src.close();
  // brought into a new station as a restore brings it, ready to be put in
  const to = dataDir("new");
  Store.open(join(to, "stillfail.db"), join(to, "archive")).close();
  const copy = join(to, "restore", "copy");
  mkdirSync(copy, { recursive: true });
  cpSync(dir, join(copy, head.gen), { recursive: true });
  cpSync(files, join(copy, "files"), { recursive: true });
  writeFileSync(join(to, "restore", "ready.json"), JSON.stringify({ origin: ORIGIN, workspace: HOME, gen: head.gen, name: "laptop", from: "x" }));
  // its rows went in, then it stopped (before its files, `formerly` and what came of it)
  build(join(to, "stillfail.db"), join(copy, head.gen), join(copy, "files"), to);
  assert.ok(takeBack(to, join(to, "stillfail.db"), 5) !== null);
  const outcome = JSON.parse(readFileSync(join(to, "replica", "restored.json"), "utf8"));
  assert.equal(outcome.error, null);
  assert.deepEqual(JSON.parse(readFileSync(join(to, "replica", "formerly.json"), "utf8")), [ORIGIN]);
  assert.equal(existsSync(join(to, "restore")), false, "what it brought let go");
  // another restore, into the same station that now has chats: refused, said, let go
  const again = join(to, "restore", "copy");
  mkdirSync(again, { recursive: true });
  cpSync(dir, join(again, "1-00000000"), { recursive: true });
  writeFileSync(join(again, "1-00000000", "head.json"), JSON.stringify({ ...head, gen: "1-00000000" }));
  writeFileSync(join(to, "restore", "ready.json"), JSON.stringify({ origin: "b".repeat(64), workspace: HOME, gen: "1-00000000", name: "other", from: "x" }));
  takeBack(to, join(to, "stillfail.db"), 6);
  const refused = JSON.parse(readFileSync(join(to, "replica", "restored.json"), "utf8"));
  assert.match(refused.error, /chats of its own/);
  assert.equal(refused.reason, "notEmpty", "said in the settings' words");
  assert.equal(existsSync(join(to, "restore")), false, "not tried again at every start");
  made.store.close();
});

test("a restore whose files cannot all be placed keeps what it brought: the next start places them, and only then lets it go", () => {
  const made = station();
  const e = exporter(made.data, made.db);
  drain(e);
  e.close();
  const head = readHeads(made.data, HOME);
  const dir = genDir(ownDir(join(made.data, "replica")), HOME, head.gen);
  const to = dataDir("new");
  Store.open(join(to, "stillfail.db"), join(to, "archive")).close();
  const copy = join(to, "restore", "copy");
  mkdirSync(join(copy, "files"), { recursive: true });
  cpSync(dir, join(copy, head.gen), { recursive: true });
  const src = new Exporter({ db: made.db, replica: join(made.data, "replica"), dataDir: made.data, origin: ORIGIN, now: () => 1 });
  for (const hash of Object.keys(head.files)) copyFileSync(src.sourceOf(hash)!, join(copy, "files", hash));
  src.close();
  writeFileSync(join(to, "restore", "ready.json"), JSON.stringify({ origin: ORIGIN, workspace: HOME, gen: head.gen, name: "laptop", from: "x" }));
  // where the picture goes cannot be made (a file in the way of its folder): the files step fails, its rows are in
  const uploads = join(to, "sessions", "chat", "chat:a", "workspace", "uploads");
  mkdirSync(join(uploads, ".."), { recursive: true });
  writeFileSync(uploads, "in the way");
  takeBack(to, join(to, "stillfail.db"), 5);
  const pending = JSON.parse(readFileSync(join(to, "replica", "restored.json"), "utf8"));
  assert.equal(pending.pending, true, "said: its files still to be placed");
  assert.equal(pending.reason, "error");
  assert.ok(existsSync(join(to, "restore", "ready.json")), "what it brought kept for the next start");
  assert.ok(existsSync(join(copy, "files")));
  const db = new DatabaseSync(join(to, "stillfail.db"));
  assert.ok((db.prepare("SELECT COUNT(*) AS n FROM replica_restore_files").get() as { n: number }).n > 0, "where the files go kept beside the rows");
  assert.ok((db.prepare("SELECT COUNT(*) AS n FROM threads").get() as { n: number }).n > 0, "the rows are in");
  db.close();
  // the next start, the way clear: the files placed, then let go
  rmSync(uploads);
  takeBack(to, join(to, "stillfail.db"), 6);
  const done = JSON.parse(readFileSync(join(to, "replica", "restored.json"), "utf8"));
  assert.equal(done.error, null);
  assert.equal(done.pending, false);
  assert.equal(readFileSync(join(uploads, "pic.png"), "utf8"), "a picture");
  assert.equal(existsSync(join(to, "restore")), false, "let go once its files are placed");
  made.store.close();
});

/// Every table of the database at `db` (the store's own and those derived by its triggers too), its rows in order.
function everything(db: string): Record<string, unknown[]> {
  const d = new DatabaseSync(db, { readOnly: true });
  const out: Record<string, unknown[]> = {};
  for (const { name } of d.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_stat%' ORDER BY name").all() as { name: string }[]) {
    const n = (d.prepare(`SELECT COUNT(*) AS n FROM pragma_table_info('${name}')`).get() as { n: number }).n;
    out[name] = d.prepare(`SELECT * FROM "${name}" ORDER BY ${Array.from({ length: n }, (_, i) => i + 1).join(", ")}`).all();
  }
  d.close();
  return out;
}

test("a copy restored from its batches as they were written (rows said again, a pass said twice) makes the same database as one from the generation folded whole", () => {
  const made = station();
  const live = join(made.data, "replica");
  // what the store says changed, told to the export as a station tells it (copies.ts `tell`)
  let told = nothingTold();
  made.store.subscribe((c) => void tell(told, c));
  const pass = (e: Exporter) => {
    const t = told;
    told = nothingTold();
    return drain(e, t);
  };
  // batches left as each pass wrote them
  const unfoldedExporter = () => {
    const x = new Exporter({ db: made.db, replica: live, dataDir: made.data, origin: ORIGIN, now: () => 1_000, fold: false });
    x.setPlaces(places);
    return x;
  };
  const e = unfoldedExporter();
  pass(e);
  const a = made.store.sessionThreads("chat:a")[0]!.thread.id;
  for (let i = 0; i < 6; i++) {
    // a turn said as it starts and again as it ends; the session said on each change; marks moved; a chat deleted
    made.store.startTurnFor(`turn-${i}`, "chat:a", "message", { profile: "cc", person: "p@x", thread: a });
    made.store.insertMessage({ thread: a, ts: `more.${i}`, authorKind: "person", author: "p@x", text: `more ${i}` });
    pass(e);
    made.store.endTurn(`turn-${i}`, "completed", null, "all_done", null);
    made.store.setRead("p@x", a, 30 + i);
    made.store.setPin("p@x", "chat:a", i % 2 === 0);
    if (i === 2) made.store.editMessage("ember", "C", "ts-chat:a", "more.1", "more, edited");
    if (i === 3) made.store.setArchived("chat:b", false, "p@x");
    if (i === 4) made.store.deleteSession(made.deleted);
    pass(e);
  }
  e.close();
  // the export started again (as a station does), its first pass reading the small tables whole, nothing new to say
  const restarted = unfoldedExporter();
  pass(restarted);
  restarted.close();
  const head = readHeads(made.data, HOME);
  const dir = genDir(ownDir(live), HOME, head.gen);
  assert.ok(head.batches.length > 10, `${head.batches.length} batches as written`);
  // as written, and the last pass's batch said again (as a pass is after one that failed)
  const unfolded = join(dataDir("unfolded"), head.gen);
  cpSync(dir, unfolded, { recursive: true });
  writeFileSync(join(unfolded, "head.json"), JSON.stringify({ ...head, batches: [...head.batches, head.batches[head.batches.length - 1]!] }));
  // the same generation folded whole: each row said once
  const f = exporter(made.data, made.db);
  const whole = nothingTold();
  whole.removedSessions.push({ key: "chat:none", ws: null });
  const folded = drain(f, whole).heads[HOME]!;
  f.close();
  assert.equal(folded.gen, head.gen);
  assert.ok(folded.batches.length < head.batches.length, `folded into ${folded.batches.length}`);
  // (the two differ in form: rows said again and a pass said twice on one side, each row once on the other)
  const said = (d: string, bs: string[]) => bs.reduce((n, b) => n + [...decodeBatch(readFileSync(join(d, "log", b))).lines].filter((l) => l.startsWith('{"r"')).length, 0);
  assert.ok(said(unfolded, [...head.batches, head.batches[head.batches.length - 1]!]) > said(dir, folded.batches), "rows said more than once as written");
  // the same history on both sides: the batches as written, folded here, say line for line what the generation folded says
  const mine = readCopy(unfolded).folded;
  const theirs = folded.batches.flatMap((b) => [...decodeBatch(readFileSync(join(dir, "log", b))).lines]);
  assert.deepEqual([...mine.records()], theirs, "the two copies say the same");
  mine.close();
  // (both made on the same test clock: the times a database is made with, equal by construction)
  const clock = testClock();
  const fresh = () => {
    const to = dataDir("into");
    Store.open(join(to, "stillfail.db"), join(to, "archive"), clock.clock).close();
    return to;
  };
  // What a database is given as it is made, not by any row restored: two made alike differ only there. Each named
  // with why, and left out of the comparison below; anything else two fresh ones differ in fails here.
  const MADE_PER_DATABASE: Record<string, string[]> = {
    // a random epoch each database draws as its schema is made (store's archive_last guard)
    archive_last_meta: ["epoch"],
  };
  const blank = (all: Record<string, unknown[]>) => {
    for (const [table, columns] of Object.entries(MADE_PER_DATABASE)) {
      all[table] = (all[table] ?? []).map((row) => ({ ...(row as object), ...Object.fromEntries(columns.map((c) => [c, "(made per database)"])) }));
    }
    return all;
  };
  const differing = (x: Record<string, unknown[]>, y: Record<string, unknown[]>) =>
    [...new Set([...Object.keys(x), ...Object.keys(y)])].filter((t) => JSON.stringify(x[t] ?? null) !== JSON.stringify(y[t] ?? null)).map((t) => {
      const cells = new Set<string>();
      const xs = (x[t] ?? []) as Record<string, unknown>[];
      const ys = (y[t] ?? []) as Record<string, unknown>[];
      for (let i = 0; i < Math.max(xs.length, ys.length); i++) {
        for (const c of new Set([...Object.keys(xs[i] ?? {}), ...Object.keys(ys[i] ?? {})])) {
          if (JSON.stringify(xs[i]?.[c]) !== JSON.stringify(ys[i]?.[c])) cells.add(c);
        }
      }
      return `${t} (${xs.length} rows against ${ys.length}; ${[...cells].join(", ")})`;
    });
  // two fresh databases: what differs between them is what is made per database, and only that
  const [one, two] = [fresh(), fresh()];
  assert.deepEqual(differing(blank(everything(join(one, "stillfail.db"))), blank(everything(join(two, "stillfail.db")))), [], "two fresh databases differ only in what is named above");
  // (both as the same station's data directory: the paths a restore moves into it come out the same)
  const sameData = join(dataDir("as"), "station");
  const into = (from: string, to: string) => {
    build(join(to, "stillfail.db"), from, join(to, "no-files"), sameData);
    return blank(everything(join(to, "stillfail.db")));
  };
  const once = into(dir, one);
  const again = into(unfolded, two);
  // every table that differs, all of them in one failure
  assert.deepEqual(differing(once, again), [], "the restores differ");
  assert.ok(once.turns!.length >= 7 && once.entries!.length > 30, "what was restored is there");
  assert.equal(once.sessions!.filter((r) => (r as { key: string }).key === made.deleted).length, 0, "the deleted chat stays deleted");
  // and both are the station as it is now, row for row (not merely alike: a fold that kept an older saying of a row,
  // or let a deleted chat back, makes both wrong the same way)
  const asItIs = rowsOf(made.store.db, null, made.data, sameData);
  for (const to of [one, two]) {
    const d = new DatabaseSync(join(to, "stillfail.db"), { readOnly: true });
    const back = rowsOf(d, null);
    for (const table of Object.keys(asItIs)) assert.deepEqual([...back[table]!.entries()].sort(), [...asItIs[table]!.entries()].sort(), `${table}, restored into ${to === one ? "the first" : "the second"}`);
    d.close();
  }
  made.store.close();
});
