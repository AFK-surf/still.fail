// What the views, the store and what goes out walk in memory as something changes follows what changed, not how much is
// shown or held (the owner's rule, as topic-work.test.ts holds it of the database's reads): counted in work.ts `walked`
// (reads tracked, values made again, `share`'s and `equal`'s walks, a keyed list's diff, the items put together, copied
// and put through their shapes as they go out), each counted to the topic made or sent then (work.ts `walking`).
//
// Each cause of real-size-asked.ts `CAUSES` (again with the chat's six pages loaded where it says `long`), one after
// another in its order on one rig `held` (every way the app asks held, at rest), from its run to the core at rest, as
// topic-work.test.ts measures them `held`; three times, each in a worker thread of its own:
// - as the rig is;
// - with what is shown three times as large (`SHOWN`): the chats' lists' windows (`WINDOWS`), the chat's messages held
//   (its last page, or its six), and every other way of asking whose size its params say (a `limit`, a job log's `lines`,
//   usage's `days`), what a page asks more of as it is scrolled or opened wider;
// - with the workspace's chats three times (real-size.ts `Size`).
// Held: no counter of any cause grows with what is shown three times as large, nor with three times the chats, but the
// pairs (cause, counter) in `OVER_SHOWN` and `OVER_CHATS`, each of which must still grow. They only fall, as a set of
// pairs: by how much one grows is not held (a field more in a row moves what `fit`, `share` and `equal` count, and is
// no other change's to answer for here). On failure, and with VIEW_WORK_PRINT=1, the tables as they would be (to
// paste), each pair's numbers and the topic whose walking grew most; and what each of `SHOWN_WHOLE`'s causes walks as
// the rig is, by topic, with what each topic sent and whether it was made again.
// `same` (items found the very objects they were, one comparison of two references each) is not held: it is one an
// item of what is shown, the rest of the walk only for what is not the same. Its growth is printed beside.
import assert from "node:assert/strict";
import { test } from "node:test";
import { Worker, isMainThread, parentPort, workerData } from "node:worker_threads";
import type { Walked } from "../src/work.ts";

// deno-lint-ignore no-explicit-any
type J = any;

const print = process.env.VIEW_WORK_PRINT === "1";
/// How much larger what is shown is in the second measure.
const SHOWN = 3;
/// The causes whose walking is printed whole, by topic.
const SHOWN_WHOLE = ["quota", "session", "member", "message", "job", "card", "line", "agent"];

/// What went out to a topic's subscribers (the first subscription of each way of asking): messages, their ops (a value
/// sent whole is one) and bytes.
type Sent = { messages: number; ops: number; bytes: number };
/// What a cause walked: the totals, each topic's (`""`: no topic's, the sync's own), and what each topic sent.
type Cost = { total: Walked; by: Record<string, Walked>; sent: Record<string, Sent>; error?: string };
type Found = Record<string, Cost>;
type Over = Record<string, (keyof Walked)[]>;

/// The causes whose walking grows with what is shown three times as large, and which of their counters grow.
const OVER_SHOWN: Over = {
  "quota": ["reads", "shared", "equaled", "copied", "fitted"],
  "message": ["reads", "shared", "equaled"],
  "agent": ["reads", "shared", "diffed", "copied", "fitted"],
  "line": ["diffed", "fitted"],
  "thing": ["reads", "shared", "equaled"],
  "card": ["reads", "shared", "equaled", "diffed", "fitted"],
  "archived": ["reads", "shared", "built", "fitted"],
  "renamed": ["reads", "shared", "diffed"],
  // (grown's shared joined as share came to take a source's own objects handed again by a lookup: 206 and 202 before, of
  // every row equal to the one kept and not it; 88 and 92 now, of the days the rows the window grew by go into)
  "grown": ["reads", "shared"],
  "down": ["reads", "shared", "equaled", "diffed", "built", "copied", "fitted"],
  "job": ["reads", "shared", "equaled"],
  "usage": ["shared", "copied", "fitted"],
  "screen": ["reads", "shared", "equaled"],
  "member": ["reads", "shared", "equaled"],
  "session": ["reads", "shared", "equaled", "copied", "fitted"],
  "decided": ["reads", "shared", "equaled"],
  "updating": ["reads", "shared", "equaled"],
  "machine": ["reads", "shared", "equaled", "copied", "fitted"],
  "login": ["shared"],
  "release": ["reads", "shared"],
  "quota six pages": ["shared", "equaled"],
  "message six pages": ["reads", "shared", "equaled"],
};
/// The same with the workspace's chats three times.
const OVER_CHATS: Over = {
  "quota": ["shared", "equaled", "copied", "fitted"],
  "message": ["reads", "shared", "copied", "fitted"],
  "agent": ["shared", "copied", "fitted"],
  "thing": ["reads", "shared", "copied", "fitted"],
  "card": ["reads", "shared", "copied", "fitted"],
  // (grown's built and fitted joined as the rows that are the objects they were came to be taken by one comparison:
  // they were the whole window's before, alike at every size; now they are the rows the window grew by and the days
  // those went into, two with three times the chats where one is as the rig is)
  "grown": ["reads", "built", "fitted"],
  "down": ["shared", "equaled", "copied", "fitted"],
  "job": ["shared", "copied", "fitted"],
  "usage": ["shared", "copied", "fitted"],
  "screen": ["shared", "equaled", "copied", "fitted"],
  "member": ["reads", "shared", "equaled"],
  "session": ["shared", "equaled", "copied", "fitted"],
  "decided": ["shared", "equaled"],
  "updating": ["shared", "equaled", "copied", "fitted"],
  "machine": ["shared", "equaled", "fitted"],
  "login": ["shared"],
  "archiving": ["shared"],
  "off": ["shared"],
  "quota six pages": ["shared"],
  "message six pages": ["shared", "copied", "fitted"],
};

// ── measuring, in a worker thread a setting ──

async function measure(shown: number): Promise<Found> {
  const { holdLanguage } = await import("../src/i18n.ts");
  const { walked, walkingBy } = await import("../src/work.ts");
  const asked = await import("./real-size-asked.ts");
  const size = await import("./real-size.ts");
  holdLanguage();
  if (shown !== 1) {
    for (const name of Object.keys(asked.WINDOWS)) asked.WINDOWS[name] = asked.WINDOWS[name]! * shown;
    size.JOB_LOG_LINES.forEach((n, i) => (size.JOB_LOG_LINES[i] = n * shown));
    for (const a of Object.values(asked.ASKED)) {
      if (typeof a.limit === "number") a.limit = a.limit * shown;
      if (a.topic === "jobLog" && typeof a.lines === "number") a.lines = a.lines * shown;
      if (a.topic === "usage" && typeof a.days === "number") a.days = a.days * shown;
    }
  }
  const snap = (): Walked => ({ ...walked });
  const enc = new TextEncoder();
  /// What went out meanwhile, by topic, of the first subscription of each way of asking (`names`, by id).
  const took = (h: J, sent: Record<string, Sent>): number => {
    const ms = h.t.host.takeEmitted();
    for (const [, m] of ms) {
      const name = typeof m?.id === "number" && m.id <= asked.AGAIN ? h.names[m.id - 1] : undefined;
      if (name === undefined) continue;
      const topic = String(asked.ASKED[name]!.topic);
      const s = (sent[topic] ??= { messages: 0, ops: 0, bytes: 0 });
      s.messages++;
      s.ops += Array.isArray(m.delta) ? m.delta.length : 1;
      s.bytes += enc.encode(JSON.stringify(m)).length;
    }
    return ms.length;
  };
  /// The clock run on till the core is at rest: nothing goes out and nothing is read a settle long.
  const rest = async (h: J, sent: Record<string, Sent>) => {
    for (let i = 0; i < 100; i++) {
      const before = walked.reads + walked.recomputes;
      await h.t.host.settle();
      if (took(h, sent) === 0 && walked.reads + walked.recomputes === before) return;
    }
    throw new Error("the core did not come to rest");
  };
  const out: Found = {};
  for (const long of [false, true]) {
    const causes = Object.entries(asked.CAUSES).filter(([, c]) => (long ? c.long === true : true));
    const h = await asked.held(long);
    if (shown !== 1) {
      // (the chat's messages held three times as many: its page shows them)
      const n = h.chat * shown;
      for (const [topic, value] of size.fixture(h.base, n)) {
        if (topic.topic === "thread" && topic.station === size.CHAT.station && topic.thread === size.CHAT.thread) h.t.set(topic, value);
      }
      (h as { chat: number }).chat = n;
    }
    await rest(h, {});
    for (const [cause, c] of causes) {
      const from = snap();
      const sent: Record<string, Sent> = {};
      const by = new Map<string, Walked>();
      walkingBy(by);
      let error: string | undefined;
      try {
        c.run(h);
        for (let t = 0; t < (c.ms ?? 1000); t += 100) {
          await h.t.host.time.pass(100);
          took(h, sent);
        }
        await rest(h, sent);
      } catch (e) {
        error = String((e as Error)?.stack ?? e);
      }
      walkingBy(null);
      const total = snap();
      for (const k of Object.keys(total) as (keyof Walked)[]) total[k] -= from[k];
      out[long ? `${cause} six pages` : cause] = { total, by: Object.fromEntries(by), sent, ...(error !== undefined ? { error } : {}) };
    }
    h.t.store.runner.shutdown();
  }
  return out;
}

if (!isMainThread && (workerData as J)?.viewWork === true) {
  measure((workerData as J).shown).then((f) => parentPort!.postMessage(f), (e) => parentPort!.postMessage({ error: String(e?.stack ?? e) }));
}

function measured(shown: number, realSize: Record<string, number>): Promise<Found> {
  return new Promise((resolve, reject) => {
    const w = new Worker(new URL(import.meta.url), { workerData: { viewWork: true, shown, realSize } });
    w.once("message", (m) => {
      void w.terminate();
      const e = (m as { error?: string }).error;
      if (e !== undefined) reject(new Error(e));
      else resolve(m as Found);
    });
    w.once("error", reject);
  });
}

// ── holding ──

type Grown = { cause: string; k: keyof Walked; was: number; now: number; topic: string };

/// Of `a` and `b` (as the rig is, and the other setting), each cause and counter that grew (of `same` alone, or of the
/// others), with the topic whose own count grew most.
function grown(a: Found, b: Found, same: boolean): Grown[] {
  const out: Grown[] = [];
  for (const cause of Object.keys(a)) {
    for (const k of Object.keys(a[cause]!.total) as (keyof Walked)[]) {
      if ((k === "same") !== same) continue;
      const was = a[cause]!.total[k];
      const now = b[cause]!.total[k];
      if (now <= was) continue;
      let topic = "";
      let most = -Infinity;
      for (const t of new Set([...Object.keys(a[cause]!.by), ...Object.keys(b[cause]!.by)])) {
        const d = (b[cause]!.by[t]?.[k] ?? 0) - (a[cause]!.by[t]?.[k] ?? 0);
        if (d > most) [most, topic] = [d, t];
      }
      out.push({ cause, k, was, now, topic: `${topic === "" ? "(no topic)" : topic} +${most}` });
    }
  }
  return out;
}

/// Holds `found` to `over` (failures into `fail`); the table as it would be, and each pair's numbers.
function holding(name: string, over: Over, found: Grown[], causes: string[], counters: number, fail: string[]): string {
  const at = new Set(found.map((g) => `${g.cause}\u0001${g.k}`));
  for (const g of found) {
    if (!(over[g.cause] ?? []).includes(g.k)) fail.push(`${name}: ${g.cause} ${g.k} grows, ${g.was} -> ${g.now} (most: ${g.topic})`);
  }
  for (const [cause, ks] of Object.entries(over)) {
    for (const k of ks) if (!at.has(`${cause}\u0001${k}`)) fail.push(`${name}: ${cause} ${k} no longer grows: take it out`);
  }
  // (as it would be, in the causes' order)
  const lines = causes.flatMap((cause) => {
    const gs = found.filter((g) => g.cause === cause);
    return gs.length === 0 ? [] : [`  ${JSON.stringify(cause)}: [${gs.map((g) => JSON.stringify(g.k)).join(", ")}],`];
  });
  const numbers = found.map((g) => `//   ${g.cause} ${g.k}: ${g.was} -> ${g.now} (most: ${g.topic})`);
  const ranked = [...found.reduce((m, g) => m.set(g.topic.split(" +")[0]!, (m.get(g.topic.split(" +")[0]!) ?? 0) + 1), new Map<string, number>())].sort((x, y) => y[1] - x[1]);
  return [`const ${name}: Over = {`, ...lines, "};", `// ${found.length} over, ${causes.length * counters - found.length} within; the topic that grew most, by pairs: ${ranked.map(([t, n]) => `${t} ${n}`).join(", ")}`, ...numbers].join("\n");
}

/// What `cause` walked as the rig is, by topic: the walks, ranked by their sum, the first six and the rest summed, and
/// all of them; of each, what was found the same object (not in the sum), what it sent and whether it was made again.
const WALKS = ["reads", "shared", "equaled", "diffed", "built", "copied", "fitted"] as const;
function whole(cause: string, c: Cost): string {
  const sum = (w: Walked) => WALKS.reduce((n, k) => n + w[k], 0);
  const topics = Object.entries(c.by).sort((x, y) => sum(y[1]) - sum(x[1]) || (x[0] < y[0] ? -1 : 1));
  const row = (name: string, w: Walked, sent: Sent | undefined, again: string) =>
    `| ${name} | ${WALKS.map((k) => w[k]).join(" | ")} | ${sum(w)} | ${w.same} | ${sent === undefined ? "0" : `${sent.messages} msg, ${sent.ops} ops, ${sent.bytes} B`} | ${again} |`;
  const rest = topics.slice(6);
  const restW = rest.reduce((acc, [, w]) => {
    for (const k of Object.keys(acc) as (keyof Walked)[]) acc[k] += w[k];
    return acc;
  }, { reads: 0, recomputes: 0, shared: 0, equaled: 0, diffed: 0, built: 0, copied: 0, fitted: 0, same: 0 } as Walked);
  const restSent = rest.reduce((n, [t]) => n + (c.sent[t]?.bytes ?? 0), 0);
  return [
    `### ${cause}`,
    `| topic | ${WALKS.join(" | ")} | sum | same | sent | made again |`,
    `|---|${WALKS.map(() => "---").join("|")}|---|---|---|---|`,
    ...topics.slice(0, 6).map(([t, w]) => row(t === "" ? "(no topic)" : t, w, c.sent[t], w.recomputes > 0 ? `yes (${w.recomputes})` : "no")),
    ...(rest.length > 0 ? [`| the other ${rest.length} | ${WALKS.map((k) => restW[k]).join(" | ")} | ${sum(restW)} | ${restW.same} | ${restSent} B | ${restW.recomputes} |`] : []),
    row("all", c.total, undefined, `${c.total.recomputes}`),
  ].join("\n");
}

// (registered in the main thread alone: the workers load this file to measure)
if (isMainThread) test("what_one_change_walks_follows_what_changed_not_what_is_shown_or_held", { timeout: 600_000 }, async () => {
  const [base, shown, chats] = await Promise.all([measured(1, {}), measured(SHOWN, {}), measured(1, { chats: 3 })]);
  const causes = Object.keys(base);
  const errors = [base, shown, chats].flatMap((f) => Object.entries(f).flatMap(([c, x]) => (x.error !== undefined ? [`${c}: ${x.error}`] : [])));
  assert.deepEqual(errors, [], "every cause ran");
  // (all but `same`, which is printed and not held)
  const counters = Object.keys(base[causes[0]!]!.total).length - 1;
  const fail: string[] = [];
  const tables = [holding("OVER_SHOWN", OVER_SHOWN, grown(base, shown, false), causes, counters, fail), holding("OVER_CHATS", OVER_CHATS, grown(base, chats, false), causes, counters, fail)].join("\n");
  if (print || fail.length > 0) console.log(tables);
  if (print) {
    for (const [name, other] of [["shown", shown], ["chats", chats]] as const) {
      console.log(grown(base, other, true).map((g) => `// same (not held), ${name}: ${g.cause} ${g.was} -> ${g.now} (most: ${g.topic})`).join("\n"));
    }
  }
  if (print) for (const c of SHOWN_WHOLE) console.log(whole(c, base[c]!));
  assert.deepEqual(fail, []);
});
