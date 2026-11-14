// Every declared read of the chat table (db/chat-reads.ts) is told by every write that changes its answer, and by as
// few others as its declaration says: generated over every declaration, no code here for any one of them.
//
// On the real-size workspace (real-size.ts), rows of it are written one change at a time: each field of their records
// changed (a flag turned, a number raised, a value taken away, one put where none was; an agent's process and its
// watch), the row put new, dropped, archived, its station's rows put in another order. Around each write every
// declaration is read as a view reads it (Data.chatFound, in a computed: its answer as kept, #chatRows) and as its
// statement gives it then (AccountDb, nothing kept), with the parameters a list asks (two ways: all of the stations'
// rows; the viewer's own, every visibility, the written row read apart), and:
// - an answer that differs after the write was told (its computed made again): never one left as it was;
// - an answer a view reads is the one its statement gives then (what is kept of it is never stale);
// - how many writes told a read whose answer stayed the same is counted (`by` exact: none), and held to TOLD_SAME,
//   which only falls. CHAT_TOLD_PRINT=1 prints it as it would be.
import assert from "node:assert/strict";
import { test } from "node:test";
import type { Data } from "../src/data.ts";
import { CHAT_READS, type ChatRead } from "../src/db/chat-reads.ts";
import { observe } from "../src/reactive.ts";
import { holdLanguage } from "../src/i18n.ts";
import { held } from "./real-size-asked.ts";
import { UP } from "./real-size.ts";
import { run } from "./run.ts";
import { setup } from "./views-rig.ts";

holdLanguage();

// deno-lint-ignore no-explicit-any
type J = any;

/// How many of the writes told each read though its answer stayed the same, by declaration. Only falls. Where they come
/// from: a station's read (`by`) cannot know where in its answer a row is, so one whose order or whether it is in it
/// changed tells it though it stays below the first rows (the window: 30 of 420; the archive: 60 of 300), and what puts a
/// row in it is said for every parameter while the parameters filter by some (`mine`, `watching`, those apart); `thread`:
/// two chats of one thread in the fixture, the first found as the other is written; a row whose place alone changed
/// (another order) tells those keyed by it.
const TOLD_SAME: Record<string, number> = {
  row: 2,
  session: 2,
  thread: 154,
  named: 2,
  agent: 2,
  overlaid: 28,
  window: 59,
  counts: 54,
  atWork: 16,
  marked: 2,
  archived: 82,
  archivedCount: 10,
};

/// A write: what it is, the row it writes as it is before it (what each read is asked by), and the write itself.
type Write = { what: string; station: string; record: () => J; apply: (data: Data) => void };

const DAY = 86_400_000;

/// What each declaration is asked with around a write to `row` (its station, its keys): as a list asks it, and as a list
/// of the viewer's own over every visibility with the row read apart.
function asked(row: J, station: string, archived: boolean): J[] {
  const keyed = {
    station,
    stations: UP,
    id: String(row.id),
    session: typeof row.session === "string" ? row.session : "none",
    thread: typeof row.thread === "number" ? row.thread : -1,
    key: typeof row.clientKey === "string" ? row.clientKey : "none",
    limit: 30,
    archived,
    from: (typeof row.lastActiveAt === "number" ? row.lastActiveAt : 0) - DAY,
    to: (typeof row.lastActiveAt === "number" ? row.lastActiveAt : 0) + DAY,
    offset: 0,
    day: DAY,
  };
  return [
    { ...keyed, mine: false, hidden: 0, watching: false, threads: [], sessions: [] },
    {
      ...keyed,
      mine: true,
      hidden: 2,
      watching: false,
      threads: typeof row.thread === "number" ? [`${station}\u0001${row.thread}`] : [],
      sessions: typeof row.session === "string" ? [`${station}\u0001${row.session}`] : [],
    },
  ];
}

/// The changes of one field of a record, each of the record as it is when it is written: turned, raised, taken away,
/// put where it was not; an agent's process and its watch.
function changesOf(record: J, now: number): [string, (r: J) => J][] {
  const out: [string, (r: J) => J][] = [];
  for (const field of new Set([...Object.keys(record), "hidden", "pinned", "mine", "title", "lastActiveAt"])) {
    if (field === "id" || field === "agents") continue;
    const v = record[field];
    if (typeof v === "boolean") out.push([`${field} turned`, (r) => ({ ...r, [field]: !r[field] })]);
    else if (typeof v === "number") out.push([`${field} raised`, (r) => ({ ...r, [field]: (typeof r[field] === "number" ? r[field] : now) + 60_000 })]);
    else if (typeof v === "string") out.push([`${field} another`, (r) => ({ ...r, [field]: `${String(r[field] ?? "")}·` })]);
    if (v !== undefined && v !== null) out.push([`${field} taken away`, (r) => ({ ...r, [field]: null })]);
    out.push([`${field} put`, (r) => ({ ...r, [field]: field === "title" ? "新的名字" : field === "hidden" || field === "mine" ? true : typeof v === "object" && v !== null ? v : now })]);
  }
  if (Array.isArray(record.agents) && record.agents.length > 0) {
    const agent = (r: J, f: (a: J) => J) => ({ ...r, agents: [f(r.agents[0]), ...r.agents.slice(1)] });
    out.push(["an agent's process", (r) => agent(r, (a) => ({ ...a, process: a.process === "running" ? "cold" : "running" }))]);
    out.push(["an agent's watch", (r) => agent(r, (a) => ({ ...a, watch: a.watch ? null : { names: ["盯着"] } }))]);
  }
  return out;
}

const textOf = (found: J[]): string => JSON.stringify(found);

test("a_write_that_changes_a_declared_reads_answer_tells_it_and_one_that_does_not_is_counted", async () => {
  const { t: h } = await held(false);
  h.store.runner.shutdown();
  const t = setup({ host: h.host });
  const reads = Object.entries(CHAT_READS) as [string, ChatRead<J>][];
  // (each told by a name of its own: one another shares is told by what tells that one)
  assert.equal(new Set(reads.map(([, r]) => r.name)).size, reads.length, "every declared read's name is its own");
  const toldSame: Record<string, number> = Object.fromEntries(reads.map(([name]) => [name, 0]));
  const stale: string[] = [];
  const db = t.data.of(UP[0])!;
  const rowsOf = (station: string, kind: "chatRows" | "archivedRows"): J[] => t.data.shared({ topic: kind, station }) as J[];
  // (as each declaration's statement gives it now, and its records as they are now)
  const fresh = (read: ChatRead<J>, p: J) => textOf(read.records ? db.chatFound(read, p).map((f) => [f.station, f.archived, f.id, f.cols, f.record]) : db.chatCounted(read, p));
  const viewed = (read: ChatRead<J>, p: J) => textOf(read.records ? t.data.chatFound(read, p).map((f) => [f.station, f.archived, f.id, f.cols, f.record]) : t.data.chatCounted(read, p));
  try {
    const now = t.host.nowMs();
    const station = UP[0];
    const writes: Write[] = [];
    const listed = rowsOf(station, "chatRows");
    const archivedRows = rowsOf(station, "archivedRows");
    // The rows written: the first of the list, one in its window, one far below it, one archived.
    // (each listed row as it is now: written one change after another)
    const now0 = (id: string) => t.data.chat(station, id) as J;
    const archivedNow = (id: string) => rowsOf(station, "archivedRows").find((r) => r.id === id);
    for (const [which, row] of [["the first", listed[0]], ["in the window", listed[12]], ["far below", listed[listed.length - 1]]] as const) {
      const id = String(row.id);
      for (const [what, change] of changesOf(row, now)) writes.push({ what: `${which}: ${what}`, station, record: () => now0(id), apply: (d) => d.putChat(station, change(now0(id))) });
    }
    const arch = archivedRows[3];
    for (const [what, change] of changesOf(arch, now)) {
      writes.push({ what: `archived: ${what}`, station, record: () => archivedNow(arch.id), apply: (d) => d.set({ topic: "archivedRows", station }, rowsOf(station, "archivedRows").map((r) => (r.id === arch.id ? change(r) : r))) });
    }
    const fresh0 = listed[5];
    writes.push({ what: "a new chat put", station, record: () => ({ ...fresh0, id: "k-told-new", session: "k-told-new", thread: 987654, lastActiveAt: now }), apply: (d) => d.putChat(station, { ...fresh0, id: "k-told-new", session: "k-told-new", thread: 987654, lastActiveAt: now }) });
    writes.push({ what: "a chat dropped", station, record: () => listed[7], apply: (d) => d.dropChat(station, String(listed[7].id)) });
    writes.push({
      what: "a chat archived",
      station,
      record: () => listed[9],
      apply: (d) => {
        const row = listed[9];
        d.set({ topic: "chatRows", station }, rowsOf(station, "chatRows").filter((r) => r.id !== row.id));
        d.set({ topic: "archivedRows", station }, [{ ...row, archived: { at: now } }, ...rowsOf(station, "archivedRows")]);
      },
    });
    writes.push({ what: "a station's rows in another order", station, record: () => listed[2], apply: (d) => d.set({ topic: "chatRows", station }, [...rowsOf(station, "chatRows")].reverse()) });

    for (const write of writes) {
      const params = asked(write.record(), write.station, write.what.startsWith("archived"));
      const watched: { name: string; read: ChatRead<J>; p: J; told: boolean; before: string; stop: () => void }[] = [];
      for (const [name, read] of reads) {
        for (const p of params) {
          const w = { name, read, p, told: false, before: fresh(read, p), stop: () => {} };
          let view = "";
          w.stop = observe(() => void (view = viewed(read, p)), () => void (w.told = true));
          if (view !== w.before) stale.push(`${name} before "${write.what}": a view read ${view.slice(0, 160)}, its statement gives ${w.before.slice(0, 160)}`);
          watched.push(w);
        }
      }
      write.apply(t.data);
      await run(t.data.written);
      for (const w of watched) {
        w.stop();
        const after = fresh(w.read, w.p);
        if (after !== w.before && !w.told) stale.push(`${w.name} not told by "${write.what}" (${JSON.stringify(w.p).slice(0, 120)}): ${w.before.slice(0, 200)} → ${after.slice(0, 200)}`);
        if (after === w.before && w.told) {
          toldSame[w.name]++;
          if (process.env.CHAT_TOLD_PRINT) console.log(`told, the same: ${w.name} by "${write.what}" (${w.p.mine ? "the viewer's own, read apart" : "all"})`);
        }
      }
    }
    if (process.env.CHAT_TOLD_PRINT) console.log(`writes ${writes.length}\nconst TOLD_SAME: Record<string, number> = ${JSON.stringify(Object.fromEntries(Object.entries(toldSame).filter(([, n]) => n > 0)))};`);
    assert.deepEqual(stale, [], "a write that changed an answer told it, and what a view reads is what its statement gives");
    const off = reads.map(([name]) => name).filter((name) => toldSame[name] !== (TOLD_SAME[name] ?? 0)).map((name) => `${name}: told ${toldSame[name]} times with its answer the same, TOLD_SAME says ${TOLD_SAME[name] ?? 0}${toldSame[name] < (TOLD_SAME[name] ?? 0) ? " (it fell: write it)" : ""}`);
    assert.deepEqual(off, []);
  } finally {
    t.store.runner.shutdown();
  }
});
