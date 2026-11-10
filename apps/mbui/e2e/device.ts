// A device of the end-to-end runs that need no app (e2e/locks.ts, e2e/rigs.ts): still.fail's TS core in Node in a
// process of its own (client/core-ts hosts/node.ts, on the station's mesh addon: one core a process, as its calls'
// handlers are the module's), signed in with the dev cloud's mock account and keeping its keys in a file (a sealer
// that asks no one), as a person uses the app. This file run as `device NAME` is that process; imported, it gives the
// run its devices and its checks (PASS or FAIL each, counted). E2E_SF_SRC, E2E_ORIGIN, E2E_PEER_DATA as peer.ts.
import { type ChildProcess, execFileSync, fork } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, watch, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const src = process.env.E2E_SF_SRC!;
export const origin = process.env.E2E_ORIGIN!;
export const dir = process.env.E2E_PEER_DATA!;
const { apply } = await import(pathToFileURL(join(src, "client/core-ts/src/delta.ts")).href);

export type J = any;

/// What `p` gives, or nothing once `ms` have gone by (a deadline: a core or a process that would not end).
export const within = <T>(p: Promise<T>, ms: number): Promise<T | undefined> => Promise.race([p, new Promise<undefined>((r) => setTimeout(r, ms))]);

/// What `ok` gives, looked at again as each of `dirs` changes (the file system's events, as scripts/waitfor.mjs waits:
/// a station's database and the lock chains it keeps), or an error saying `what` by `ms`.
export function whenChanged<T>(dirs: string[], ok: () => T | undefined | null | false, ms: number, what: () => string): Promise<T> {
  return new Promise((resolve, reject) => {
    let done = false;
    const watchers = dirs.map((d) => watch(d, { recursive: true }, () => look()));
    const end = () => {
      done = true;
      clearTimeout(deadline);
      for (const w of watchers) w.close();
    };
    const deadline = setTimeout(() => (end(), reject(new Error(what()))), ms);
    const look = () => {
      if (done) return;
      const got = ok();
      if (got) (end(), resolve(got));
    };
    look();
  });
}

// A device: this file run as `device NAME`, its core's messages passed to and from the parent as they are.
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
  const sealer = {
    get: async (key: string) => kept.get(key) ?? null,
    set: async (key: string, value: Uint8Array) => void (kept.set(key, value), save()),
    delete: async (key: string) => void (kept.delete(key), save()),
    ask: async () => {},
  };
  const core = start(join(data, "core"), origin, (_c: number, json: string) => process.send!(json), undefined, { sealer });
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
  constructor(name: string, user = "alice") {
    this.name = name;
    this.user = user;
    this.child = this.#fork(false);
  }
  #fork(again: boolean): ChildProcess {
    const child = fork(fileURLToPath(import.meta.url), ["device", this.name, ...(again ? ["again"] : [])], { stdio: ["ignore", "inherit", "inherit", "ipc"] });
    child.on("message", (json: J) => this.#got(JSON.parse(json)));
    return child;
  }
  /// The app quit and started again: the same data, a core anew (what it was subscribed to forgotten).
  async restart(): Promise<void> {
    await this.close();
    this.pending.clear();
    this.topics.clear();
    this.child = this.#fork(true);
    await this.call("client.device", { client: "still.fail e2e", app: "desktop", model: this.name });
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
    await this.call("client.device", { client: "still.fail e2e", app: "desktop", model: this.name });
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
    const exited = new Promise<void>((resolve) => child.once("exit", () => resolve()));
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
