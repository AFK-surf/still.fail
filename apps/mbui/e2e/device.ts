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
// data, `record.log`, across its restarts, with a line for each request of a station answered (`asked: …`, this file's:
// `watchRequests`); a failed run keeps it (scripts/e2e-local.sh `kept`). What a device prints
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

/// The mesh addon the core is given, its requests watched (`Device.answered`). hosts/node-iroh.ts loads it with
/// process.dlopen; wrapped as it is loaded, every request the core makes of a station is seen where it goes: on a stream
/// of its own, its first write the head line (client/core-ts/src/mesh.ts `#open`: `{"method","path",…}`), its answer
/// read to its end as that stream reads null, the station the connection's (`remoteId`, a station's id). `told` hears
/// each such answer; nothing the core sends or reads is changed.
function watchRequests(told: (station: string, method: string, path: string) => void): void {
  // (the object as it is, but for `own`: the native one's methods called on it)
  const over = <T extends object>(target: T, own: Record<string, unknown>): T =>
    new Proxy(target, {
      get: (t, k) => {
        if (typeof k === "string" && k in own) return own[k];
        const v = Reflect.get(t, k);
        return typeof v === "function" ? v.bind(t) : v;
      },
    });
  const stream = (s: J, station: string): J => {
    let first = true;
    let head: { method: string; path: string } | null = null;
    return over(s, {
      write: (b: Buffer) => {
        if (first) {
          first = false;
          const end = b.indexOf(10);
          try {
            const h = end > 0 ? JSON.parse(b.subarray(0, end).toString("utf8")) : null;
            if (typeof h?.method === "string" && typeof h.path === "string") head = { method: h.method, path: h.path };
          } catch {}
        }
        return s.write(b);
      },
      read: async () => {
        const b = await s.read();
        if ((b === null || b === undefined) && head !== null) {
          const h = head;
          head = null;
          told(station, h.method, h.path);
        }
        return b;
      },
    });
  };
  const connection = (c: J): J => over(c, { openBi: async () => stream(await c.openBi(), c.remoteId()) });
  const endpoint = (e: J): J => over(e, { connect: async (...a: J[]) => connection(await e.connect(...a)) });
  const dlopen = process.dlopen.bind(process);
  process.dlopen = ((module: { exports: J }, filename: string, ...rest: J[]) => {
    (dlopen as (...x: J[]) => void)(module, filename, ...rest);
    const addon = module.exports;
    if (typeof addon?.bind !== "function") return;
    module.exports = over(addon, { bind: async (o: J) => endpoint(await addon.bind(o)) });
  }) as typeof process.dlopen;
}

// A device: this file run as `device NAME again|new sealed|plain|page`, its core's messages passed to and from the
// parent as they are.
if (process.argv[2] === "device") {
  const data = join(dir, process.argv[3]);
  // (its record: what its links do, the core's lines; and each request of a station answered, this file's)
  const record = join(data, "record.log");
  // (before the core is loaded: it loads the addon as its host is made)
  watchRequests((station, method, path) => {
    appendFileSync(record, `asked: ${station.slice(0, 8)} ${method} ${path} -> answered\n`);
    if (process.connected) process.send!({ answered: { station, method, path } });
  });
  const { start } = await import(pathToFileURL(join(src, "client/core-ts/src/hosts/node.ts")).href);
  // (`again`: the same device started anew, its data and what it sealed kept)
  if (process.argv[4] !== "again") rmSync(data, { recursive: true, force: true });
  mkdirSync(data, { recursive: true });
  // What it seals, in a file of its own (the system's secure storage, as it outlives the app).
  const sealedAt = join(data, "sealed.json");
  const kept = new Map<string, Uint8Array>(existsSync(sealedAt) ? Object.entries(JSON.parse(readFileSync(sealedAt, "utf8")) as Record<string, string>).map(([k, v]) => [k, Buffer.from(v, "hex")]) : []);
  const save = () => writeFileSync(sealedAt, JSON.stringify(Object.fromEntries([...kept].map(([k, v]) => [k, Buffer.from(v).toString("hex")]))));
  // Each time the person would have been asked (a value sealed for their presence read, or they asked to say yes),
  // a line, written as it happens: it outlives the process, as the driver reads it after a restart. Its time and the
  // reason the core gave, so a check that finds someone asked says what asked (the side run of 2026-11-13: "asked the
  // person 7 times" and nothing of why).
  const noteAsked = (what: string, reason: string) => appendFileSync(askedFile(data), `${new Date().toISOString()} ${what} ${reason.replace(/\s+/g, " ")}\n`);
  const sealer = {
    get: async (key: string, user: boolean, reason: string) => {
      if (user) noteAsked(`get ${key}`, reason);
      return kept.get(key) ?? null;
    },
    set: async (key: string, value: Uint8Array, _user: boolean) => void (kept.set(key, value), save()),
    delete: async (key: string) => void (kept.delete(key), save()),
    ask: async (reason: string) => noteAsked("ask", reason),
  };
  // (`plain`: a device from before, whose host seals nothing: hosts/node.ts gives it no `secure*`; `page`: a web page's
  // host, no app's keys and nothing sealed)
  // (its record goes on in the same file when started `again`, as its data does)
  // (`handOverByTests`: the core offers `lock.handOver` to this driver, as no app's host does: views/lock.ts `handOver`;
  // `handOverAuto` but with E2E_HANDOVER=call, a chain handed over by itself as it is from HAND_OVER_FROM, e2e/locks-moved.ts)
  const options = { handOverByTests: true, handOverAuto: process.env.E2E_HANDOVER !== "call", ...(process.argv[5] === "page" ? { page: true, record } : process.argv[5] === "plain" ? { record } : { sealer, record }) };
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
/// A device the dev cloud would not sign in (its sign-in limit, the cloud down): every round after it that needs that
/// device would fail one by one, for minutes, each naming something else; the run ends at once instead, saying why.
export class SignInFailed extends Error {}
export async function check(what: string, body: () => Promise<unknown>): Promise<boolean> {
  try {
    await body();
    pass(what);
    return true;
  } catch (e) {
    fail(what, e);
    if (e instanceof SignInFailed) throw new SignInFailed(`stopped: a device not signed in (${e.message})`);
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
  /// The last six characters of the access token it was signed in with: how the dev cloud's log (LOG_REQUESTS,
  /// cloud/test/dev.ts) names its requests, so a run can count an account's requests a minute.
  tokenTail = "";
  /// Whether its host seals what it keeps (an app of today); false: an app from before, with no sealer.
  sealed: boolean;
  /// A web page's, not an app's (no keys of an app, nothing sealed).
  page: boolean;
  /// The release it says it is (`client.device`'s `build`, `0.1.<n>`, said with each request to a station, which keeps
  /// the highest a device of a lock said: station/src/mesh/device-builds.ts); none: `0.1.0`, a build from the sources,
  /// taken as one that takes a moved workspace (client/core-ts src/lock-handover.ts `ableBuild`). An owner's app of a
  /// release before MOVED_FROM_BUILD moves nothing itself (views/lock.ts `heldBack`, its own build), so a workspace
  /// whose owners' apps all say one stays as before a move; no other device's build holds a move back.
  build: string | undefined;
  /// Each request of its core's to a station whose answer it read to its end (`watchRequests`), across its restarts,
  /// as this driver heard of it (`at`: its clock then); and the waits for one (`answered`).
  answers: { station: string; method: string; path: string; at: number }[] = [];
  #heard = new Set<() => void>();
  constructor(name: string, user = "alice", opts: { sealed?: boolean; page?: boolean; build?: string } = {}) {
    this.name = name;
    this.user = user;
    this.page = opts.page ?? false;
    this.build = opts.build;
    this.sealed = !this.page && (opts.sealed ?? true);
    this.child = this.#fork(false);
  }
  #fork(again: boolean): ChildProcess {
    const kind = this.page ? "page" : this.sealed ? "sealed" : "plain";
    const child = fork(fileURLToPath(import.meta.url), ["device", this.name, again ? "again" : "new", kind], { stdio: ["ignore", "inherit", "pipe", "ipc"] });
    // (its core's messages are its JSON; what watchRequests tells, an object)
    child.on("message", (m: J) => {
      if (typeof m === "string") return this.#got(JSON.parse(m));
      if (m?.answered) {
        this.answers.push({ ...m.answered, at: Date.now() });
        for (const f of [...this.#heard]) f();
      }
    });
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
      : { client: "still.fail e2e", app: "desktop", model: this.name, ...(this.build === undefined ? {} : { build: this.build }) };
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
    return this.askedWhat().length;
  }
  /// What its sealer was asked from the `from`th time on (`asked`), a line each: when, what (`get <key>`, `ask`), the
  /// reason the core gave.
  askedWhat(from = 0): string[] {
    const at = askedFile(join(dir, this.name));
    return (existsSync(at) ? readFileSync(at, "utf8").split("\n").filter((l) => l !== "") : []).slice(from);
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
  /// A standing subscription to `topic`: every value it is given, kept with this driver's clock (`values`), until
  /// `stop`. One subscription all along, so what it shows between two looks is not missed, and no look of the driver's
  /// asks the core anything more (subscribing to a topic may read again what it shows: the `lock` topic does).
  watch(topic: J): { values: { at: number; value: J }[]; stop: () => void } {
    const id = this.next++;
    const values: { at: number; value: J }[] = [];
    const entry = { value: undefined as J, error: undefined as J, changed: () => {} };
    entry.changed = () => {
      if (entry.value !== undefined) values.push({ at: Date.now(), value: structuredClone(entry.value) });
    };
    this.topics.set(id, entry);
    this.#send({ id, subscribe: topic });
    return {
      values,
      stop: () => {
        if (!this.topics.delete(id)) return;
        this.#send({ id, unsubscribe: true });
      },
    };
  }
  async signIn(): Promise<{ workspace: string; station: string }> {
    await this.call("client.device", this.#about());
    // (the dev cloud's sign-in: one over the account's requests a minute is a finding, not tried again)
    const r = await fetch(`${origin}/__dev/account?user=${this.user}`);
    const text = await r.text();
    if (!r.ok) throw new SignInFailed(`${this.name} dev sign-in: ${r.status} ${text.slice(0, 200)}`);
    const account = JSON.parse(text);
    this.tokenTail = String(account.access ?? "").slice(-6);
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
  /// How a station stands for this device (the first of the workspace's, or the one of `id`): its link's state and
  /// message as its page has them (the `station` topic's `link`), and `cause` lock while it is down for a security
  /// mode (its `blocked`). The chats topic's station rows said these till #5382 left them what the list's rows read.
  async stationState(workspace: string, ok: (s: J) => boolean, ms = 60_000, id?: string): Promise<J> {
    const station = await this.until({ topic: "stations", scope: workspace }, (v) => {
      const s = (v ?? []).find((s: J) => id === undefined || s.id === id);
      return s ? (s.station as string) : undefined;
    }, ms);
    return this.until({ topic: "station", scope: workspace, station }, (v) => {
      if (!v?.link) return undefined;
      const s: J = { station, state: v.link.state, message: v.link.message, ...(v.link.old ? { old: v.link.old } : {}), ...(v.blocked ? { cause: "lock", blocked: v.blocked } : {}) };
      return ok(s) ? s : undefined;
    }, ms);
  }
  /// The first request of its core's to station `station` whose path (less `/admin/api`) begins with `path`, answered
  /// and read to its end since `since` (this driver's clock), as soon as it is (or an error by `ms` saying those there
  /// were): what a read of the station that ends in it has been given, its core's own handling of it to follow.
  answered(station: string, path: string, since: number, ms = 60_000): Promise<{ station: string; method: string; path: string; at: number }> {
    const find = () => this.answers.find((a) => a.at >= since && a.station === station && a.path.replace(/^\/admin\/api/, "").startsWith(path));
    return new Promise((resolve, reject) => {
      const look = () => {
        const a = find();
        if (!a) return;
        clearTimeout(timer);
        this.#heard.delete(look);
        resolve(a);
      };
      const timer = setTimeout(() => {
        this.#heard.delete(look);
        const seen = this.answers.filter((a) => a.at >= since).map((a) => `${a.station.slice(0, 8)} ${a.method} ${a.path}`);
        reject(new Error(`${this.name}: no ${path} of ${station.slice(0, 8)} answered in ${ms} ms; answered since: ${seen.join(", ").slice(0, 2000) || "none"}`));
      }, ms);
      this.#heard.add(look);
      look();
    });
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
