// The locks end to end against the local still.fail (scripts/e2e-local.sh locks, after up; locks-all, the side run's):
// alice's devices and bob's, each still.fail's TS core in Node in a process of its own (client/core-ts hosts/node.ts,
// on the station's mesh addon: one core a process, as its calls' handlers are the module's), each signed in with the
// dev cloud's mock account and keeping its keys in a file (a sealer that asks no one), as a person uses the app:
//   1-3 A turns safe mode on and keeps an item in a vault; C is approved into the workspace's lock face to face (the
//     old way) and given the vault; A opens alice's own lock: C, off it, keeps it from being bound until C joins it;
//     A takes C off: C taken out, the vault keyed anew; B joins the own lock face to face, is let in and given the
//     vault; A, its vault locked, takes B off: B refused, the vault keyed anew (the box key read); B joins again;
//     D joins through B; the station restarted, D taken off while it is frozen, B taken off while its app is closed;
//   4 B takes A, the first device, off; the last one left cannot take itself off;
//   5 A's app installed anew (its data and keys gone): a new device, let in only as it joins again;
//   6 the cloud frozen while a device joins and is taken off: the stations carry the locks;
//   7 a second station in the lock, the first frozen while a device joins and is taken off through the second;
//   8 bob, a member: his first device approved by the owner face to face, a vault of his own, his own lock and his
//     second device on it; taken out of the workspace by the owner, out of its lock with his devices, refused;
//   9 a second workspace of alice's, safe mode on there too, its own station: a device joining her own lock once is let
//     in by both, taken off it refused by both;
//   10 safe mode turned off in the second: its station lets that device in again, the first still refuses it;
//   11 round 7's second station taken out of the first workspace: out of its lock too.
// Each check says PASS or FAIL; it goes on after a failure where it can, and exits 1 if any failed. E2E_SF_SRC,
// E2E_ORIGIN, E2E_PEER_DATA as peer.ts; E2E_WORK, E2E_STATION as e2e-local.sh's.
import { type ChildProcess, execFileSync, fork } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, watch, writeFileSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const src = process.env.E2E_SF_SRC!;
const origin = process.env.E2E_ORIGIN!;
const dir = process.env.E2E_PEER_DATA!;
const { apply } = await import(pathToFileURL(join(src, "client/core-ts/src/delta.ts")).href);

type J = any;

/// What `p` gives, or nothing once `ms` have gone by (a deadline: a core or a process that would not end).
const within = <T>(p: Promise<T>, ms: number): Promise<T | undefined> => Promise.race([p, new Promise<undefined>((r) => setTimeout(r, ms))]);

/// What `ok` gives, looked at again as each of `dirs` changes (the file system's events, as scripts/waitfor.mjs waits:
/// a station's database and the lock chains it keeps), or an error saying `what` by `ms`.
function whenChanged<T>(dirs: string[], ok: () => T | undefined | null | false, ms: number, what: () => string): Promise<T> {
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
  await new Promise(() => {});
}
const t0 = Date.now();
const log = (s: string) => console.log(`[${((Date.now() - t0) / 1000).toFixed(1)}s] ${s}`);
let failed = 0;
const pass = (what: string) => log(`PASS ${what}`);
const fail = (what: string, why: unknown) => {
  failed++;
  log(`FAIL ${what}: ${why instanceof Error ? why.message : String(why)}`.slice(0, 3000));
};
async function check(what: string, body: () => Promise<unknown>): Promise<boolean> {
  try {
    await body();
    pass(what);
    return true;
  } catch (e) {
    fail(what, e);
    return false;
  }
}

class Device {
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
    if (this.user === "alice") sub = this.sub;
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

const lockDevices = (l: J): J[] => (l.members ?? []).flatMap((m: J) => (m.groups ?? []).flatMap((g: J) => g.devices ?? []));
const appIds = (l: J): string[] => lockDevices(l).filter((d) => d.kind === "app").map((d) => d.id.slice(0, 8)).sort();
const short = (s: J) => JSON.stringify({ state: s.state, cause: s.cause, message: s.message });
const must = async (what: string, body: () => Promise<unknown>) => {
  if (!(await check(what, body))) throw new Error(`stopped at: ${what}`);
};

const a = new Device("A");
const b = new Device("B");
const c = new Device("C");
const d = new Device("D");
const e = new Device("E");
const f = new Device("F");
const g = new Device("G");
const h = new Device("H", "bob");
const i = new Device("I", "bob");
const j = new Device("J");
let dKey = "";
let dBase = "";
/// The test station frozen (as if its network went) or started anew (scripts/e2e-local.sh freeze, thaw).
const stationSays = (what: string): string => execFileSync("scripts/e2e-local.sh", [what], { encoding: "utf8", env: { ...process.env, HOME: process.env.E2E_HOME ?? process.env.HOME } });
const stationDo = (what: string, ...more: string[]) => log(`  station: ${execFileSync("scripts/e2e-local.sh", [what, ...more], { encoding: "utf8", env: { ...process.env, HOME: process.env.E2E_HOME ?? process.env.HOME } }).trim().split("\n").pop()}`);
let sub = "";
/// The test station's data: its database, the lock chains it keeps (scripts/e2e-local.sh lock-state reads them).
const stationData = `${process.env.E2E_STATION}/data`;
try {
  const { workspace, station } = await a.signIn();
  log(`A signed in as ${sub}: workspace ${workspace}, station ${station}`);
  await a.stationState(workspace, (s) => s.state === "online", 120_000);
  const baseOf = async (d: Device) => (await d.lock(workspace, (l) => typeof l.me?.device === "string")).me.device as string;
  const aBase = await baseOf(a);

  await must("A turns safe mode on, the only device in it", async () => {
    const draft = await a.until({ topic: "lockDraft", workspace }, (v) => (v?.ready ? v : undefined), 120_000);
    for (const d of draft.devices ?? []) if (!d.current) await a.call("lock.toggle", { workspace, id: d.id });
    await a.call("lock.open", { workspace });
    await a.lock(workspace, (l) => l.locked && l.signs);
    await a.stationState(workspace, (s) => s.state === "online");
  });

  let vault = "";
  let item = "";
  const secret = `ghp_e2e_${Date.now()}`;
  const opens = async (d: Device) => {
    const o = await d.call("vault.open", { workspace, item });
    if (o?.plain?.fields?.value !== secret) throw new Error(`${d.name} opened: ${JSON.stringify(o)?.slice(0, 300)}`);
  };
  const keyedFor = async (d: Device, ms = 90_000) => {
    await d.until({ topic: "vaults", workspace }, (v) => (v?.vaults ?? []).find((x: J) => x.id === vault && x.keyed), ms);
  };
  // (once it has heard it is out of the workspace's lock: what it held before, it held)
  const refusedVault = async (d: Device) => {
    const l = await d.lock(workspace, (l) => !l.signs, 60_000);
    log(`  ${d.name}'s lock view: me=${JSON.stringify(l.me)}`);
    await d.call("vault.lock", { workspace });
    const o = await d.call("vault.open", { workspace, item }).then((o) => o, (e) => e);
    if (!(o instanceof Error)) throw new Error(`still opened: ${JSON.stringify(o)?.slice(0, 200)}`);
    log(`  ${d.name}'s vault.open: ${o.message.slice(0, 200)}`);
  };
  /// A's vault as it stands after a device went: shown again (keyed anew) and opened, how long it took.
  const aStill = async (what: string) => {
    const t1 = Date.now();
    const v = await a.until({ topic: "vaults", workspace }, (v) => (v?.vaults ?? []).find((x: J) => x.id === vault && x.keyed), 60_000);
    log(`  ${what}: A's vault back after ${Date.now() - t1} ms (${v.devices} devices hold its key)`);
    await a.stationState(workspace, (s) => s.state === "online");
    await opens(a);
  };

  await must("A sets up the vault and keeps an item in it", async () => {
    await a.until({ topic: "vaults", workspace }, (v) => (v?.locked && (v.refused ?? []).length === 0 ? v : undefined), 60_000);
    await a.call("vault.setup", { workspace });
    await a.until({ topic: "vaults", workspace }, (v) => v?.setUp, 60_000);
    vault = (await a.call("vault.create", { workspace, name: "e2e", station: station.split("/")[1] })).id;
    item = (await a.call("vault.putItem", {
      workspace, vault,
      plain: { kind: "token", name: "e2e-token", fields: { value: secret }, domains: [], notes: "" },
      listing: { name: "e2e-token", kind: "token", modes: ["proxy"], hosts: ["api.example.test"] },
    })).id;
  });

  // ── C: a device let into the workspace's lock the old way (face to face, before the own lock), given the vault ──
  await c.signIn();
  await must("C approved into the workspace's lock face to face by A (the old way)", async () => {
    // (left out by the station first: then it waits in the workspace, to be approved)
    await c.stationState(workspace, (s) => s.cause === "lock", 60_000);
    await c.lock(workspace, (l) => l.me?.waiting, 60_000);
    const shown = a.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await c.call("lock.pair", { workspace });
    const p = await shown;
    await c.call("lock.pairCode", { workspace, code: p.code });
    await c.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await c.stationState(workspace, (s) => s.state === "online", 90_000);
  });
  const cBase = await baseOf(c);
  await must("C sets up the vault, is given its key, opens the item", async () => {
    await c.call("vault.setup", { workspace });
    await keyedFor(c);
    await opens(c);
  });

  // ── the own lock opened: bound, and C (never on it) taken out of the workspace's lock by A ──
  await must("A opens alice's own lock", async () => {
    await a.call("adb.personalOpen", { sub });
    await a.personal((p) => p.standing === "member");
  });
  // ── C, of the workspace's lock but off alice's own, keeps it from being bound: C still let in, until it joins ──
  const join = async (d: Device) => {
    const shown = a.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await d.call("adb.personalJoin", { sub });
    const p = await shown;
    await d.call("adb.personalCode", { code: p.code });
    const mine = await d.personal((p) => p.standing === "member", 90_000);
    return mine.devices.find((x: J) => x.me)?.key as string;
  };
  await check("C, off alice's own lock, keeps it from being bound: still in the workspace's lock, let in, opens the item", async () => {
    const l = await a.lock(workspace, (l) => l.signs, 30_000);
    if (!lockDevices(l).some((d) => d.id === cBase)) throw new Error("C taken out");
    await c.stationState(workspace, (s) => s.state === "online", 30_000);
    await opens(c);
  });
  let cKey = "";
  await must("C joins alice's own lock face to face with A, and alice is bound to it then", async () => {
    if (stationSays("lock-state").includes("PERSONS 1")) throw new Error("bound before C joined");
    cKey = await join(c);
    await whenChanged([stationData], () => stationSays("lock-state").includes("PERSONS 1"), 60_000, () => "not bound in 60 s");
  });
  await must("A removes C from alice's own lock (bound once C was on it)", async () => {
    await a.call("adb.personalRemove", { sub, key: cKey });
    await a.personal((p) => p.devices.length === 1, 60_000);
  });
  await check("C, taken off alice's own lock, is taken out of the workspace's", async () => {
    const l = await a.lock(workspace, (l) => !lockDevices(l).some((d) => d.id === cBase), 90_000);
    log(`  A sees app devices: ${appIds(l)}`);
  });
  await check("the station refuses C", async () => log(`  C sees: ${short(await c.stationState(workspace, (s) => s.state !== "online", 90_000))}`));
  await check("C can no longer open the item", () => refusedVault(c));
  await check("A's vault keyed anew without C (its key in hand: nobody asked)", () => aStill("C taken out"));

  // ── B joins the own lock face to face, is put in the workspace's lock and given the vault ──
  await b.signIn();
  let bKey = "";
  await must("B joins alice's own lock face to face with A", async () => {
    bKey = await join(b);
  });
  await check("B let in, in the workspace's lock signing, given the vault, opens the item", async () => {
    await b.stationState(workspace, (s) => s.state === "online", 90_000);
    await b.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await b.call("vault.setup", { workspace });
    await keyedFor(b);
    await opens(b);
  });

  // ── B taken off by A, A's vault key not in hand: keyed anew all the same, the person asked ──
  await must("A removes B from alice's own lock, the vault locked on A first", async () => {
    await a.call("vault.lock", { workspace });
    await a.call("adb.personalRemove", { sub, key: bKey });
    await a.personal((p) => p.devices.length === 1, 60_000);
  });
  await check("B gone from the workspace's lock, refused by the station and by the vault", async () => {
    await a.lock(workspace, (l) => appIds(l).length === 1, 90_000);
    log(`  B sees: ${short(await b.stationState(workspace, (s) => s.state !== "online", 90_000))}`);
    await refusedVault(b);
  });
  await check("A's vault keyed anew without B (its key read with the box key)", () => aStill("B taken off"));

  // ── B back again: a new key given it ──
  await must("B joins alice's own lock again", async () => {
    bKey = await join(b);
  });
  await check("B let in again and given the vault's new key, opens the item", async () => {
    await b.stationState(workspace, (s) => s.state === "online", 90_000);
    await b.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await keyedFor(b);
    await opens(b);
  });
  await check("A still let in and opens the item", async () => {
    await a.stationState(workspace, (s) => s.state === "online");
    await opens(a);
    log(`  A's own lock: ${JSON.stringify((await a.personal(() => true)).devices.map((d: J) => d.key.slice(8, 16)))}; workspace lock apps ${appIds(await a.lock(workspace, () => true))} (A ${aBase.slice(0, 8)})`);
  });

  // ── D approved by B (not A): any device on the own lock lets one in, and puts it in the workspace's lock ──
  await d.signIn();
  await must("D joins alice's own lock face to face with B", async () => {
    const shown = b.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await d.call("adb.personalJoin", { sub });
    const p = await shown;
    log(`  B shows ${p.code}`);
    await d.call("adb.personalCode", { code: p.code });
    dKey = (await d.personal((p) => p.standing === "member", 90_000)).devices.find((x: J) => x.me)?.key;
  });
  dBase = await baseOf(d);
  await check("D let in, in the workspace's lock signing, given the vault, opens the item", async () => {
    await d.stationState(workspace, (s) => s.state === "online", 90_000);
    await d.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await d.call("vault.setup", { workspace });
    await keyedFor(d);
    await opens(d);
  });

  // ── B's app started anew: still on the locks, let in, its vault opened ──
  await b.restart();
  await check("B started anew: on the own lock, let in, opens the item", async () => {
    await b.personal((p) => p.standing === "member", 60_000);
    await b.stationState(workspace, (s) => s.state === "online", 90_000);
    await opens(b);
  });

  // ── the station started anew: those on the lock let in again, C still refused ──
  await check("the station started anew: A, B and D let in again, the item opened on each", async () => {
    stationDo("freeze");
    stationDo("thaw");
    for (const x of [a, b, d]) await x.stationState(workspace, (s) => s.state === "online", 120_000);
    for (const x of [a, b, d]) await opens(x);
  });
  await check("C still refused by the station started anew", async () => {
    await c.restart();
    const st = await c.stationState(workspace, (s) => s.cause === "lock" || (s.state !== "online" && s.state !== "connecting"), 90_000);
    log(`  C sees: ${short(st)}`);
  });

  // ── D taken off while the station is away: refused once it is back ──
  await must("A removes D from alice's own lock while the station is frozen", async () => {
    stationDo("freeze");
    await a.call("adb.personalRemove", { sub, key: dKey });
    await a.personal((p) => p.devices.length === 2, 60_000);
  });
  await check("the station back: D refused, gone from the workspace's lock, the vault keyed anew for A and B", async () => {
    stationDo("thaw");
    await a.lock(workspace, (l) => !lockDevices(l).some((x) => x.id === dBase), 120_000);
    log(`  D sees: ${short(await d.stationState(workspace, (s) => s.state !== "online", 120_000))}`);
    await refusedVault(d);
    await aStill("D taken off with the station away");
    await keyedFor(b);
    await opens(b);
  });

  // ── B taken off while its app is closed: refused as it starts again ──
  await must("A removes B while B's app is closed", async () => {
    await b.close();
    await a.call("adb.personalRemove", { sub, key: bKey });
    await a.personal((p) => p.devices.length === 1, 60_000);
    await a.lock(workspace, (l) => appIds(l).length === 1, 90_000);
  });
  await check("B started again: refused by the station, off the own lock, no vault", async () => {
    await b.restart();
    log(`  B sees: ${short(await b.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    const p = await b.personal((p) => p.standing !== "member", 60_000);
    log(`  B's own lock standing: ${p.standing}`);
    await refusedVault(b);
  });
  await check("A, the last on the own lock, still let in and opens the item", async () => {
    await aStill("B taken off while closed");
  });

  // ── round 4: the first device taken off by another; the last one left cannot go ──
  const joinVia = async (approver: Device, d: Device) => {
    const t1 = Date.now();
    const shown = approver.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await d.call("adb.personalJoin", { sub: approver.sub });
    const p = await shown;
    log(`  ${approver.name} shows ${JSON.stringify(p).slice(0, 300)} after ${Date.now() - t1} ms`);
    await d.call("adb.personalCode", { code: p.code });
    return (await d.personal((p) => p.standing === "member", 90_000)).devices.find((x: J) => x.me)?.key as string;
  };
  let bKey3 = "";
  await must("B joins alice's own lock once more, face to face with A", async () => {
    bKey3 = await joinVia(a, b);
  });
  await check("B let in, given the vault, opens the item", async () => {
    await b.stationState(workspace, (s) => s.state === "online", 90_000);
    await b.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await keyedFor(b);
    await opens(b);
  });
  const aKey = (await a.personal((p) => p.standing === "member")).devices.find((x: J) => x.me)?.key as string;
  await must("B takes A, the first device, off alice's own lock", async () => {
    await b.call("adb.personalRemove", { sub, key: aKey });
    await b.personal((p) => p.devices.length === 1, 60_000);
  });
  await check("A refused by the station, out of the workspace's lock, no vault", async () => {
    log(`  A sees: ${short(await a.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    await refusedVault(a);
  });
  await check("B, the one left, keys the vault anew without A and opens the item", async () => {
    const t1 = Date.now();
    const v = await b.until({ topic: "vaults", workspace }, (v) => (v?.vaults ?? []).find((x: J) => x.id === vault && x.keyed), 60_000);
    log(`  B's vault back after ${Date.now() - t1} ms (${v.devices} devices hold its key)`);
    await b.stationState(workspace, (s) => s.state === "online", 60_000);
    await opens(b);
  });
  await check("B, the last on alice's own lock, cannot take itself off, and still opens the item", async () => {
    const r = await b.call("adb.personalRemove", { sub, key: bKey3 }).then(() => null, (e) => e as Error);
    if (r === null) throw new Error("the last device was taken off");
    log(`  B told: ${r.message.slice(0, 200)}`);
    const p = await b.personal((p) => p.standing === "member");
    if (p.devices.length !== 1) throw new Error(`devices: ${p.devices.length}`);
    await opens(b);
  });

  // ── round 5: A's app installed anew (its data and keys gone): a new device, let in only as it joins again ──
  await a.close();
  await e.signIn();
  await check("A installed anew, before it joins: refused by the station, no vault", async () => {
    log(`  E sees: ${short(await e.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    const o = await e.call("vault.open", { workspace, item }).then((o) => o, (x) => x as Error);
    if (!(o instanceof Error)) throw new Error(`opened: ${JSON.stringify(o)?.slice(0, 200)}`);
  });
  await must("A installed anew joins alice's own lock face to face with B", async () => {
    await joinVia(b, e);
  });
  await check("A installed anew let in, in the workspace's lock signing, given the vault, opens the item", async () => {
    await e.stationState(workspace, (s) => s.state === "online", 90_000);
    await e.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await e.call("vault.setup", { workspace });
    await keyedFor(e);
    await opens(e);
  });
  await check("C and D still refused by the station started anew; A installed anew and B let in again", async () => {
    stationDo("freeze");
    stationDo("thaw");
    for (const x of [c, d]) {
      await x.restart();
      log(`  ${x.name} sees: ${short(await x.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    }
    await e.stationState(workspace, (s) => s.state === "online", 90_000);
    await opens(e);
    await opens(b);
  });

  // ── round 6: the cloud frozen (it answers nothing) while a device is let in and taken off: the stations carry the
  // locks (the root AGENTS.md, The cloud is the account system) ──
  await f.signIn();
  await check("F, not on the lock yet, refused by the station", async () => {
    log(`  F sees: ${short(await f.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
  });
  stationDo("cloud-freeze");
  let fKey = "";
  let fBase = "";
  await must("with the cloud frozen, F joins alice's own lock face to face with B", async () => {
    const t1 = Date.now();
    fKey = await joinVia(b, f);
    log(`  joined in ${Date.now() - t1} ms`);
  });
  await check("with the cloud frozen, F let in, in the workspace's lock signing, given the vault, opens the item", async () => {
    const t1 = Date.now();
    await f.stationState(workspace, (s) => s.state === "online", 90_000);
    log(`  F let in after ${Date.now() - t1} ms`);
    fBase = await baseOf(f);
    await f.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await f.call("vault.setup", { workspace });
    await keyedFor(f);
    await opens(f);
  });
  await check("with the cloud frozen, A installed anew hears of the station that F joined", async () => {
    await e.personal((p) => p.devices.length === 3, 60_000);
  });
  await must("with the cloud frozen, B takes F off alice's own lock", async () => {
    await b.call("adb.personalRemove", { sub, key: fKey });
    await b.personal((p) => p.devices.length === 2, 60_000);
  });
  await check("with the cloud frozen, F refused and out of the vault; B and A installed anew still open the item", async () => {
    await b.lock(workspace, (l) => !lockDevices(l).some((x) => x.id === fBase), 90_000);
    log(`  F sees: ${short(await f.stationState(workspace, (s) => s.state !== "online", 120_000))}`);
    await refusedVault(f);
    await e.personal((p) => p.devices.length === 2, 60_000);
    await keyedFor(b);
    await opens(b);
    await opens(e);
  });
  stationDo("cloud-thaw");
  await check("the cloud back: F still refused; B and A installed anew let in and open the item", async () => {
    await f.restart();
    log(`  F sees: ${short(await f.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    for (const x of [b, e]) {
      await x.stationState(workspace, (s) => s.state === "online", 90_000);
      await opens(x);
    }
  });

  // ── round 7: a second station in the lock. The stations keep each other level in alice's own lock (person-sync.ts):
  // with the first one frozen, G joins through the second; the first, back, hears it of the second ──
  const stationIn = (x: Device, id: string, ok: (s: J) => boolean, ms = 60_000) =>
    x.until({ topic: "chats", scope: workspace, mine: false, limit: 5 }, (v) => {
      const s = (v?.stations ?? []).find((s: J) => JSON.stringify(s).includes(id));
      return s && ok(s) ? s : undefined;
    }, ms);
  const chainsAt = (data: string): number => {
    try {
      const kept = JSON.parse(readFileSync(`${data}/mesh/person-chains.json`, "utf8"));
      const chains = (kept.chains ?? kept) as Record<string, J[]>;
      return Math.max(0, ...Object.values(chains).filter((c) => c[0]?.ws === `person:${sub}`).map((c) => c.length));
    } catch {
      return 0;
    }
  };
  const atLength = async (data: string, n: number, ms = 60_000) => {
    await whenChanged([data], () => chainsAt(data) >= n, ms, () => `${data}: alice's own lock ${chainsAt(data)} long, not ${n}`);
  };
  const first = `${process.env.E2E_STATION}/data`;
  const second = `${process.env.E2E_STATION}-b/data`;
  let secondId = "";
  await must("A installed anew enrolls a second station with the lock's hash and takes it into the lock by its code", async () => {
    const made = await e.call("workspace.enroll", { account: sub, workspace, name: "second" });
    const at = `${dir}/enroll.log`;
    writeFileSync(at, `ANSWER workspace.enroll ok ${JSON.stringify(made)}\n`);
    stationDo("second-station", at);
    const said = readFileSync(`${process.env.E2E_WORK}/run/second-enroll.log`, "utf8");
    const code = said.match(/(?:code|安全码为)\s*([0-9A-Z-]{4,})/i)?.[1];
    if (!code) throw new Error(`no code in: ${said}`);
    const w = await e.until({ topic: "workspace", workspace }, (v) => (v?.stations ?? []).find((s: J) => s.id !== station.split("/")[1]), 60_000);
    secondId = w.id;
    log(`  second station ${secondId.slice(0, 12)}, code ${code}`);
    await e.call("lock.addStation", { workspace, station: secondId, code });
    await e.lock(workspace, (l) => JSON.stringify(l).includes(secondId), 60_000);
  });
  await check("B and A installed anew let in by the second station too", async () => {
    for (const x of [b, e]) log(`  ${x.name} sees the second: ${short(await stationIn(x, secondId, (s) => s.state === "online", 120_000))}`);
  });
  const n = chainsAt(first);
  await check(`the second station hears alice's own lock of the first (${n} long)`, async () => {
    await atLength(second, n);
  });
  stationDo("freeze");
  let gKey = "";
  await g.signIn().catch((x) => log(`  G signs in: ${x}`));
  await check("with the first station frozen, G, not on the lock yet, refused by the second", async () => {
    log(`  G sees the second: ${short(await stationIn(g, secondId, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
  });
  await must("with the first station frozen, G joins alice's own lock face to face with B", async () => {
    const t1 = Date.now();
    gKey = await joinVia(b, g);
    log(`  joined in ${Date.now() - t1} ms`);
  });
  await check("with the first station frozen, the second keeps G on alice's own lock; A installed anew hears it", async () => {
    await atLength(second, n + 1);
    await e.personal((p) => p.devices.length === 3, 60_000);
  });
  await check("with the first station frozen, G let in by the second, in the workspace's lock signing, set up for the vault", async () => {
    const t1 = Date.now();
    await stationIn(g, secondId, (s) => s.state === "online", 90_000);
    log(`  G let in after ${Date.now() - t1} ms`);
    await g.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    const t2 = Date.now();
    await g.call("vault.setup", { workspace });
    log(`  G set up in ${Date.now() - t2} ms`);
  });
  stationDo("thaw");
  await check("the first station back hears G of the second: G let in by it too, given the vault (written on the first), opens the item", async () => {
    await atLength(first, n + 1, 90_000);
    log(`  G sees the first: ${short(await stationIn(g, station.split("/")[1], (s) => s.state === "online", 120_000))}`);
    const t1 = Date.now();
    await keyedFor(g);
    log(`  G given the vault's key after ${Date.now() - t1} ms`);
    await opens(g);
  });
  stationDo("freeze");
  await must("with the first station frozen, B takes G off alice's own lock", async () => {
    await b.call("adb.personalRemove", { sub, key: gKey });
    await b.personal((p) => p.devices.length === 2, 60_000);
  });
  await check("with the first station frozen, the second refuses G; G out of the vault", async () => {
    await atLength(second, n + 2);
    log(`  G sees the second: ${short(await stationIn(g, secondId, (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    await refusedVault(g);
  });
  stationDo("thaw");
  await check("the first station back hears G was taken off: it refuses G; B and A installed anew open the item", async () => {
    await atLength(first, n + 2, 90_000);
    await g.restart();
    log(`  G sees the first: ${short(await stationIn(g, station.split("/")[1], (s) => s.state !== "online" && s.state !== "connecting", 120_000))}`);
    for (const x of [b, e]) {
      await x.stationState(workspace, (s) => s.state === "online", 90_000);
      await opens(x);
    }
  });
  // C, D, F and G were taken off and have no more part: closed, as such a device mostly is. Each device of alice's reads
  // her account again on every change to her workspaces (a member, a station, a workspace), and still.fail cloud gives
  // an account 120 requests a minute (account.ts): nine of them running through rounds 8 and 9 use it up.
  await within(Promise.all([c, d, f, g].map((x) => x.close())), 5000);
  // (round 9's devices' ids, as the workspace's lock has them: a device's id is its own, the same in each workspace)
  const bId = await baseOf(b);
  const eId = await baseOf(e);
  // ── round 8: a second person, bob, a member: his first device let into the workspace's lock by the owner face to
  // face, a vault of his own; his own lock opened and bound, his second device joining it; then the owner takes him
  // out of the workspace: the cloud's to say (members are the account system's), his devices refused ──
  let bobVault = "";
  let bobItem = "";
  const bobSecret = `ghp_bob_${Date.now()}`;
  const bobOpens = async (x: Device) => {
    const o = await x.call("vault.open", { workspace, item: bobItem });
    if (o?.plain?.fields?.value !== bobSecret) throw new Error(`${x.name} opened: ${JSON.stringify(o)?.slice(0, 300)}`);
  };
  await must("B adds bob to the workspace", async () => {
    const r = await b.call("workspace.addMembers", { account: sub, workspace, role: "member", emails: ["bob@example.test"] });
    log(`  added: ${JSON.stringify(r)?.slice(0, 200)}`);
  });
  await h.signIn();
  await must("bob's first device H, not in the workspace's lock, refused; B approves it face to face", async () => {
    log(`  H sees the first: ${short(await h.stationState(workspace, (s) => s.cause === "lock", 90_000))}`);
    await h.lock(workspace, (l) => l.me?.waiting, 60_000);
    const shown = b.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await h.call("lock.pair", { workspace });
    const p = await shown;
    await h.call("lock.pairCode", { workspace, code: p.code });
    await h.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await h.stationState(workspace, (s) => s.state === "online", 90_000);
  });
  await must("H sets up the vault, keeps an item in a vault of bob's own, opens it", async () => {
    await h.call("vault.setup", { workspace });
    await h.until({ topic: "vaults", workspace }, (v) => v?.setUp, 60_000);
    bobVault = (await h.call("vault.create", { workspace, name: "bob", station: station.split("/")[1] })).id;
    bobItem = (await h.call("vault.putItem", {
      workspace, vault: bobVault,
      plain: { kind: "token", name: "bob-token", fields: { value: bobSecret }, domains: [], notes: "" },
      listing: { name: "bob-token", kind: "token", modes: ["proxy"], hosts: ["api.example.test"] },
    })).id;
    await bobOpens(h);
  });
  await check("alice's devices do not open bob's item; B still opens alice's", async () => {
    const o = await b.call("vault.open", { workspace, item: bobItem }).then((o) => o, (x) => x);
    if (!(o instanceof Error)) throw new Error(`B opened bob's item: ${JSON.stringify(o)?.slice(0, 200)}`);
    await opens(b);
  });
  await must("H opens bob's own lock", async () => {
    await h.call("adb.personalOpen", { sub: h.sub });
    await h.personal((p) => p.standing === "member");
  });
  await check("bob bound to his own lock in the workspace's lock (the station's: two persons); H still let in", async () => {
    let said = "";
    await whenChanged([stationData], () => /^PERSONS 2$/m.test((said = stationSays("lock-state"))), 60_000, () => `the station's lock: ${said.trim().split("\n").slice(-4).join("; ")}`);
    await h.stationState(workspace, (s) => s.state === "online", 60_000);
    await bobOpens(h);
  });
  await i.signIn();
  await check("bob's second device I, not on his own lock, refused", async () => {
    log(`  I sees the first: ${short(await i.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 90_000))}`);
  });
  await must("I joins bob's own lock face to face with H", async () => {
    await joinVia(h, i);
  });
  await check("I let in, in the workspace's lock signing, given bob's vault, opens his item", async () => {
    const t1 = Date.now();
    await i.stationState(workspace, (s) => s.state === "online", 90_000);
    log(`  I let in after ${Date.now() - t1} ms`);
    await i.lock(workspace, (l) => l.signs && l.me?.confirmed, 90_000);
    await i.call("vault.setup", { workspace });
    await i.until({ topic: "vaults", workspace }, (v) => (v?.vaults ?? []).find((x: J) => x.id === bobVault && x.keyed), 90_000);
    await bobOpens(i);
  });
  await check("alice's own lock untouched by bob's: B and A installed anew still let in, open alice's item", async () => {
    for (const x of [b, e]) {
      await x.stationState(workspace, (s) => s.state === "online", 60_000);
      await opens(x);
    }
  });
  await must("B takes bob out of the workspace", async () => {
    await b.call("workspace.removeMember", { account: sub, workspace, member: h.sub });
  });
  /// Out of the workspace as the device has it: the workspace gone from its list (the cloud's, the account system's),
  /// or its station refusing it, whichever it hears first.
  const out = (x: Device, ms: number) => Promise.any([
    x.until({ topic: "workspaces" }, (v) => (v ?? []).every((a: J) => !(a.workspaces ?? []).some((w: J) => w.id === workspace)) ? "the workspace gone from its list" : undefined, ms),
    x.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", ms).then(short),
  ]).catch((x: AggregateError) => Promise.reject(x.errors[0]));
  await check("bob out of the workspace's lock too, his devices with him: the cloud alone does not keep him out", async () => {
    let said = "";
    await whenChanged([stationData], () => !/^DEVICE \S+ bob /m.test((said = stationSays("lock-state"))), 60_000, () => `the station's lock: ${said.trim().split("\n").filter((l) => l.startsWith("DEVICE")).join("; ")}`);
  });
  await check("bob's devices H and I out once he is: the workspace gone, its station refusing them", async () => {
    for (const x of [h, i]) {
      const t1 = Date.now();
      log(`  ${x.name}: ${await out(x, 60_000)} after ${Date.now() - t1} ms`);
    }
  });
  await check("bob out: a device of his started anew is out too", async () => {
    await i.restart();
    log(`  I: ${await out(i, 60_000)}`);
  });
  await check("alice's devices go on: B and A installed anew let in, open alice's item", async () => {
    for (const x of [b, e]) {
      await x.stationState(workspace, (s) => s.state === "online", 60_000);
      await opens(x);
    }
  });
  // ── round 9: a second workspace of alice's, safe mode on there too, its own station: alice's own lock bound in both;
  // a new device joining it once is let in by both, taken off it once is refused by both ──
  let two = "";
  let third = "";
  await must("A installed anew makes a second workspace and enrolls a station of its own in it", async () => {
    two = (await e.call("workspace.create", { account: sub, name: "Two" })).id;
    const made = await e.call("workspace.enroll", { account: sub, workspace: two, name: "third" });
    const at = `${dir}/enroll-two.log`;
    writeFileSync(at, `ANSWER workspace.enroll ok ${JSON.stringify(made)}\n`);
    stationDo("second-station", at, "third");
    third = (await e.until({ topic: "workspace", workspace: two }, (v) => (v?.stations ?? [])[0], 60_000)).id;
    await e.stationState(two, (s) => s.state === "online", 120_000);
  });
  await must("A installed anew turns safe mode on in it, with B and itself, the two on alice's own lock", async () => {
    const draft = await e.until({ topic: "lockDraft", workspace: two }, (v) => (v?.ready ? v : undefined), 120_000);
    log(`  the draft's devices: ${(draft.devices ?? []).map((d: J) => `${d.id.slice(0, 8)}${d.on === false ? " (off)" : ""}`).join(", ")}`);
    for (const d of draft.devices ?? []) if (d.id !== bId && d.id !== eId && d.on !== false) await e.call("lock.toggle", { workspace: two, id: d.id });
    await e.call("lock.open", { workspace: two });
    await e.lock(two, (l) => l.locked && l.signs);
    await e.stationState(two, (s) => s.state === "online");
  });
  await check("alice's own lock bound in the second workspace too; B let in there, signing", async () => {
    await b.stationState(two, (s) => s.state === "online", 90_000);
    await b.lock(two, (l) => l.signs && l.me?.confirmed, 90_000);
    const at = `${process.env.E2E_STATION}-third/data`;
    const persons = () => { try { return readFileSync(`${at}/mesh/person-chains.json`, "utf8"); } catch { return ""; } };
    await whenChanged([at], () => persons().includes(`person:${sub}`), 60_000, () => `the third station keeps no lock of alice's: ${persons().slice(0, 200)}`);
  });
  await j.signIn();
  await check("a new device J, not on alice's own lock, refused in both workspaces", async () => {
    for (const ws of [workspace, two]) log(`  J in ${ws === two ? "Two" : "Dev"}: ${short(await j.stationState(ws, (s) => s.state !== "online" && s.state !== "connecting", 90_000))}`);
  });
  let jKey = "";
  // (as a person does it on a new phone: 发送批准请求 on the page that waits in the workspace, not the settings' 个人锁.
  // Approved into the workspace's lock that way, as it was before, every station went on refusing it: 2026-11-10)
  await must("J asks from the page that waits in Dev: it joins alice's own lock, face to face with B", async () => {
    const me = (await j.lock(workspace, (l) => l.me?.waiting && l.me?.ownLock, 60_000)).me;
    log(`  J's page in Dev: ${JSON.stringify({ waiting: me.waiting, ownLock: me.ownLock, pair: me.pair?.state ?? null })}`);
    const shown = b.until({ topic: "lockPrompts" }, (v) => v?.pairing?.[0], 90_000);
    await j.call("lock.pair", { workspace });
    const p = await shown;
    await j.lock(workspace, (l) => l.me?.pair?.state === "code", 60_000);
    await j.call("lock.pairCode", { workspace, code: p.code });
    jKey = (await j.personal((p) => p.standing === "member", 90_000)).devices.find((x: J) => x.me)?.key as string;
  });
  await check("J let in by both workspaces' stations, in both workspaces' locks signing", async () => {
    for (const ws of [workspace, two]) {
      const t1 = Date.now();
      await j.stationState(ws, (s) => s.state === "online", 90_000);
      await j.lock(ws, (l) => l.signs && l.me?.confirmed, 90_000);
      log(`  J in ${ws === two ? "Two" : "Dev"} after ${Date.now() - t1} ms`);
    }
  });
  await must("B takes J off alice's own lock", async () => {
    await b.call("adb.personalRemove", { sub, key: jKey });
    await b.personal((p) => !p.devices.some((x: J) => x.key === jKey), 60_000);
  });
  await check("J refused by both workspaces' stations, out of both workspaces' locks", async () => {
    for (const ws of [workspace, two]) {
      log(`  J in ${ws === two ? "Two" : "Dev"}: ${short(await j.stationState(ws, (s) => s.state !== "online" && s.state !== "connecting", 90_000))}`);
      await j.lock(ws, (l) => !l.signs, 60_000);
    }
  });
  await check("B and A installed anew still let in by both, alice's item opened", async () => {
    for (const x of [b, e]) {
      for (const ws of [workspace, two]) await x.stationState(ws, (s) => s.state === "online", 60_000);
      await opens(x);
    }
  });
  // ── round 10: safe mode turned off in the second workspace by its owner: its station lets in any device of its
  // members again, J too; the first workspace's lock, and alice's own lock bound there, still keep J out ──
  await must("A installed anew turns safe mode off in Two", async () => {
    await e.call("lock.disable", { workspace: two });
    await e.lock(two, (l) => !l.locked, 60_000);
  });
  await check("J, off alice's own lock, let in by Two's station now; still refused in Dev", async () => {
    const t1 = Date.now();
    await j.stationState(two, (s) => s.state === "online", 90_000);
    log(`  J in Two after ${Date.now() - t1} ms`);
    log(`  J in Dev: ${short(await j.stationState(workspace, (s) => s.state !== "online" && s.state !== "connecting", 30_000))}`);
  });
  await check("B and A installed anew go on in both", async () => {
    for (const x of [b, e]) for (const ws of [workspace, two]) await x.stationState(ws, (s) => s.state === "online", 60_000);
    await opens(b);
  });
  // ── round 11: the second station of round 7 taken out of the first workspace by alice: out of its lock too, by her
  // device's signature, not the cloud's word alone; the first station and her devices go on ──
  await must("B takes the second station out of Dev", async () => {
    await b.call("workspace.removeStation", { account: sub, workspace, station: secondId });
  });
  await check("the first station's lock names it no more", async () => {
    let said = "";
    await whenChanged([stationData], () => /^STATIONS 1$/m.test((said = stationSays("lock-state"))), 60_000, () => `the station's lock: ${said.trim().split("\n").slice(-3).join("; ")}`);
  });
  await check("B and A installed anew go on in Dev, alice's item opened", async () => {
    for (const x of [b, e]) {
      await x.stationState(workspace, (s) => s.state === "online", 60_000);
      await opens(x);
    }
  });
} catch (e) {
  fail("the run", e);
}
log(failed === 0 ? "ALL PASSED" : `${failed} FAILED`);
await within(Promise.all([a, b, c, d, e, f, g, h, i, j].map((x) => x.close())), 5000);
process.exit(failed === 0 ? 0 : 1);
