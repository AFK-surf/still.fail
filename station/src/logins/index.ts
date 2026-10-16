// The station's logins to the command-line tools its agents use (docs/remote-login.md): each station logs in itself,
// the login landing in its own user's home and keychain (machine-wide: every chat's agent uses it); a person finishes it
// from their client, in their own browser. One way for every tool (用户定: no service supported one by one): the tool's
// own login command is run (run.ts), and what it asks of a person is read from what it does. Here: the logins under way
// and ended lately (their screens with them), and the record of those done through still.fail on this station (command,
// who, when, how it ended: <data>/logins/history.json), which is all the station page lists.
import { mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import type { Clock } from "effect";
import { Fibers } from "../ops/fibers.ts";
import { type Lang, stationLang, tr } from "../ops/i18n.ts";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";
import { commandWords, domainOf } from "./parse.ts";
import { type Answered, type Callback, Refused, relay } from "./relay.ts";
import { type Key, KEYS, LoginRun, type Screen } from "./run.ts";

export { Refused };

/// An ended login (and its screen) is kept in memory this long; its record stays in the history.
const KEPT_MS = 10 * 60_000;
/// How many ended logins are kept in memory at most.
const KEPT_MOST = 20;
/// How many past logins the history keeps.
const HISTORY_MOST = 50;

export type Person = { email: string; name: string };
/// Who started a login: a person (from their client, in a workspace), or an agent (its session, in its chat's workspace;
/// `by` its chat's starter).
export type Starter = { by: Person; workspace: string | null; chat?: string | null };

export type Login = {
  id: string;
  /// What it is shown by: its command's program (gh, gcloud).
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
};

type Entry = { run: LoginRun; starter: Starter; screens: Set<(screen: Screen) => void> };

export type LoginsOptions = {
  data: string;
  /// The environment logins run in (the station's: the same home and keychain its agents use).
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
  readonly #listeners = new Set<(change: { login: string }) => void>();
  readonly #ended = new Set<(login: Login, starter: Starter) => void>();
  /// The logins whose end was told (once each).
  readonly #endedOnce = new Set<string>();
  #next = 0;

  constructor(o: LoginsOptions) {
    this.#data = o.data;
    this.#env = o.env ?? (() => Object.fromEntries(Object.entries(process.env).filter((e): e is [string, string] => e[1] !== undefined && !SCRUBBED.includes(e[0]))));
    this.#fibers = new Fibers("logins", o.clock);
    this.#lang = o.lang ?? stationLang;
  }

  // ── what is told ──

  /// Hears each login that changed (its id).
  changes(listener: (change: { login: string }) => void): () => void {
    this.#listeners.add(listener);
    return () => this.#listeners.delete(listener);
  }

  /// Hears each login that ends (done, failed, cancelled), with who started it.
  onEnded(listener: (login: Login, starter: Starter) => void): () => void {
    this.#ended.add(listener);
    return () => this.#ended.delete(listener);
  }

  #tell(change: { login: string }) {
    for (const l of this.#listeners) {
      try {
        l(change);
      } catch (e) {
        log.warn("logins", "a listener failed", { error: (e as Error).message });
      }
    }
  }

  // ── the history ──

  /// The logins done through still.fail on this station, newest first: how each ended, no page, code or output.
  history(): Login[] {
    try {
      const v = JSON.parse(readFileSync(join(this.#data, "logins", "history.json"), "utf8"));
      return Array.isArray(v) ? v.filter((l) => l && typeof l.id === "string") : [];
    } catch {
      return [];
    }
  }

  #record(login: Login) {
    const dir = join(this.#data, "logins");
    mkdirSync(dir, { recursive: true });
    const kept: Login = {
      id: login.id, name: login.name, command: login.command, state: login.state, waiting: false, by: login.by,
      ...(login.workspace ? { workspace: login.workspace } : {}), ...(login.chat ? { chat: login.chat } : {}),
      startedAt: login.startedAt, expiresAt: login.expiresAt, ...(login.endedAt !== undefined ? { endedAt: login.endedAt } : {}),
      ...(login.timedOut ? { timedOut: true } : {}),
    };
    const history = [kept, ...this.history().filter((l) => l.id !== login.id)].slice(0, HISTORY_MOST);
    writeAtomic(join(dir, "history.json"), `${JSON.stringify(history, null, 2)}\n`);
  }

  // ── logins ──

  /// Those under way, then those ended: kept in memory as they are (with their pages and outcome), then the history's.
  logins(): Login[] {
    this.#sweep();
    const all = [...this.#entries.values()];
    const live = [...all.filter((e) => e.run.active), ...all.filter((e) => !e.run.active).reverse()].map((e) => this.#shown(e));
    return [...live, ...this.history().filter((h) => !this.#entries.has(h.id))];
  }

  get(id: string): Login | null {
    this.#sweep();
    const e = this.#entries.get(id);
    return e ? this.#shown(e) : (this.history().find((h) => h.id === id) ?? null);
  }

  /// A login started: a command (words, or a line split as a shell would). One under way for the same command is given
  /// rather than another. Throws Refused when it cannot be.
  async start(command: string | string[], starter: Starter): Promise<Login> {
    const lang = this.#lang();
    const words = Array.isArray(command) ? command : commandWords(command);
    if (words === null || words.length === 0 || words.some((w) => typeof w !== "string" || w === "") || words.join(" ").length > 2000) throw new Refused(400, tr(lang, "station.machineLogin.badCommand"));
    const running = [...this.#entries.values()].find((e) => e.run.active && e.run.command.join("\0") === words.join("\0"));
    if (running) return this.#shown(running);
    const id = `${this.#fibers.now().toString(36)}${(++this.#next).toString(36)}${Math.random().toString(36).slice(2, 6)}`;
    const dir = join(this.#data, "run", "logins");
    mkdirSync(dir, { recursive: true });
    const entry: Entry = { starter, screens: new Set(), run: undefined as unknown as LoginRun };
    entry.run = new LoginRun({
      id,
      command: words,
      env: this.#env(),
      cwd: platform.home(this.#env()) ?? this.#data,
      shims: this.#shims(),
      opened: join(dir, `${id}.opened`),
      fibers: this.#fibers,
      lang,
      changed: () => {
        if (!entry.run.active) this.#endedNow(entry);
        this.#tell({ login: id });
      },
      drawn: () => {
        const screen = entry.run.screen();
        for (const s of entry.screens) s(screen);
      },
    });
    this.#entries.set(id, entry);
    await entry.run.start();
    return this.#shown(entry);
  }

  #endedNow(entry: Entry) {
    const id = entry.run.id;
    if (this.#endedOnce.has(id)) return;
    this.#endedOnce.add(id);
    const shown = this.#shown(entry);
    try {
      this.#record(shown);
    } catch (e) {
      log.warn("logins", "a login was not recorded", { error: (e as Error).message });
    }
    for (const l of this.#ended) {
      try {
        l(shown, entry.starter);
      } catch (e) {
        log.warn("logins", "a listener failed", { error: (e as Error).message });
      }
    }
    // Let go of a while after (its screen with it): its record stays.
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

  /// Typed into its terminal: `{text}`, or `{key}`.
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
    const login: Login = {
      id: r.id,
      name: r.command[0]?.split(/[\\/]/).at(-1) ?? "",
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
      ...(r.timedOut ? { timedOut: true } : {}),
    };
    if (r.url) {
      const domain = domainOf(r.url);
      if (domain) login.domain = domain;
      login.url = r.url;
    }
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
