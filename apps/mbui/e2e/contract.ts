// The core's contract: what the kept conversations (e2e/traces/*.trace, the tapes the Tester's flows are given again:
// src/sfreplay) say the core answers, a real core answers now. Each tape's asks, in its order, are put to ember's TS
// core (client/core-ts hosts/node.ts) signed in to the local still.fail scripts/e2e-local.sh started (as alice, the
// tapes' person), and each answer is compared with the tape's (the rules below). A difference fails, naming the ask
// and the place in its answer, and says how to record the tape again: then the tapes the Tester runs on are what the
// core does now, not what it did once.
//
//   node e2e/contract.ts [NAME…]     every tape (in the order they were recorded: the world they made goes on from one
//                                    to the next, as in the run) or those named; e2e/contract.sh runs it
//   node e2e/contract.ts --runs      the tapes by the run they were recorded in, a line each (a run's tapes are put to
//                                    a still.fail of their own: e2e/contract.sh starts one for each line)
//
// E2E_EMBER (this checkout), E2E_ORIGIN (the local cloud), E2E_CORE_DATA (a directory of its own: the cores' data),
// E2E_STATION (the test station's directory: its home is where the drive's tapes' folders are), E2E_SEED (a command
// run with a tape's world: `drive TAG [FILE…]`, the drive folder of that tag with those files put in it; `peer ARGS`,
// alice's other device doing so). The tapes of one recorded run share a core's data, restarted for each as the app
// was; signed in once, as the run's first flow was.
//
// What is compared, and how (the rules a tape's answers are normalized by):
// - Ids made anew each run (a workspace's, a station's, a chat's, a notice's, a ULID, a 64-hex key, a thread's number,
//   a path the station made) are learned: where the tape's answer has one, the live answer at the same place has
//   its own, and the tape's later asks are put with the live ones. An ask is put once every answer it came after in
//   the tape has come (by name: its id's first answer, never a time), and once it holds no id not learned yet.
// - Time is left out: numbers and words at time's keys (TIME_KEYS: when something was, how long ago, "8 分钟前"),
//   and the machine's own (MACHINE_KEYS, MACHINE_PATHS: its name, CPU, load, memory, disk, version, relay port, where
//   the station is installed). Of an error, the core's own words, not what the host said of it (a fetch's failure
//   is each host's: the app's core runs on the Rust shell, this one on Node). And what is the run's timing alone
//   (TIMING_PATHS: whether the mesh has met the station yet).
// - Each answer is then the same: a call's (ok, or the error); of a subscription's values, one is the tape's last
//   (waited for by the value, never by a time: the deadline only fails it; how many pushes it took is the station's
//   timing). The same: no key the tape has that the live answer lacks, or the other way, no value of another type,
//   no list of another length, no other words.
import { mkdirSync, readFileSync, readdirSync, rmSync } from "node:fs";
import { join, dirname } from "node:path";
import { pathToFileURL, fileURLToPath } from "node:url";
import { execFileSync } from "node:child_process";

type J = any;
const HERE = dirname(fileURLToPath(import.meta.url));
const ember = process.env.E2E_EMBER!;
const origin = process.env.E2E_ORIGIN!;
const work = process.env.E2E_CORE_DATA!;
const stationDir = process.env.E2E_STATION!;
const seed = process.env.E2E_SEED;
/// How long a tape's answer may take to come before the contract fails on it: a deadline, never what is waited for.
const DEADLINE_MS = Number(process.env.E2E_CONTRACT_MS ?? 90_000);

// (not for --runs, which needs no core)
const listing = process.argv.includes("--runs");
const { start } = listing ? { start: null } : await import(pathToFileURL(join(ember, "client/core-ts/src/hosts/node.ts")).href);
const { applyKeyed } = listing ? { applyKeyed: null } : await import(pathToFileURL(join(ember, "client/core-ts/src/collections.ts")).href);

// ---- the rules

/// Keys whose values are times (left out).
const TIME_KEYS = /^(at|ts|w|set|changed|mtime|ago|full|until|when|since|time|timeText|threadTs|lastSeen|last_seen|.*_at|.*At|.*Ms)$/;
/// Keys whose values are the machine's own (left out).
const MACHINE_KEYS = /^(host|hostname|cpuModel|arch|os|version|latest|relay_url|origin|freeBytes|totalBytes|usedBytes|swapUsedBytes|emberRssBytes|load|cpuBusy|uptimeSec|runtimeSessionId|processText|processesText|code|device|clientKey|identity|loginCommand|machineLogins)$/;
/// Places whose values are the machine's, by their path: where the station's parts are installed.
const MACHINE_PATHS = [/\.overview\.updates\[\d+\]\.note$/];
/// Places whose values are the run's timing, by topic and path: whether the mesh has met a station yet (its row's
/// words, "正在连接" until then).
const TIMING_PATHS: Record<string, RegExp[]> = { stations: [/^\[\d+\]\.(summary|line)$/] };
/// Ids made anew each run, found in words: learned from the live answers, put in the tape's asks.
const TOKENS: [string, RegExp][] = [
  ["key", /\b[0-9a-f]{64}\b/g],
  ["ulid", /\b[0-9A-HJKMNP-TV-Z]{26}\b/g],
  ["chat", /\bc-[0-9a-f]{10}\b/g],
  ["notice", /\bn-[0-9a-f]{18}\b/g],
  ["upload", /\b\d{4}-\d\d-\d\dT\d\d-\d\d-\d\d-[0-9a-f]{6}\b/g],
  ["outgoing", /\bout-[0-9a-f]{18}\b/g],
  ["uuid", /\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/g],
];
/// Keys whose numbers are ids made anew (learned as words are).
const NUMBER_IDS = new Set(["thread"]);

// ---- a tape

type Ev = { out: true; msg: J } | { out: false; id: number; msg: J; bytes: boolean };
type Tape = { name: string; evs: Ev[]; first: number; tag: string | null; home: string | null; run: string };

function readTape(name: string): Tape {
  const text = readFileSync(join(HERE, "traces", `${name}.trace`), "utf8");
  const evs: Ev[] = [];
  let first = Infinity;
  for (const line of text.split("\n")) {
    if (!line.trim()) continue;
    const e = JSON.parse(line);
    if (e.out) evs.push({ out: true, msg: e.out });
    else if (e.in) {
      evs.push({ out: false, id: e.in.id, msg: e.in, bytes: typeof e.b === "string" });
      if (typeof e.w === "number") first = Math.min(first, e.w);
    }
  }
  // the station's home the tape's run had (its drive folder's path: …/home/e2e-TAG)
  const m = /"(\/[^"]*?)\/home\/e2e-(\d{6})/.exec(text);
  // the run it was recorded in (its workspace's id): the tapes of one run share a core's data, as the run's app did
  const run = /[0-9A-HJKMNP-TV-Z]{26}/.exec(evs.filter((e) => e.out).map((e) => JSON.stringify(e.msg)).join("\n"))?.[0] ?? name;
  return { name, evs, first, tag: m ? m[2] : null, home: m ? m[1] : null, run };
}

/// What the tape's world needs before it is put (a run's earlier flows' doings that no tape has): the drive folder of
/// its tag, and what 18-drive-upload put in it, for the drive's tapes after it.
function world(t: Tape): string[][] {
  // 02-home-new-chat, before the chat's tapes: a chat made on alice's other device, answered there
  if (t.name === "send-text") {
    const tag = /另一台设备新建的对话 (\d{6})/.exec(JSON.stringify(t.evs))?.[1];
    if (tag) return [["peer", "create", `另一台设备新建的对话 ${tag} post:新对话里的回复 ${tag}`]];
  }
  if (!t.tag) return [];
  if (t.name === "drive-lend" || t.name === "drive-list") return [["drive", t.tag]];
  if (t.name === "drive-read") return [];
  if (t.name === "drive-rename") return [["drive", t.tag, "e2e-photo.jpg", "e2e-data.bin"]];
  // 91-drive-download-many's folder, after drive-delete took the photo
  if (t.name === "station-file-sent") return [["drive-big", t.tag]];
  return [];
}

// ---- the live core

type Live = { msgs: J[]; values: J[]; bytes: boolean[] };

/// The core of each recorded run's data: one for all its tapes, each tape a client of its own (as each of the run's
/// flows was the app started again). Not closed and started again between them: closing lets go of what it had not
/// written yet (a reading place, put on the device a moment after it is told), which an app that keeps running keeps.
const cores = new Map<string, { core: J; to: Map<number, (m: J, bytes?: Uint8Array) => void> }>();
function coreOf(dir: string) {
  let c = cores.get(dir);
  if (!c) {
    const to = new Map<number, (m: J, bytes?: Uint8Array) => void>();
    const core = start(dir, origin, (client: number, json: string, bytes?: Uint8Array) => {
      const m = JSON.parse(json);
      if (m.fatal) {
        console.error("core fatal:", m.fatal);
        process.exit(3);
      }
      to.get(client)?.(m, bytes);
    });
    c = { core, to };
    cores.set(dir, c);
  }
  return c;
}

class Run {
  core: J;
  client: number;
  live = new Map<number, Live>();
  map = new Map<string, string>();
  numbers = new Map<string, Map<number, number>>();
  prefix: [string, string] | null = null;
  changed: () => void = () => {};
  /// A client of its own of the run's core (`cores`: one a recorded run, its data kept from tape to tape).
  constructor(dir: string) {
    const c = coreOf(dir);
    this.core = c.core;
    this.client = this.core.connect();
    c.to.set(this.client, (m: J, bytes?: Uint8Array) => {
      if (typeof m.id !== "number") return;
      const l = this.live.get(m.id) ?? { msgs: [], values: [], bytes: [] };
      this.live.set(m.id, l);
      l.msgs.push(m);
      l.bytes.push(!!bytes && bytes.length > 0);
      const prev = l.values.length > 0 ? l.values[l.values.length - 1] : undefined;
      l.values.push("value" in m ? m.value : "delta" in m ? applyKeyed(prev, m.delta) : m);
      this.changed();
    });
  }
  send(msg: J) {
    this.core.receive(this.client, JSON.stringify(msg));
  }
  /// Until `ok` holds (asked again as each message comes), or the deadline fails it with `what`.
  until(what: () => string, ok: () => boolean): Promise<void> {
    if (ok()) return Promise.resolve();
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.changed = () => {};
        reject(new Error(what()));
      }, DEADLINE_MS);
      this.changed = () => {
        if (ok()) {
          clearTimeout(timer);
          this.changed = () => {};
          resolve();
        }
      };
    });
  }
}

// ---- learning the ids

function tokens(s: string): [string, string][] {
  const out: [string, number, string][] = [];
  for (const [kind, re] of TOKENS) for (const m of s.matchAll(re)) out.push([kind, m.index!, m[0]]);
  // a key's 64 hex holds no ULID; the rest do not overlap
  out.sort((a, b) => a[1] - b[1]);
  return out.map(([k, , v]) => [k, v]);
}

/// The tape's words in the live run's terms: its station's directory, then each id learned.
function translate(r: Run, s: string): string {
  if (r.prefix && s.startsWith(r.prefix[0])) s = r.prefix[1] + s.slice(r.prefix[0].length);
  for (const [, v] of tokens(s)) {
    const live = r.map.get(v);
    if (live) s = s.split(v).join(live);
  }
  return s;
}

/// Ids in `s` not learned yet.
function unknown(r: Run, s: string): string[] {
  return tokens(s).filter(([, v]) => !r.map.has(v)).map(([, v]) => v);
}

/// The leaves of a value that say what it is, for pairing a list's items (ids and time left out).
function marks(v: J, out: string[] = [], key = ""): string[] {
  if (Array.isArray(v)) for (const x of v) marks(x, out, key);
  else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) marks(x, out, k);
  else if (!TIME_KEYS.test(key) && !MACHINE_KEYS.test(key)) {
    const s = typeof v === "string" ? v.replace(/\d{6}/g, "") : String(v);
    if (typeof v !== "string" || tokens(v).length === 0) out.push(`${key}=${s}`);
  }
  return out;
}

function score(a: J, b: J): number {
  const bm = new Set(marks(b));
  let n = 0;
  for (const m of marks(a)) if (bm.has(m)) n++;
  return n;
}

/// A list's items paired, the tape's with the live answer's: each with the live one most like it (the same words),
/// else by place.
function pairs(rec: J[], live: J[]): [J, J][] {
  // the likest pairs first, over the whole list (a row of the tape's run that the live one lacks pairs with none)
  const all: [number, number, number][] = [];
  rec.forEach((a, i) => live.forEach((b, j) => all.push([score(a, b), i, j])));
  all.sort((x, y) => y[0] - x[0] || x[1] - y[1] || x[2] - y[2]);
  const ri = new Set<number>();
  const lj = new Set<number>();
  const out: [J, J][] = [];
  const most = all.length > 0 ? all[0][0] : 0;
  for (const [s, i, j] of all) {
    if (ri.has(i) || lj.has(j) || s === 0 || (rec.length > 1 && s < most / 2)) continue;
    ri.add(i);
    lj.add(j);
    out.push([rec[i], live[j]]);
  }
  // lists of one: by place
  if (out.length === 0 && rec.length === 1 && live.length === 1) out.push([rec[0], live[0]]);
  return out;
}

/// The ids the tape's answer `rec` has, learned from the live answer `live` at the same places.
function learn(r: Run, rec: J, live: J, key = "") {
  if (Array.isArray(rec) && Array.isArray(live)) {
    for (const [a, b] of pairs(rec, live)) learn(r, a, b, key);
  } else if (rec && live && typeof rec === "object" && typeof live === "object") {
    for (const k of Object.keys(rec)) {
      if (k in live) learn(r, rec[k], live[k], k);
      else {
        // a key that is an id (a workspace's marks by workspace): the live one the only other id key of its kind
        const kt = tokens(k);
        if (kt.length === 1 && !r.map.has(k)) {
          const others = Object.keys(live).filter((x) => !(x in rec) && tokens(x).length === 1 && tokens(x)[0][0] === kt[0][0]);
          if (others.length === 1) r.map.set(k, others[0]);
        }
      }
      const lk = r.map.get(k);
      if (lk && lk in live && !(k in live)) learn(r, rec[k], live[lk], k);
    }
  } else if (typeof rec === "string" && typeof live === "string") {
    const a = tokens(rec);
    const b = tokens(live);
    if (a.length === b.length) {
      a.forEach(([kind, v], i) => {
        if (b[i][0] === kind && !r.map.has(v)) r.map.set(v, b[i][1]);
      });
    }
    // a path the station made (an upload's place): the whole of it
    if (rec.startsWith("/") && live.startsWith("/") && !r.map.has(rec) && translate(r, rec) !== live) r.map.set(rec, live);
  } else if (typeof rec === "number" && typeof live === "number" && NUMBER_IDS.has(key)) {
    const m = r.numbers.get(key) ?? new Map();
    r.numbers.set(key, m);
    if (!m.has(rec)) m.set(rec, live);
  }
}

/// The tape's ask in the live run's terms.
function put(r: Run, v: J, key = ""): J {
  if (Array.isArray(v)) return v.map((x) => put(r, x, key));
  if (v && typeof v === "object") return Object.fromEntries(Object.entries(v).map(([k, x]) => [r.map.get(k) ?? translate(r, k), put(r, x, k)]));
  if (typeof v === "string") return r.map.get(v) ?? translate(r, v);
  if (typeof v === "number" && NUMBER_IDS.has(key)) return r.numbers.get(key)?.get(v) ?? v;
  return v;
}

function pending(r: Run, v: J, key = ""): string[] {
  if (Array.isArray(v)) return v.flatMap((x) => pending(r, x, key));
  if (v && typeof v === "object") return Object.entries(v).flatMap(([k, x]) => pending(r, x, k));
  if (typeof v === "string") return r.map.has(v) ? [] : unknown(r, v);
  if (typeof v === "number" && NUMBER_IDS.has(key) && !r.numbers.get(key)?.has(v)) return [`${key} ${v}`];
  return [];
}

// ---- comparing

/// The places the answer being compared leaves out for its topic (TIMING_PATHS).
let ignoring: RegExp[] = [];

/// Where the tape's answer and the live one differ (empty: the same), the tape's in the live run's terms.
function differ(r: Run, rec: J, live: J, path = "", key = "", out: string[] = []): string[] {
  if (TIME_KEYS.test(key) || MACHINE_KEYS.test(key) || MACHINE_PATHS.some((p) => p.test(path)) || ignoring.some((p) => p.test(path))) return out;
  const type = (v: J) => (v === null ? "null" : Array.isArray(v) ? "list" : typeof v);
  if (type(rec) !== type(live)) {
    out.push(`${path || "."}: the tape has ${type(rec)} ${short(rec)}, the core ${type(live)} ${short(live)}`);
  } else if (Array.isArray(rec)) {
    if (rec.length !== live.length) out.push(`${path || "."}: the tape has ${rec.length} items, the core ${live.length}`);
    else rec.forEach((x, i) => differ(r, x, live[i], `${path}[${i}]`, key, out));
  } else if (rec && typeof rec === "object") {
    const skip = (k: string, p: string) => TIME_KEYS.test(k) || MACHINE_KEYS.test(k) || MACHINE_PATHS.some((m) => m.test(p)) || ignoring.some((m) => m.test(p));
    // (a key may be an id: the tape's in the live run's terms)
    const keys = new Map(Object.keys(rec).map((k) => [r.map.get(k) ?? translate(r, k), k]));
    for (const [lk, k] of keys) {
      if (skip(k, `${path}.${k}`)) continue;
      if (!(lk in live)) out.push(`${path}.${k}: the tape has it, the core has not (${short(rec[k])})`);
      else differ(r, rec[k], live[lk], `${path}.${k}`, k, out);
    }
    for (const k of Object.keys(live)) if (!keys.has(k) && !skip(k, `${path}.${k}`)) out.push(`${path}.${k}: the core has it, the tape has not (${short(live[k])})`);
  } else if (typeof rec === "number" && NUMBER_IDS.has(key)) {
    if ((r.numbers.get(key)?.get(rec) ?? rec) !== live) out.push(`${path}: the tape has ${rec}, the core ${live}`);
  } else if (typeof rec === "string" && path.endsWith(".error.message")) {
    // an error's words: the core's own, up to what the host said of it (a fetch's failure is each host's own words)
    const own = (s: string) => s.split(/：|: /)[0];
    if (own(rec) !== own(live)) out.push(`${path}: the tape has ${short(rec)}, the core ${short(live)}`);
  } else if (typeof rec === "string") {
    const a = translate(r, r.map.get(rec) ?? rec);
    const strip = (s: string) => tokens(s).reduce((s, [k, v]) => s.split(v).join(`<${k}>`), s);
    if (a !== live && strip(a) !== strip(live)) out.push(`${path}: the tape has ${short(rec)}, the core ${short(live)}`);
  } else if (rec !== live) {
    out.push(`${path}: the tape has ${short(rec)}, the core ${short(live)}`);
  }
  return out;
}

function short(v: J): string {
  const s = JSON.stringify(v) ?? String(v);
  return s.length > 120 ? s.slice(0, 117) + "…" : s;
}

// ---- a tape put to the core

type Ask = { id: number; kind: "call" | "subscribe" | "other"; topic: string; what: string; answers: Ev[] };

function describe(msg: J): string {
  if (msg.call) return `call ${msg.call}`;
  if (msg.subscribe) return `subscribe ${JSON.stringify(msg.subscribe).slice(0, 80)}`;
  return JSON.stringify(msg).slice(0, 80);
}

const signedIn = new Set<string>();

async function play(t: Tape): Promise<string[]> {
  const dir = join(work, t.run);
  const fresh = !signedIn.has(t.run);
  if (fresh) {
    rmSync(dir, { recursive: true, force: true });
    mkdirSync(dir, { recursive: true });
  }
  for (const w of world(t)) if (seed) execFileSync(seed, w, { stdio: ["ignore", "ignore", "inherit"] });
  const r = new Run(dir);
  if (t.home) r.prefix = [t.home, stationDir];
  // signed in as the tape's run was before its first ask (the environment's account: the app's MBUI_CORE_ACCOUNT_B64),
  // and the system asked about notifications as the app does the first time it is signed in (sfapp notices.mbt)
  if (fresh) {
    const account = await (await fetch(`${origin}/__dev/account?user=alice`)).json();
    for (const [id, call, params] of [[1_000_000, "migrate", { accounts: [account] }], [1_000_001, "notify.set", { asked: true }]] as const) {
      r.send({ id, call, params });
      await r.until(() => `${t.name}: ${call} was not answered`, () => r.live.has(id));
    }
    signedIn.add(t.run);
  }

  const asks = new Map<number, Ask>();
  for (const e of t.evs) {
    if (e.out) {
      if (typeof e.msg.id === "number") {
        asks.set(e.msg.id, { id: e.msg.id, kind: e.msg.call ? "call" : e.msg.subscribe ? "subscribe" : "other", topic: e.msg.subscribe?.topic ?? "", what: describe(e.msg), answers: [] });
      }
    } else asks.get(e.id)?.answers.push(e);
  }
  // each ask's answers learned from, as far as each has come (the tape's n-th answer with the live n-th, or the live
  // one most like it)
  const learnt = new Map<number, number>();
  const learnFrom = () => {
    for (const [id, l] of r.live) {
      const a = asks.get(id);
      if (!a) continue;
      const recValues = values(a.answers);
      for (let i = learnt.get(id) ?? 0; i < l.values.length && i < recValues.length; i++) learn(r, recValues[i], l.values[i]);
      learnt.set(id, Math.min(l.values.length, recValues.length));
      // a subscription's later values: each tape value with the newest live one, for ids that come late (a reply)
      if (a.kind === "subscribe" && l.values.length > 0) for (const v of recValues) learn(r, v, l.values[l.values.length - 1]);
    }
  };
  const inner = r.changed;
  void inner;

  const seen = new Map<number, number>(); // the tape's answers per id met so far
  for (const e of t.evs) {
    if (!e.out) {
      seen.set(e.id, (seen.get(e.id) ?? 0) + 1);
      continue;
    }
    // what this ask came after: each ask's first answer that came before it in the tape
    const after = [...seen.keys()].filter((id) => asks.has(id));
    await r.until(
      () => `${t.name}: before ${describe(e.msg)}, no answer yet to ${after.filter((id) => !r.live.has(id)).map((id) => asks.get(id)!.what).join(", ")}`,
      () => { learnFrom(); return after.every((id) => r.live.has(id)); },
    );
    await r.until(
      () => `${t.name}: ${describe(e.msg)} holds ids no live answer gave: ${pending(r, e.msg).join(", ")}`,
      () => { learnFrom(); return pending(r, e.msg).length === 0; },
    );
    r.send(put(r, e.msg));
  }

  // every answer the tape has: a call's (its outcome), each of a subscription's values in turn until its last
  const faults: string[] = [];
  const done = (a: Ask): boolean => {
    const l = r.live.get(a.id);
    const rec = values(a.answers);
    if (rec.length === 0) return true;
    if (!l) return false;
    learnFrom();
    return closest(a, rec[rec.length - 1], l.values).length === 0;
  };
  try {
    await r.until(() => "", () => [...asks.values()].every(done));
  } catch {
    // the deadline: what still differs, said below
  }
  for (const a of asks.values()) {
    const rec = values(a.answers);
    if (rec.length === 0) continue;
    const l = r.live.get(a.id);
    if (!l) {
      faults.push(`${t.name} #${a.id} ${a.what}: the core never answered (the tape has ${rec.length})`);
      continue;
    }
    const d = closest(a, rec[rec.length - 1], l.values);
    for (const line of d.slice(0, 12)) faults.push(`${t.name} #${a.id} ${a.what}: ${line}`);
    if (d.length > 12) faults.push(`${t.name} #${a.id} ${a.what}: and ${d.length - 12} more`);
    const recBytes = a.answers.some((e) => !e.out && e.bytes);
    if (recBytes !== l.bytes.some(Boolean)) faults.push(`${t.name} #${a.id} ${a.what}: bytes ${recBytes ? "in the tape, not from the core" : "from the core, not in the tape"}`);
  }
  r.core.disconnect(r.client);
  return faults;

  /// Where the tape's last answer to `a` and the live core's differ: a call's one answer; of a subscription's values the
  /// one that came to it (none: the least apart), the live run's own values in between not compared (how many pushes
  /// a change takes is the station's timing).
  function closest(a: Ask, want: J, got: J[]): string[] {
    ignoring = TIMING_PATHS[a.topic] ?? [];
    if (a.kind !== "subscribe") return differ(r, want, got[got.length - 1]);
    let best: string[] | null = null;
    for (let i = got.length - 1; i >= 0; i--) {
      const d = differ(r, want, got[i]);
      if (d.length === 0) return d;
      if (best === null || d.length < best.length) best = d;
    }
    return best ?? [];
  }
}

/// The values an ask's answers make, in turn (a subscription's deltas applied; a call's whole answer).
function values(answers: Ev[]): J[] {
  const out: J[] = [];
  for (const e of answers) {
    if (e.out) continue;
    const m = e.msg;
    const prev = out.length > 0 ? out[out.length - 1] : undefined;
    out.push("value" in m ? m.value : "delta" in m ? applyKeyed(prev, m.delta) : m);
  }
  return out;
}

// ---- every tape

const names = process.argv.slice(2).filter((a) => a !== "--runs");
const tapes = (names.length > 0 ? names : readdirSync(join(HERE, "traces")).filter((f) => f.endsWith(".trace")).map((f) => f.slice(0, -6)))
  .map(readTape)
  .sort((a, b) => a.first - b.first);
if (listing) {
  const runs = new Map<string, string[]>();
  for (const t of tapes) runs.set(t.run, [...(runs.get(t.run) ?? []), t.name]);
  for (const r of runs.values()) console.log(r.join(" "));
  process.exit(0);
}
let failed = 0;
for (const t of tapes) {
  let faults: string[];
  try {
    faults = await play(t);
  } catch (e) {
    faults = [e instanceof Error ? e.message : String(e)];
  }
  if (faults.length === 0) console.log(`ok   ${t.name}`);
  else {
    failed++;
    console.log(`FAIL ${t.name}`);
    for (const f of faults) console.log(`  ${f}`);
    console.log(`  the core answers otherwise than the tape: if the core changed, record it again (e2e/run.sh mac with MBUI_CORE_TRACE=1, then scripts/trace.py out/e2e/mac/<flow>.log ${t.name})`);
  }
}
console.log(`${tapes.length - failed} of ${tapes.length} tapes are what the core answers`);
process.exit(failed > 0 ? 1 : 0);
