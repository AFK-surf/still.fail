// A device of the end-to-end runs that need no app (e2e/locks.ts, e2e/rigs.ts): still.fail's TS core in Node in a
// process of its own (client/core-ts hosts/node.ts, on the station's mesh addon: one core a process, as its calls'
// handlers are the module's), signed in with the dev cloud's mock account and keeping its keys in a file (a sealer
// that asks no one, though it notes each time it would have asked: `Device.asked`), as a person uses the app; or, as
// a device from before the update to a lock of one's own for everyone, with no sealer at all (`{ sealed: false }`:
// the core then keeps its signing key in a plain file and makes no key of a person's lock); or a web page in a desktop
// browser (`{ page: true }`: hosts/node.ts `page`, keeping no keys of an app and sealing nothing, as hosts/web.ts; it
// signs nothing, keeps no vault, approves no one). This file run as `device NAME` is that process; imported, it gives
// the run its devices and its checks (PASS or FAIL each, counted).
// Each device keeps the core's record of what its connections do (record.ts: dials, waits, what woke a link) in its
// data, `record.log`, across its restarts; a failed run keeps it (scripts/e2e-local.sh `kept`). What a device prints
// to stderr (its core's, its mesh addon's) comes out with its name before each line, `E| …`: the native mesh does not
// say whose its lines are, and the stations' say the same words.
// E2E_SF_SRC, E2E_ORIGIN, E2E_PEER_DATA as peer.ts.
import { type ChildProcess, execFileSync, fork } from "node:child_process";
import { appendFileSync, existsSync, mkdirSync, readFileSync, rmSync, watch, writeFileSync } from "node:fs";
import type { Socket } from "node:net";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const src = process.env.E2E_SF_SRC!;
export const origin = process.env.E2E_ORIGIN!;
export const dir = process.env.E2E_PEER_DATA!;
const { apply } = await import(pathToFileURL(join(src, "client/core-ts/src/delta.ts")).href);

export type J = any;

/// What `p` gives, or nothing once `ms` have gone by (a deadline: a core or a process that would not end).
export const within = <T>(p: Promise<T>, ms: number): Promise<T | undefined> => Promise.race([p, new Promise<undefined>((r) => setTimeout(r, ms))]);

/// The watch of a directory waited on, kept for the rest of the run and shared by its waits: one stream of the file
/// system's events for the run, not one begun and ended by each wait. It is only as good as the Mac's file events. On
/// one whose fseventsd had been at 100% of a CPU and 15 GB for days (Studio, 2026-11-11) a watch was told of none of
/// eight writes in 12 s, and this run's waits ended by whatever else was told later, or not at all: round 7 failed with
/// what it waited for there, "alice's own lock 16 long, not 16". So a wait looks once more as its time ends
/// (`whenChanged`), and says when that was what saw it.
const watches = new Map<string, Set<() => void>>();
function watching(d: string, changed: () => void): () => void {
  let told = watches.get(d);
  if (told === undefined) {
    const all = (told = new Set<() => void>());
    watches.set(d, all);
    const w = watch(d, { recursive: true }, () => {
      for (const f of [...all]) f();
    });
    // (a watch that fails, its directory gone: the next wait there begins another; those waiting keep their deadlines)
    w.on("error", () => {
      if (watches.get(d) === all) watches.delete(d);
      w.close();
    });
    w.unref();
  }
  told.add(changed);
  const mine = told;
  return () => void mine.delete(changed);
}

/// What `ok` gives, looked at again as each of `dirs` changes (the file system's events, as scripts/waitfor.mjs waits:
/// a station's database and the lock chains it keeps), or an error saying `what` by `ms`. Looked at once more at `ms`:
/// what holds by then is not failed for no change having been seen of it, and the run says that it was so.
export function whenChanged<T>(dirs: string[], ok: () => T | undefined | null | false, ms: number, what: () => string): Promise<T> {
  return new Promise((resolve, reject) => {
    let done = false;
    const end = () => {
      done = true;
      clearTimeout(deadline);
      for (const stop of stops) stop();
    };
    const look = (): boolean => {
      if (done) return false;
      const got = ok();
      if (got) (end(), resolve(got));
      return !!got;
    };
    const deadline = setTimeout(() => {
      if (look()) log(`  (seen only as its ${ms} ms ended: no change of ${dirs.join(", ")} was told for it; are this Mac's file events late or lost?)`);
      else if (!done) (end(), reject(new Error(what())));
    }, ms);
    const stops = dirs.map((d) => watching(d, () => void look()));
    look();
  });
}

/// Where a device notes each time its sealer was asked with the person present (`Device.asked`), in its data.
const askedFile = (data: string) => join(data, "asked.log");

// A device: this file run as `device NAME again|new sealed|plain|page`, its core's messages passed to and from the
// parent as they are.
if (process.argv[2] === "device") {
  const { start } = await import(pathToFileURL(join(src, "client/core-ts/src/hosts/node.ts")).href);
  const data = join(dir, process.argv[3]);
  // (`again`: the same device started anew, its data and what it sealed kept)
  if (process.argv[4] !== "again") rmSync(data, { recursive: true, force: true });
  mkdirSync(data, { recursive: true });
  // What it seals, in a file of its own (the system's secure storage, as it outlives the app).
  const sealedAt = join(data, "sealed.json");
  const kept = new Map<string, Uint8Array>(existsSync(sealedAt) ? Object.entries(JSON.parse(readFileSync(sealedAt, "utf8")) as Record<string, string>).map(([k, v]) => [k, Buffer.from(v, "hex")]) : []);
  const save = () => writeFileSync(sealedAt, JSON.stringify(Object.fromEntries([...kept].map(([k, v]) => [k, Buffer.from(v).toString("hex")]))));
  // Each time the person would have been asked (a value sealed for their presence read, or they asked to say yes),
  // a line, written as it happens: it outlives the process, as the driver reads it after a restart.
  const noteAsked = (what: string) => appendFileSync(askedFile(data), `${what}\n`);
  const sealer = {
    get: async (key: string, user: boolean, _reason: string) => {
      if (user) noteAsked(`get ${key}`);
      return kept.get(key) ?? null;
    },
    set: async (key: string, value: Uint8Array, _user: boolean) => void (kept.set(key, value), save()),
    delete: async (key: string) => void (kept.delete(key), save()),
    ask: async (_reason: string) => noteAsked("ask"),
  };
  // (`plain`: a device from before, whose host seals nothing: hosts/node.ts gives it no `secure*`; `page`: a web page's
  // host, no app's keys and nothing sealed)
  // (its record goes on in the same file when started `again`, as its data does)
  const record = join(data, "record.log");
  const options = process.argv[5] === "page" ? { page: true, record } : process.argv[5] === "plain" ? { record } : { sealer, record };
  const core = start(join(data, "core"), origin, (_c: number, json: string) => process.send!(json), undefined, options);
  const client = core.connect();
  process.on("message", (m: J) => {
    if (m === "close") void within(core.close(), 4000).then(() => process.exit(0));
    else core.receive(client, m);
  });
  // (the driver gone without closing it, as when it fell: this device does not stay behind, holding its output open)
  process.on("disconnect", () => process.exit(0));
  await new Promise(() => {});
}
const t0 = Date.now();
export const log = (s: string) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1)}s] ${s}`);
let failed = 0;
/// How many checks failed so far.
export const failures = (): number => failed;
export const pass = (what: string) => log(`PASS ${what}`);
export const fail = (what: string, why: unknown) => {
  failed++;
  log(`FAIL ${what}: ${why instanceof Error ? why.message : String(why)}`.slice(0, 3000));
};
export async function check(what: string, body: () => Promise<unknown>): Promise<boolean> {
  try {
    await body();
    pass(what);
    return true;
  } catch (e) {
    fail(what, e);
    return false;
  }
}

export class Device {
  child: ChildProcess;
  next = 1;
  pending = new Map<number, (m: J) => void>();
  topics = new Map<number, { value: J; error: J; changed: () => void }>();
  name: string;
  /// Whose device: the dev cloud's mock account (alice, or bob) and, once signed in, its subject.
  user: string;
  sub = "";
  /// Whether its host seals what it keeps (an app of today); false: an app from before, with no sealer.
  sealed: boolean;
  /// A web page's, not an app's (no keys of an app, nothing sealed).
  page: boolean;
  constructor(name: string, user = "alice", opts: { sealed?: boolean; page?: boolean } = {}) {
    this.name = name;
    this.user = user;
    this.page = opts.page ?? false;
    this.sealed = !this.page && (opts.sealed ?? true);
    this.child = this.#fork(false);
  }
  #fork(again: boolean): ChildProcess {
    const kind = this.page ? "page" : this.sealed ? "sealed" : "plain";
    const child = fork(fileURLToPath(import.meta.url), ["device", this.name, again ? "again" : "new", kind], { stdio: ["ignore", "inherit", "pipe", "ipc"] });
    child.on("message", (json: J) => this.#got(JSON.parse(json)));
    // Its stderr a line at a time, named; a line not yet ended waits for its end, or for the stream's. The pipe never
    // keeps the driver up (`close` waits for it to end instead).
    const err = child.stderr!;
    (err as Socket).unref();
    err.setEncoding("utf8");
    let partial = "";
    err.on("data", (chunk: string) => {
      const lines = (partial + chunk).split("\n");
      partial = lines.pop()!;
      for (const line of lines) process.stderr.write(`${this.name}| ${line}\n`);
    });
    err.on("end", () => {
      if (partial !== "") process.stderr.write(`${this.name}| ${partial}\n`);
      partial = "";
    });
    return child;
  }
  /// What it says it is (`client.device`, prefs.ts `device`): a desktop app, or a web page in a desktop browser.
  #about(): J {
    return this.page
      ? { client: "still.fail e2e", app: "web", userAgent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36" }
      : { client: "still.fail e2e", app: "desktop", model: this.name };
  }
  /// The app quit and started again: the same data, a core anew (what it was subscribed to forgotten). `sealed: true`
  /// on a device from before: the app updated, its host sealing now; left out, as it was.
  async restart(opts: { sealed?: boolean } = {}): Promise<void> {
    await this.close();
    this.pending.clear();
    this.topics.clear();
    if (opts.sealed !== undefined) this.sealed = opts.sealed;
    this.child = this.#fork(true);
    await this.call("client.device", this.#about());
  }
  /// How many times its sealer was asked with the person present since the device was new: a value sealed for their
  /// presence read (`get` with `user`), or the person asked to say yes (`ask`). None while it had no sealer.
  asked(): number {
    const at = askedFile(join(dir, this.name));
    return existsSync(at) ? readFileSync(at, "utf8").split("\n").filter((l) => l !== "").length : 0;
  }
  #send(m: J) {
    // (a device closed while a wait on it was still counting, one of two a step raced: nothing is there to be told
    // the wait is over, and sending to it would be an error of the driver's own)
    if (!this.child.connected) return;
    this.child.send(JSON.stringify(m));
  }
  #got(m: J) {
    if (m.fatal) {
      console.error(`${this.name}: core fatal:`, m.fatal);
      process.exit(3);
    }
    const t = this.topics.get(m.id);
    if (t && "value" in m) t.value = m.value;
    else if (t && "delta" in m) t.value = apply(t.value, m.delta);
    else if (t && "error" in m) t.error = m.error;
    else if (this.pending.has(m.id)) {
      this.pending.get(m.id)!(m);
      this.pending.delete(m.id);
      return;
    }
    t?.changed();
  }
  call(name: string, params?: J): Promise<J> {
    const id = this.next++;
    return new Promise((resolve, reject) => {
      this.pending.set(id, (m) => ("error" in m ? reject(new Error(`${this.name} ${name}: ${JSON.stringify(m.error)}`)) : resolve(m.ok)));
      this.#send(params === undefined ? { id, call: name } : { id, call: name, params });
    });
  }
  /// The topic's value once `ok` gives something (or the time is up: what it was, in the error).
  until<T>(topic: J, ok: (v: J) => T | undefined | null | false, ms = 60_000): Promise<T> {
    const id = this.next++;
    return new Promise((resolve, reject) => {
      const entry = { value: undefined as J, error: undefined as J, changed: () => {} };
      const end = () => {
        this.topics.delete(id);
        this.#send({ id, unsubscribe: true });
      };
      const timer = setTimeout(() => {
        end();
        reject(new Error(`${this.name} timed out on ${JSON.stringify(topic)}: ${JSON.stringify(entry.value ?? entry.error)?.slice(0, 2500)}`));
      }, ms);
      entry.changed = () => {
        if (entry.value === undefined) return;
        const got = ok(entry.value);
        if (got) {
          clearTimeout(timer);
          end();
          resolve(got);
        }
      };
      this.topics.set(id, entry);
      this.#send({ id, subscribe: topic });
    });
  }
  async signIn(): Promise<{ workspace: string; station: string }> {
    await this.call("client.device", this.#about());
    // (the dev cloud's sign-in: one over the account's requests a minute is a finding, not tried again)
    const r = await fetch(`${origin}/__dev/account?user=${this.user}`);
    const text = await r.text();
    if (!r.ok) throw new Error(`dev sign-in: ${r.status} ${text.slice(0, 200)}`);
    const account = JSON.parse(text);
    await this.call("migrate", { accounts: [account] });
    const accounts = await this.until({ topic: "accounts" }, (v) => (Array.isArray(v) && v.length > 0 ? v : undefined));
    this.sub = accounts[0].sub;
    const workspace = await this.until({ topic: "workspaces" }, (v) => {
      for (const a of v ?? []) for (const w of a.workspaces ?? []) if (w.name === "Dev") return w.id as string;
      return undefined;
    });
    const station = await this.until({ topic: "workspace", workspace }, (v) => {
      const st = (v?.stations ?? [])[0];
      return st ? `${workspace}/${st.id}` : undefined;
    }, 120_000);
    return { workspace, station };
  }
  /// How the station stands for this device (the chats topic's station row): its state and why.
  stationState(workspace: string, ok: (s: J) => boolean, ms = 60_000): Promise<J> {
    return this.until({ topic: "chats", scope: workspace, mine: false, limit: 5 }, (v) => {
      const s = (v?.stations ?? [])[0];
      return s && ok(s) ? s : undefined;
    }, ms);
  }
  personal(ok: (p: J) => boolean, ms = 60_000): Promise<J> {
    return this.until({ topic: "adbShare" }, (v) => {
      const p = (v?.personal ?? []).find((x: J) => x.sub === this.sub);
      return p && ok(p) ? p : undefined;
    }, ms);
  }
  lock(workspace: string, ok: (l: J) => boolean, ms = 60_000): Promise<J> {
    return this.until({ topic: "lock", workspace }, (v) => (v && ok(v) ? v : undefined), ms);
  }
  close(): Promise<void> {
    if (this.child.exitCode !== null || this.child.signalCode !== null) return Promise.resolve();
    const child = this.child;
    // (`close`, not `exit`: its stderr read to the end, so what it said last is written before the run goes on)
    const exited = new Promise<void>((resolve) => child.once("close", () => resolve()));
    child.send("close");
    return within(exited, 5000).then(() => {
      if (child.exitCode === null && child.signalCode === null) child.kill("SIGKILL");
    });
  }
}

/// A check the run cannot go on without.
export const must = async (what: string, body: () => Promise<unknown>) => {
  if (!(await check(what, body))) throw new Error(`stopped at: ${what}`);
};

/// scripts/e2e-local.sh's words said from a run (freeze, thaw, second-station …): what it printed, and its last line logged.
export const stationSays = (what: string, ...more: string[]): string => execFileSync("scripts/e2e-local.sh", [what, ...more], { encoding: "utf8", env: { ...process.env, HOME: process.env.E2E_HOME ?? process.env.HOME } });
export const stationDo = (what: string, ...more: string[]) => log(`  station: ${stationSays(what, ...more).trim().split("\n").pop()}`);
