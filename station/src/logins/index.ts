// The station's logins to the command-line tools its agents use (docs/remote-login.md): each station logs in itself,
// the login landing in its own user's home and keychain (machine-wide: every chat's agent uses it); a person finishes it
// from their client, in their own browser. Here: the services it knows (built in, and those agents described), how each
// stands (its status command, asked when the list is first read, after each login, and when read again past 5 minutes:
// never on a timer), the logins under way and ended lately, and who logged in through still.fail.
import { execFile } from "node:child_process";
import { mkdirSync, readFileSync, readdirSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { Clock } from "effect";
import { Fibers } from "../ops/fibers.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";
import { BUILTIN, type Description, type Flow, checked } from "./builtin.ts";
import { commandWords, domainOf } from "./parse.ts";
import { type Answered, type Callback, Refused, relay } from "./relay.ts";
import { type Key, KEYS, LoginRun, type Screen } from "./run.ts";

export { Refused };

/// A status read this long ago is read again when the list is.
const STALE_MS = 5 * 60_000;
/// A status command's time.
const STATUS_MS = 10_000;
/// An ended login (and its screen) is kept this long.
const KEPT_MS = 10 * 60_000;
/// How many ended logins are kept at most.
const KEPT_MOST = 20;

export type Person = { email: string; name: string };
/// Who started a login: a person (from their client, in a workspace), or an agent (its session, in its chat's workspace).
export type Starter = { by: Person; workspace: string | null; chat?: string | null };

export type ServiceState = "in" | "out" | "unknown";
export type Service = {
  id: string;
  name: string;
  installed: boolean;
  state: ServiceState;
  account?: string;
  by?: Person;
  at?: number;
  checkedAt?: number;
  flow: Flow;
  builtin: boolean;
  /// Its login under way.
  login?: string;
};

export type Login = {
  id: string;
  service?: string;
  name: string;
  command: string[];
  state: string;
  step?: string;
  url?: string;
  domain?: string;
  /// Loopback: where the browser comes back to (`state` the page's: a client relays only that callback).
  callback?: { host: string; port: number; path: string; state: string | null; post: boolean };
  code?: string;
  codeUrl?: string;
  waiting: boolean;
  by: Person;
  workspace?: string;
  chat?: string;
  startedAt: number;
  expiresAt: number;
  endedAt?: number;
  error?: string;
  /// Failed for want of time.
  timedOut?: boolean;
  account?: string;
  /// Who was logged in when it began.
  before?: { account?: string; by?: Person; at?: number };
};

type Kept = { by: Person; workspace: string | null; chat: string | null; at: number; account: string | null };
type Entry = { run: LoginRun; service: Description | null; starter: Starter; before: Login["before"]; screens: Set<(screen: Screen) => void> };

export type LoginsOptions = {
  data: string;
  /// The environment logins and status commands run in (the station's: the same home and keychain its agents use).
  env?: () => Record<string, string>;
  clock?: Clock.Clock;
  lang?: () => Lang;
};

export class Logins {
  readonly #data: string;
  readonly #env: () => Record<string, string>;
  readonly #fibers: Fibers;
  readonly #lang: () => Lang;
  readonly #entries = new Map<string, Entry>();
  readonly #status = new Map<string, Pick<Service, "state" | "account" | "checkedAt">>();
  readonly #listeners = new Set<(change: { login?: string; service?: string }) => void>();
  readonly #ended = new Set<(login: Login, starter: Starter) => void>();
  /// The logins whose end was told (once each).
  readonly #endedOnce = new Set<string>();
  #checking: Promise<void> | null = null;
  #checkedAt: number | null = null;
  #next = 0;

  constructor(o: LoginsOptions) {
    this.#data = o.data;
    this.#env = o.env ?? (() => Object.fromEntries(Object.entries(process.env).filter((e): e is [string, string] => e[1] !== undefined && !SCRUBBED.includes(e[0]))));
    this.#fibers = new Fibers("logins", o.clock);
    this.#lang = o.lang ?? stationLang;
  }

  // ── what is told ──

  /// Hears what changed: a login (its id) or a service (its id).
  changes(listener: (change: { login?: string; service?: string }) => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  /// Hears each login that ends (done, failed, cancelled), with who started it.
  onEnded(listener: (login: Login, starter: Starter) => void): () => void {
    this.#ended.add(listener);
    return () => this.#ended.delete(listener);
  }

  #tell(change: { login?: string; service?: string }) {
    for (const l of this.#listeners) {
      try {
        l(change);
      } catch (e) {
        log.warn("logins", "a listener failed", { error: (e as Error).message });
      }
    }
  }

  // ── services ──

  /// The descriptions: the built-in ones, each replaced by an agent's of the same id, then the agents' own.
  descriptions(): Description[] {
    const own = new Map<string, Description>();
    const dir = join(this.#data, "logins", "services");
    let names: string[] = [];
    try {
      names = readdirSync(dir).filter((n) => n.endsWith(".json"));
    } catch {}
    for (const name of names.sort()) {
      try {
        const d = checked(JSON.parse(readFileSync(join(dir, name), "utf8")));
        own.set(d.id, d);
      } catch (e) {
        log.warn("logins", "a service description is not read", { file: name, error: (e as Error).message });
      }
    }
    return [...BUILTIN.map((b) => own.get(b.id) ?? b), ...[...own.values()].filter((d) => !BUILTIN.some((b) => b.id === d.id))];
  }

  description(id: string): Description | null {
    return this.descriptions().find((d) => d.id === id) ?? null;
  }

  /// A description an agent gives (or changes): kept, and the service's status read.
  describe(given: unknown): Service {
    const d = checked(given);
    const dir = join(this.#data, "logins", "services");
    mkdirSync(dir, { recursive: true });
    writeAtomic(join(dir, `${d.id}.json`), `${JSON.stringify(d, null, 2)}\n`);
    this.#status.delete(d.id);
    void this.#check([d]).catch(() => {});
    this.#tell({ service: d.id });
    return this.service(d)!;
  }

  services(): Service[] {
    return this.descriptions().map((d) => this.service(d)!);
  }

  service(d: Description | string): Service | null {
    const desc = typeof d === "string" ? this.description(d) : d;
    if (desc === null) return null;
    const env = this.#env();
    const installed = platform.findCommand(desc.bin, env) !== null;
    const status = this.#status.get(desc.id);
    const kept = this.#kept()[desc.id];
    const running = [...this.#entries.values()].find((e) => e.service?.id === desc.id && e.run.active);
    const state: ServiceState = !installed ? "out" : (status?.state ?? "unknown");
    // Who logged in through still.fail: said while the account is the one they logged in (or none is told).
    const byKept = kept && state === "in" && (status?.account === undefined || kept.account === null || kept.account === status.account);
    return {
      id: desc.id,
      name: desc.name,
      installed,
      state,
      ...(status?.account ? { account: status.account } : {}),
      ...(byKept ? { by: kept.by, at: kept.at } : {}),
      ...(status?.checkedAt !== undefined ? { checkedAt: status.checkedAt } : {}),
      flow: desc.login.flow,
      builtin: BUILTIN.some((b) => b.id === desc.id),
      ...(running ? { login: running.run.id } : {}),
    };
  }

  /// The list as a page reads it: the statuses read first when never read, else again (in the background) once stale.
  async list(): Promise<{ services: Service[]; logins: Login[] }> {
    if (this.#checkedAt === null) await this.refresh();
    else if (this.#fibers.now() - this.#checkedAt >= STALE_MS) void this.refresh().catch(() => {});
    return { services: this.services(), logins: this.logins() };
  }

  /// Every installed service's status read again (one reading at a time).
  refresh(): Promise<void> {
    if (this.#checking) return this.#checking;
    this.#checking = this.#check(this.descriptions()).finally(() => {
      this.#checking = null;
      this.#checkedAt = this.#fibers.now();
    });
    return this.#checking;
  }

  /// Statuses read: each told as it changes.
  async #check(descriptions: Description[]): Promise<void> {
    const env = this.#env();
    await Promise.all(
      descriptions.map(async (d) => {
        if (platform.findCommand(d.bin, env) === null) return;
        const read = await this.#statusOf(d, env);
        const was = this.#status.get(d.id);
        this.#status.set(d.id, { ...read, checkedAt: this.#fibers.now() });
        if (was?.state !== read.state || was?.account !== read.account) this.#tell({ service: d.id });
      }),
    );
  }

  /// Whether the machine is logged in to `d`, and as whom: its status command, without a terminal.
  #statusOf(d: Description, env: Record<string, string>): Promise<{ state: ServiceState; account?: string }> {
    const [program, ...args] = d.status.command;
    const r = platform.runnable(program!, args, { ...env, ...(d.env ?? {}) });
    return new Promise((resolve) => {
      execFile(r.file, r.args, { env: { ...env, ...(d.env ?? {}) }, timeout: STATUS_MS, killSignal: "SIGKILL", windowsHide: true, windowsVerbatimArguments: r.windowsVerbatimArguments, maxBuffer: 1_000_000 }, (error, stdout, stderr) => {
        const said = `${stdout}\n${stderr}`;
        if (error && (error.killed || typeof error.code !== "number")) return resolve({ state: "unknown" });
        const exit = error ? (error.code as number) : 0;
        const exitOk = d.status.in.exit === undefined || d.status.in.exit === exit;
        let matched = true;
        if (d.status.in.match !== undefined) {
          try {
            matched = new RegExp(d.status.in.match, "m").test(said);
          } catch {
            matched = false;
          }
        }
        let account: string | undefined;
        if (exitOk && matched && d.status.account) {
          try {
            const m = new RegExp(d.status.account, "m").exec(String(stdout).trim() !== "" ? String(stdout) : said);
            account = m?.[1] ?? m?.[0];
          } catch {}
        }
        resolve(exitOk && matched ? { state: "in", ...(account ? { account: account.trim() } : {}) } : { state: "out" });
      });
    });
  }

  /// Who logged in to what through still.fail (`<data>/logins/state.json`).
  #kept(): Record<string, Kept> {
    try {
      const v = JSON.parse(readFileSync(join(this.#data, "logins", "state.json"), "utf8"));
      return v && typeof v === "object" ? v : {};
    } catch {
      return {};
    }
  }

  #keep(service: string, kept: Kept) {
    const dir = join(this.#data, "logins");
    mkdirSync(dir, { recursive: true });
    writeAtomic(join(dir, "state.json"), `${JSON.stringify({ ...this.#kept(), [service]: kept }, null, 2)}\n`);
  }

  // ── logins ──

  logins(): Login[] {
    this.#sweep();
    const all = [...this.#entries.values()];
    return [...all.filter((e) => e.run.active), ...all.filter((e) => !e.run.active).reverse()].map((e) => this.#shown(e));
  }

  get(id: string): Login | null {
    this.#sweep();
    const e = this.#entries.get(id);
    return e ? this.#shown(e) : null;
  }

  /// A login started: for a service it knows (one under way for it is given rather than another), or a command of its
  /// own (words, or a line split as a shell would). Throws Refused when it cannot be.
  async start(what: { service?: string | null; command?: string | string[] | null }, starter: Starter): Promise<Login> {
    const lang = this.#lang();
    let service: Description | null = null;
    let command: string[];
    if (what.service) {
      service = this.description(what.service);
      if (service === null) throw new Refused(404, tr(lang, "station.machineLogin.unknownService", { service: what.service }));
      const running = [...this.#entries.values()].find((e) => e.service?.id === service!.id && e.run.active);
      if (running) return this.#shown(running);
      if (platform.findCommand(service.bin, this.#env()) === null) throw new Refused(409, tr(lang, "station.machineLogin.notInstalled", { name: service.name, bin: service.bin }));
      command = service.login.command;
    } else {
      const words = Array.isArray(what.command) ? what.command : typeof what.command === "string" ? commandWords(what.command) : null;
      if (words === null || words.length === 0 || words.some((w) => typeof w !== "string") || words.join(" ").length > 2000) throw new Refused(400, tr(lang, "station.machineLogin.badCommand"));
      command = words;
      // A known service's own login command is that service's login.
      service = this.descriptions().find((d) => d.login.command.join("\0") === words.join("\0")) ?? null;
      const running = service && [...this.#entries.values()].find((e) => e.service?.id === service!.id && e.run.active);
      if (running) return this.#shown(running);
    }
    const id = `${this.#fibers.now().toString(36)}${(++this.#next).toString(36)}${Math.random().toString(36).slice(2, 6)}`;
    const dir = join(this.#data, "run", "logins");
    mkdirSync(dir, { recursive: true });
    const before = service ? this.service(service) : null;
    const entry: Entry = {
      service,
      starter,
      before: before && before.state === "in" ? { ...(before.account ? { account: before.account } : {}), ...(before.by ? { by: before.by, at: before.at } : {}) } : undefined,
      screens: new Set(),
      run: undefined as unknown as LoginRun,
    };
    entry.run = new LoginRun({
      id,
      command,
      env: this.#env(),
      cwd: platform.home(this.#env()) ?? this.#data,
      shims: this.#shims(),
      opened: join(dir, `${id}.opened`),
      description: service,
      fibers: this.#fibers,
      lang,
      changed: () => {
        this.#tell({ login: id });
        if (!entry.run.active) this.#endedNow(entry);
      },
      drawn: () => {
        const screen = entry.run.screen();
        for (const s of entry.screens) s(screen);
      },
      verify: async () => {
        if (!service) return null;
        await this.#check([service]);
        return this.#status.get(service.id)?.account ?? null;
      },
    });
    this.#entries.set(id, entry);
    if (service) this.#tell({ service: service.id });
    await entry.run.start();
    return this.#shown(entry);
  }

  #endedNow(entry: Entry) {
    const id = entry.run.id;
    if (this.#endedOnce.has(id)) return;
    this.#endedOnce.add(id);
    const service = entry.service;
    if (entry.run.state === "done" && service) {
      this.#keep(service.id, { by: entry.starter.by, workspace: entry.starter.workspace, chat: entry.starter.chat ?? null, at: entry.run.endedAt ?? this.#fibers.now(), account: entry.run.account });
    }
    if (service) {
      this.#tell({ service: service.id });
      // A failed or cancelled one may have changed it all the same.
      if (entry.run.state !== "done") void this.#check([service]).catch(() => {});
    }
    const shown = this.#shown(entry);
    for (const l of this.#ended) {
      try {
        l(shown, entry.starter);
      } catch (e) {
        log.warn("logins", "a listener failed", { error: (e as Error).message });
      }
    }
    // Let go of a while after (its screen with it).
    this.#fibers.after(KEPT_MS, () => {
      const e = this.#entries.get(id);
      if (e && !e.run.active) {
        e.run.close();
        this.#entries.delete(id);
        this.#endedOnce.delete(id);
      }
    });
  }

  /// Ended logins past what is kept: the oldest go.
  #sweep() {
    const ended = [...this.#entries.values()].filter((e) => !e.run.active);
    for (const e of ended.slice(0, Math.max(0, ended.length - KEPT_MOST))) {
      e.run.close();
      this.#entries.delete(e.run.id);
    }
  }

  #entry(id: string): Entry {
    const e = this.#entries.get(id);
    if (!e) throw new Refused(404, tr(this.#lang(), "station.machineLogin.unknown"));
    return e;
  }

  cancel(id: string): Login {
    const e = this.#entry(id);
    e.run.cancel();
    return this.#shown(e);
  }

  /// Typed into its terminal: `{text}` (with Enter when `enter`), or `{key}`.
  input(id: string, given: { text?: unknown; key?: unknown }): void {
    const e = this.#entry(id);
    if (!e.run.active) throw new Refused(409, tr(this.#lang(), "station.machineLogin.ended"));
    if (typeof given.key === "string") {
      if (!(given.key in KEYS)) throw new Refused(400, `key: one of ${Object.keys(KEYS).join(", ")}`);
      e.run.input({ key: given.key as Key });
    } else if (typeof given.text === "string") {
      if (given.text.length > 10_000) throw new Refused(413, "too much text");
      e.run.input({ text: given.text });
    } else throw new Refused(400, "text or key");
  }

  /// What a person pasted: the address the browser came back to (http://localhost…) is taken as its callback; anything
  /// else is typed in, with Enter.
  async paste(id: string, text: string): Promise<{ login: Login; answered?: Answered }> {
    const e = this.#entry(id);
    const t = text.trim();
    const back = /^http:\/\/(localhost|127\.0\.0\.1|\[::1\]):(\d+)(\/[^\s]*)?$/.exec(t);
    if (back !== null && e.run.loopback !== null) {
      const answered = await relay(e.run, { method: "GET", path: back[3] ?? "/", headers: { host: `${back[1]}:${back[2]}` } });
      return { login: this.#shown(e), answered };
    }
    this.input(id, { text: `${t}\r` });
    return { login: this.#shown(e) };
  }

  /// The browser's callback, from a person's client, relayed to the command.
  async callback(id: string, callback: Callback): Promise<Answered> {
    return relay(this.#entry(id).run, callback);
  }

  /// Its terminal: now, and each time it changes, until the returned function is called.
  follow(id: string, send: (screen: Screen) => void): () => void {
    const e = this.#entries.get(id);
    if (!e) return () => {};
    e.screens.add(send);
    send(e.run.screen());
    return () => e.screens.delete(send);
  }

  /// A login as clients have it (Logins.limited: as a read-only member may see it).
  #shown(e: Entry): Login {
    const r = e.run;
    const name = e.service?.name ?? r.command[0]?.split(/[\\/]/).at(-1) ?? "";
    const login: Login = {
      id: r.id,
      ...(e.service ? { service: e.service.id } : {}),
      name,
      command: r.command,
      state: r.state,
      ...(r.step ? { step: r.step } : {}),
      waiting: r.waiting,
      by: e.starter.by,
      ...(e.starter.workspace ? { workspace: e.starter.workspace } : {}),
      ...(e.starter.chat ? { chat: e.starter.chat } : {}),
      startedAt: r.startedAt,
      expiresAt: r.expiresAt,
      ...(r.endedAt !== null ? { endedAt: r.endedAt } : {}),
      ...(r.account ? { account: r.account } : {}),
      ...(r.timedOut ? { timedOut: true } : {}),
      ...(e.before ? { before: e.before } : {}),
    };
    if (r.url) {
      const domain = domainOf(r.url);
      if (domain) login.domain = domain;
    }
    if (r.url) login.url = r.url;
    if (r.loopback) login.callback = { ...r.loopback };
    if (r.code) login.code = r.code;
    if (r.codeUrl) login.codeUrl = r.codeUrl;
    if (r.error) login.error = r.error;
    return login;
  }

  /// A login as a read-only member may see it.
  static limited(login: Login): Login {
    const { url: _u, callback: _c, code: _k, codeUrl: _q, error: _e, ...rest } = login;
    return rest;
  }

  /// The stand-ins for the browser (`browser` for BROWSER; `open`, `xdg-open` and `osascript` first on the command's
  /// PATH): each writes the pages it is given to the file the login names, and does nothing else.
  #shims(): string {
    const dir = join(this.#data, "run", "login-shims");
    mkdirSync(dir, { recursive: true });
    const pages = `#!/bin/sh\n# A browser for a login command run by still.fail (station/src/logins): the page goes to the station.\n[ -n "$STILLFAIL_LOGIN_OPENED" ] || exit 0\nfor a in "$@"; do printf '%s\\n' "$a" >> "$STILLFAIL_LOGIN_OPENED"; done\nexit 0\n`;
    // Python's opener before 3.14 says `open location "…"` on osascript's stdin.
    const osascript = `#!/bin/sh\n# osascript for a login command run by still.fail (station/src/logins): the page goes to the station.\n[ -n "$STILLFAIL_LOGIN_OPENED" ] || exit 0\nprintf '%s\\n' "$*" >> "$STILLFAIL_LOGIN_OPENED"\n[ -t 0 ] || cat >> "$STILLFAIL_LOGIN_OPENED"\nexit 0\n`;
    for (const [name, text] of [["browser", pages], ["open", pages], ["xdg-open", pages], ["osascript", osascript]] as const) {
      const path = join(dir, name);
      let same = false;
      try {
        same = readFileSync(path, "utf8") === text;
      } catch {}
      if (!same) platform.makeCommand(path, text);
    }
    return dir;
  }

  /// Every login ended (the station stopping: they end with it).
  async close(): Promise<void> {
    for (const e of this.#entries.values()) e.run.close();
    this.#entries.clear();
    await this.#fibers.close();
  }
}

/// What the login commands do not take from the station's environment: what would point a runtime elsewhere, and the
/// station's own.
const SCRUBBED = ["CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CLAUDE_CONFIG_DIR", "CODEX_HOME", "STILLFAIL_MESH_NATIVE", "STILLFAIL_RUNNER", "SSH_CONNECTION", "SSH_CLIENT", "SSH_TTY"];

function writeAtomic(path: string, text: string) {
  const tmp = `${path}.${process.pid}.tmp`;
  writeFileSync(tmp, text);
  renameSync(tmp, path);
}

