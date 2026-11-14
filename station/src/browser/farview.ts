// Farview (AFK-surf/farview, a browser whose pages run on a host and draw on the person's device) as a chat's browser,
// in place of its Chrome context, where the station's config says so: config.json `browser: { engine: "farview",
// farview: "<the unpacked release: bin/host.exe, bin/agent.exe, lib/>" }`. Without it, nothing here runs and the chats
// have Chrome as before (the user, 2026-11-14: a switch of its own first, so nobody else is touched).
//
// Each chat gets one host process (`host.exe --tab`): one tab that lasts with nobody connected, its cookies, local
// storage and address kept in the chat's own directory (<data>/browser/farview/<chat>), gone with the chat. The host
// listens on 127.0.0.1 only: its agent port (driven with `agent.exe`, which the `browser` tool tells the agent of) and
// its frame port (JSON lines; what the tab's screen is made of, farview-screen.ts). It is started as a job is, in a
// group of its own, and outlives a station process: the next one takes it up by the `host.json` it wrote.
//
// Sign-ins ( 登录态) go into the tab as they go into a chat's Chrome context (browsers.ts): a sign-in the vault grants
// is its cookies set in the host's jar, taken out again as the grant ends; one kept is read from it; a card's sign-in
// fills the tab's form (farview-form.ts). Farview has no authenticator: a sign-in's passkeys are not put in.
// Not yet: the login pages a station opens of its own are Chrome's.
import { createHash } from "node:crypto";
import { access, mkdir, readFile, readdir, rm, writeFile } from "node:fs/promises";
import { connect } from "node:net";
import { join } from "node:path";
import { Clock, Effect } from "effect";
import { liveClock, wall } from "../ops/fibers.ts";
import { endGroup, groupAlive, startTimeOf } from "../ops/group.ts";
import { log } from "../ops/log.ts";
import { startLasting } from "../ops/processes.ts";
import type { Screens } from "../screens/source.ts";
import type { BrowserStatus } from "./browser.ts";
import { askTab } from "./farview-agent.ts";
import { FarviewForm } from "./farview-form.ts";
import { FarviewScreen } from "./farview-screen.ts";
import { type CookieParam, allCookies, ofSites } from "./signins.ts";
import type { TabInfo } from "./tabs.ts";

/// Where Farview is, as the config says it; null: the chats have Chrome.
export type FarviewConfig = { dir: string; host: string; agent: string };

export function farviewConfig(raw: any): FarviewConfig | null {
  const b = raw?.browser;
  if (b === null || typeof b !== "object" || b.engine !== "farview" || typeof b.farview !== "string" || b.farview === "") return null;
  return { dir: b.farview, host: join(b.farview, "bin", "host.exe"), agent: join(b.farview, "bin", "agent.exe") };
}

/// What a host writes into its state directory once it listens: its process and its ports.
export type HostFile = { pid: number; port: number; agent: number; frame: number };

export function hostFileOf(v: any): HostFile | null {
  const port = (n: unknown) => typeof n === "number" && Number.isInteger(n) && n > 0 && n < 65536;
  return v && typeof v === "object" && Number.isInteger(v.pid) && v.pid > 0 && port(v.port) && port(v.agent) && port(v.frame)
    ? { pid: v.pid, port: v.port, agent: v.agent, frame: v.frame }
    : null;
}

/// A chat's directory name: its session key is not one (`chat:c-…`, a Slack thread's address).
export const chatDir = (session: string): string => createHash("sha256").update(session).digest("hex").slice(0, 24);

/// The page a new tab opens on.
export const FIRST_PAGE = "about:blank";
/// How long a host is given to say it listens, and to end once asked.
const START_MS = 20_000;
const END_MS = 5_000;
const LOOK_MS = 100;

type Host = HostFile & { started: number | null; dir: string; screen: FarviewScreen; unscreen: () => void };

export type FarviewOptions = {
  /// <data>/browser/farview: a directory a chat.
  dir: string;
  config: () => FarviewConfig | null;
  screens?: Screens;
};

/// Whether something answers on a port of 127.0.0.1.
function answers(port: number): Promise<boolean> {
  return new Promise((resolve) => {
    const s = connect({ host: "127.0.0.1", port });
    const done = (ok: boolean) => {
      s.destroy();
      resolve(ok);
    };
    s.once("connect", () => done(true));
    s.once("error", () => done(false));
  });
}

export class FarviewTabs {
  readonly #o: FarviewOptions;
  readonly #hosts = new Map<string, Host>();
  /// Starts under way, by session: asked again meanwhile, the same one.
  readonly #starting = new Map<string, Promise<Host>>();

  constructor(o: FarviewOptions) {
    this.#o = o;
  }

  active(): FarviewConfig | null {
    return this.#o.config();
  }

  #dirOf(session: string): string {
    return join(this.#o.dir, chatDir(session));
  }

  /// The host `dir` says runs, if it is still that process and answers on its agent port.
  async #find(session: string, dir: string): Promise<Host | null> {
    let file: HostFile | null;
    try {
      file = hostFileOf(JSON.parse(await readFile(join(dir, "host.json"), "utf8")));
    } catch {
      return null;
    }
    if (file === null || !groupAlive(file.pid) || !(await answers(file.agent))) return null;
    return this.#up(session, dir, file, await startTimeOf(file.pid));
  }

  #up(session: string, dir: string, file: HostFile, started: number | null): Host {
    const screen = new FarviewScreen({ session, port: file.frame });
    const unscreen = this.#o.screens?.add(screen) ?? (() => {});
    screen.watch();
    const host: Host = { ...file, started, dir, screen, unscreen };
    this.#hosts.set(session, host);
    return host;
  }

  /// `session`'s chat's host: the one that runs (this process's, or one an earlier station process left), else started.
  async host(session: string): Promise<Host> {
    const had = this.#hosts.get(session);
    if (had !== undefined) {
      if (groupAlive(had.pid)) return had;
      this.#forget(session);
    }
    const starting = this.#starting.get(session);
    if (starting) return starting;
    const made = this.#start(session).finally(() => this.#starting.delete(session));
    this.#starting.set(session, made);
    return made;
  }

  async #start(session: string): Promise<Host> {
    const config = this.active();
    if (config === null) throw new Error("Farview is not this station's browser (config.json `browser`).");
    try {
      await access(config.host);
    } catch {
      throw new Error(`Farview's host is not at ${config.host}: unpack its release there, or take \`browser\` out of config.json for Chrome.`);
    }
    const dir = this.#dirOf(session);
    const found = await this.#find(session, dir);
    if (found !== null) return found;
    await mkdir(dir, { recursive: true, mode: 0o700 });
    await rm(join(dir, "host.json"), { force: true });
    // (whose chat it is, for the next station process to take its host up as it starts: `resume`)
    await writeFile(join(dir, "session"), session, { mode: 0o600 });
    let url = FIRST_PAGE;
    try {
      url = (await readFile(join(dir, "url"), "utf8")).trim() || FIRST_PAGE;
    } catch {}
    const child = startLasting(config.host, ["--tab", "0", url], {
      cwd: dir,
      stdio: "ignore",
      env: { ...process.env, FV_STATE_DIR: dir, FV_AGENT_PORT: "0", FV_FRAME_PORT: "0", FV_BIND: "127.0.0.1" },
    });
    let ended: number | null | undefined;
    child.once("exit", (code) => (ended = code));
    child.once("error", () => (ended = -1));
    const pid = child.pid ?? null;
    // timer: a deadline for a process that tells nothing until it wrote its file.
    for (let waited = 0; ; waited += LOOK_MS) {
      if (ended !== undefined) throw new Error(`Farview's host ended as it started (exit ${ended}); its log: ${dir}`);
      if (waited >= START_MS) {
        if (pid !== null) await this.#end(pid);
        throw new Error(`Farview's host did not open its ports within ${START_MS / 1000} s`);
      }
      await wall.sleep(LOOK_MS);
      try {
        const file = hostFileOf(JSON.parse(await readFile(join(dir, "host.json"), "utf8")));
        if (file !== null && (pid === null || file.pid === pid)) {
          log.info("browser", "a chat's Farview started", { session, pid: file.pid, agent: file.agent });
          return this.#up(session, dir, file, pid === null ? null : await startTimeOf(pid));
        }
      } catch {}
    }
  }

  async #end(pid: number) {
    if (groupAlive(pid)) await Effect.runPromise(endGroup(pid, END_MS).pipe(Effect.provideService(Clock.Clock, liveClock)));
  }

  #forget(session: string) {
    const host = this.#hosts.get(session);
    if (host === undefined) return;
    this.#hosts.delete(session);
    host.unscreen();
    host.screen.close();
  }

  /// Takes up the hosts an earlier station process left running, as this one starts: their tabs stay among the
  /// screens a person has open (an update restarted the station, and a person's view of a tab found it gone until its
  /// chat's agent asked for its browser again). Each chat's directory says whose it is.
  async resume(): Promise<void> {
    if (this.active() === null) return;
    let dirs: string[];
    try {
      dirs = await readdir(this.#o.dir);
    } catch {
      return;
    }
    for (const name of dirs) {
      const dir = join(this.#o.dir, name);
      let session: string;
      try {
        session = (await readFile(join(dir, "session"), "utf8")).trim();
      } catch {
        continue;
      }
      if (session === "" || chatDir(session) !== name || this.#hosts.has(session)) continue;
      const found = await this.#find(session, dir).catch(() => null);
      if (found !== null) log.info("browser", "a chat's Farview taken up", { session, pid: found.pid });
    }
  }

  /// Takes up the hosts an earlier station process left running (each chat's, as it asks: `host`).
  async endpoint(session: string): Promise<BrowserStatus> {
    await this.host(session);
    return this.status(session);
  }

  status(session: string): BrowserStatus {
    const host = this.#hosts.get(session);
    if (host === undefined || !groupAlive(host.pid)) return { running: false };
    return { running: true, binary: "Farview", headless: true, pid: host.pid, tabs: 1, viewing: host.screen.viewing() };
  }

  /// The port of the host whose tab is screen `id` that a person's client speaks Farview's protocol on (null: none
  /// runs): an app that draws the tab itself is carried to it (`{"farview": …}` streams, module.ts).
  clientPort(id: string): number | null {
    for (const host of this.#hosts.values()) if (host.screen.id === id && groupAlive(host.pid)) return host.port;
    return null;
  }

  /// Its agent port, for the agent's `agent.exe` (null: not running).
  agentPort(session: string): number | null {
    return this.#hosts.get(session)?.agent ?? null;
  }

  /// Its one tab, by the id its screen goes by after `browser:` (as a Chrome tab's: a sign-in's card opens
  /// `browser:<tab>`).
  tabs(session: string): TabInfo[] {
    const host = this.#hosts.get(session);
    if (host === undefined) return [];
    const page = host.screen.page();
    return [{ id: host.screen.id.replace(/^browser:/, ""), title: page.title, url: page.url, attached: false, session }];
  }

  async #cookies(session: string, verb: "get" | "set" | "clear", arg: string): Promise<string> {
    const host = await this.host(session);
    const a = await askTab(host.agent, { kind: "cookies", verb, arg });
    if (a.kind !== "value") throw new Error("Farview's tab did not give its cookies");
    if (a.value.startsWith("error:")) throw new Error(`Farview: ${a.value}`);
    return a.value;
  }

  /// The cookies of the chat's tab (its host started if it is not running).
  async cookies(session: string): Promise<CookieParam[]> {
    let read: unknown = [];
    try {
      read = JSON.parse(await this.#cookies(session, "get", ""));
    } catch {}
    return allCookies(read);
  }

  /// `cookies` set in the chat's tab (a sign-in granted).
  async putCookies(session: string, cookies: CookieParam[]): Promise<void> {
    if (cookies.length > 0) await this.#cookies(session, "set", JSON.stringify(cookies));
  }

  /// The cookies of `sites` taken out of the chat's tab where its host runs (a sign-in's grant ended): them, as they
  /// were.
  async takeOut(session: string, sites: string[]): Promise<CookieParam[]> {
    if (!this.#hosts.has(session)) {
      const found = await this.#find(session, this.#dirOf(session));
      if (found === null) return [];
    }
    const taken = (await this.cookies(session)).filter((c) => ofSites(c.domain, sites));
    // (Farview clears a host's cookies and its parent domains': each of theirs by its own, the site's among them)
    for (const domain of new Set(taken.map((c) => c.domain.replace(/^\./, "")))) await this.#cookies(session, "clear", domain);
    return taken;
  }

  /// The tab's sign-in form, filled from a card.
  async form(session: string): Promise<FarviewForm> {
    return new FarviewForm((await this.host(session)).agent);
  }

  /// Ends `session`'s chat's host; its directory (cookies, storage, where it was) stays for when it asks again.
  async stop(session: string): Promise<void> {
    const host = this.#hosts.get(session);
    this.#forget(session);
    if (host !== undefined) await this.#end(host.pid);
  }

  /// `session`'s chat was archived or deleted: its host ends and its directory goes, its sign-ins with it.
  async closeOf(session: string): Promise<void> {
    const dir = this.#dirOf(session);
    const host = this.#hosts.get(session) ?? (await this.#find(session, dir));
    this.#forget(session);
    if (host !== null) await this.#end(host.pid);
    await rm(dir, { recursive: true, force: true });
  }

  /// This station process ends: the hosts go on for the next one to take up.
  close(): void {
    for (const session of [...this.#hosts.keys()]) this.#forget(session);
  }
}

/// What the `browser` tool tells an agent of its chat's Farview.
export function farviewHowTo(config: FarviewConfig, port: number): string {
  const run = `${config.agent} 127.0.0.1 ${port}`;
  return [
    "This chat's browser runs: Farview (a browser whose pages run on this station and draw on people's devices), one tab.",
    `Drive it with: \`${run} <step>...\` — each step prints what the page says after it (its address, title and an outline of its content).`,
    "Steps: `look`, `go:<address>`, `click:<selector>`, `fill:<selector>=<words>`, `submit:<selector>`, `key:<key>` or `key:<key>@<selector>`, `back`, `forward`, `reload`, `wait:<ms>`, `shot:<file.png>`, `eval:<js>` (its result as JSON).",
    `For example: \`${run} go:https://example.com look\`.`,
    "There is no DevTools address: Playwright and chrome-devtools-mcp do not drive it.",
    "Its cookies and storage are this chat's alone and stay until the chat is archived. A site's sign-in: `sign_in` puts one the vault keeps into this tab, or asks a person on a card, as with Chrome.",
    "A person can see and drive the tab from their app (the `screen` tool gives the link); when they act on it, it is theirs: the agent is told \"the person took the tab back\" and waits until they say it is done.",
  ].join("\n");
}
