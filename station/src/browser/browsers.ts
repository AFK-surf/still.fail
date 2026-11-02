// Each chat's own environment in the station's browser (docs/remote-screens.md, "A chat's own environment"): one
// Chrome for the station (browser.ts), and in it a browser context per chat, made over DevTools when the chat's agent
// first asks for the browser. A context is kept in memory only, as Chrome keeps one it is asked to make: no cookie of a
// chat is written to the station's disk, and none of another chat's reaches it (the gate on its agent's connection,
// gate.ts). What a chat is signed in to comes from the vault (docs/vault.md 登录态): a sign-in granted is put into its
// context (signins.ts) and taken out again when its grant ends, its cookies as they were then given back to the vault.
// The context goes when its chat is archived or deleted, and with Chrome when Chrome ends (idle, a crash): a chat asking
// again then has a new one, its sign-ins still granted put in again. The default context is the station's own, for the
// tabs it opens itself (a login's page: docs/remote-login.md), no chat's.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Fibers } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { type BrowserOptions, type BrowserStatus, StationBrowser } from "./browser.ts";
import type { GateParts } from "./gate.ts";
import { sitePasskeys } from "./passkeys.ts";
import { type SignedIn, expired, keptOf, siteCookies, stateOf } from "./signins.ts";
import { TabForm } from "./signin-form.ts";
import type { TabInfo } from "./tabs.ts";

/// A sign-in taken out of a chat's context as its grant ended: its cookies (and passkeys) as they were then (the site may
/// have given new ones since), as the vault keeps them (signins.ts `keptOf`), for it to keep (secrets.ts `renewed`).
export type TakenOut = (session: string, request: string, cookies: string) => void;

/// Each chat's context in the Chrome that runs, kept beside it (<data>/browser/contexts.json) so the next station
/// process takes them up with the browser: Chrome's DevTools address (which Chrome they are of) and, by session, its
/// context.
type Kept = { ws: string; contexts: Record<string, string>; signedIn?: Record<string, SignedIn[]> };

export class Browsers {
  /// The station's one Chrome; its default context the station's own.
  readonly station: StationBrowser;
  readonly #dir: string;
  readonly #fibers: Fibers;
  /// Each chat's context, by session, in the Chrome at `#ws`.
  #contexts = new Map<string, string>();
  #ws: string | null = null;
  /// Contexts being made, by session: asked again meanwhile, the same one.
  readonly #making = new Map<string, Promise<string>>();
  /// The sign-ins put into each chat's context and not taken out yet, by session; their timers by request.
  readonly #signedIn = new Map<string, SignedIn[]>();
  readonly #timers = new Map<string, () => void>();
  #takenOut: TakenOut = () => {};
  /// A chat's context made anew (Chrome started again): its sign-ins still granted are to be put in again.
  #fresh: (session: string) => void = () => {};
  /// A chat's context taken up from the station process before (its passkeys went with that process's connection):
  /// the passkeys of its sign-ins still granted are to be put in again.
  #resumed: (session: string) => void = () => {};
  #used: (session: string, host: string) => void = () => {};

  constructor(o: BrowserOptions) {
    this.#dir = o.dir;
    this.#fibers = new Fibers("browsers", o.clock);
    this.station = new StationBrowser({ ...o, contextOwner: (ctx) => this.#ownerOf(ctx), usedTab: (session, target) => this.used(session, target) });
    const kept = this.#read();
    if (kept !== null) {
      this.#ws = kept.ws;
      this.#contexts = new Map(Object.entries(kept.contexts));
      for (const [session, all] of Object.entries(kept.signedIn ?? {})) {
        this.#signedIn.set(session, all);
        for (const x of all) this.#arm(session, x);
      }
    }
  }

  /// A timer for sign-in `x` of `session`, at its end.
  #arm(session: string, x: SignedIn) {
    this.#timers.get(x.request)?.();
    this.#timers.set(x.request, this.#fibers.after(Math.max(0, x.until * 1000 - this.#fibers.now()), () => {
      this.#timers.delete(x.request);
      void this.#due(session).catch((e) => log.warn("browser", "a sign-in could not be taken out", { session, error: (e as Error).message }));
    }));
  }

  /// Hears each sign-in taken out of a chat's context, with its cookies as they were.
  onTakenOut(f: TakenOut) {
    this.#takenOut = f;
  }

  /// Hears each chat whose context was made anew, to put its sign-ins still granted in again.
  onFresh(f: (session: string) => void) {
    this.#fresh = f;
  }

  /// Hears each chat whose context was taken up from the station process before, to put its passkeys in again.
  onResumed(f: (session: string) => void) {
    this.#resumed = f;
  }

  /// A person or agent deliberately used a site in this chat's browser.
  onUsed(f: (session: string, host: string) => void) { this.#used = f; }

  used(session: string, target: string, url?: string) {
    const address = url ?? this.tabs(session).find((t) => t.id === target)?.url;
    if (!address) return;
    try { this.#used(session, new URL(address).hostname.toLowerCase()); } catch { /* not a site */ }
  }

  /// Extend the browser's removal timer without putting old cookies back over the current ones.
  extendSignIn(session: string, request: string, until: number) {
    const x = this.#signedIn.get(session)?.find((y) => y.request === request);
    if (!x || x.until <= this.#fibers.now() / 1000) return;
    x.until = until;
    this.#write();
    this.#arm(session, x);
  }

  /// Takes up the Chrome an earlier station process left running, with the chats' contexts in it.
  async resume(): Promise<void> {
    await this.station.resume();
    if (this.station.status().running) this.passkeysAgain();
  }

  /// Each chat with sign-ins in its context: their passkeys asked to be put in again (`onResumed`).
  passkeysAgain() {
    for (const session of this.#signedIn.keys()) if (this.#contexts.has(session)) this.#resumed(session);
  }

  /// The passkeys of a sign-in still granted put into `session`'s chat's context again (its cookies are there still), if
  /// the browser runs with it.
  async passkeysIn(session: string, d: { sites: string[]; cookies: string }): Promise<void> {
    const ctx = this.#contexts.get(session);
    const passkeys = sitePasskeys(stateOf(d.cookies).passkeys, d.sites);
    if (ctx === undefined || passkeys.length === 0 || !this.station.status().running) return;
    await (await this.station.passkeys()).put(ctx, passkeys);
  }

  /// The session whose chat's context `ctx` is.
  #ownerOf(ctx: string | undefined): string | undefined {
    if (ctx === undefined) return undefined;
    for (const [session, c] of this.#contexts) if (c === ctx) return session;
    return undefined;
  }

  /// `session`'s chat's context in the browser (started if it is not running), made if it has none there.
  async context(session: string): Promise<string> {
    const status = await this.station.endpoint();
    const ws = status.ws ?? "";
    if (ws !== this.#ws) {
      // Another Chrome than the one the contexts were made in: theirs went with it, the sign-ins in them too (those
      // still granted are put in again as each chat's context is made anew).
      this.#ws = ws;
      this.#contexts.clear();
      for (const stop of this.#timers.values()) stop();
      this.#timers.clear();
      this.#signedIn.clear();
      this.#write();
    }
    const had = this.#contexts.get(session);
    if (had !== undefined) return had;
    const making = this.#making.get(session);
    if (making) return making;
    const made = (async () => {
      const { browserContextId } = await this.station.send("Target.createBrowserContext", { disposeOnDetach: false });
      if (typeof browserContextId !== "string" || browserContextId === "") throw new Error("Chrome made no browser context.");
      this.#contexts.set(session, browserContextId);
      this.#write();
      log.info("browser", "a chat's own context made", { session });
      this.#fresh(session);
      return browserContextId;
    })().finally(() => this.#making.delete(session));
    this.#making.set(session, made);
    return made;
  }

  /// The door's way in for `session` (proxy.ts): the browser's DevTools and the gate's parts for its chat's context.
  async open(session: string): Promise<{ ws: string; gate: GateParts }> {
    const context = await this.context(session);
    await this.#due(session);
    const ws = this.station.status().ws;
    if (ws === undefined) throw new Error("the browser has no DevTools address");
    return { ws, gate: { context, contextOf: (id) => this.station.contextOf(id), used: (id, url) => this.used(session, id, url) } };
  }

  /// What `session`'s agent is told of the browser (its tool): it runs, its chat's context made.
  async endpoint(session: string): Promise<BrowserStatus> {
    await this.context(session);
    await this.#due(session);
    return this.status(session);
  }

  /// The tabs of `session`'s chat.
  tabs(session: string): TabInfo[] {
    return this.station.tabs().filter((t) => t.session === session);
  }

  /// The sign-in form of `session`'s chat's tab `targetId`, on a connection of its own (signin-form.ts); refused for a
  /// tab not its chat's.
  async form(session: string, targetId: string): Promise<TabForm> {
    if (!this.tabs(session).some((t) => t.id === targetId)) throw new Error("no such tab in this chat's browser");
    const { cdp, session: tab } = await this.station.attach(targetId);
    return new TabForm(cdp, tab, targetId);
  }

  status(session: string): BrowserStatus {
    const s = this.station.status();
    if (!s.running || !this.#contexts.has(session)) return { running: false };
    return { ...s, tabs: this.tabs(session).length };
  }

  /// Closes `session`'s chat's context, its tabs with it; its sign-ins still granted are put in again when it asks.
  async stop(session: string): Promise<void> {
    await this.#dispose(session);
  }

  /// `session`'s chat was archived or deleted: its context goes, its tabs and sign-ins with it; tabs it opened in the
  /// station's own context (before chats had their own) are closed.
  async closeOf(session: string): Promise<void> {
    await this.#dispose(session);
    for (const x of this.#signedIn.get(session) ?? []) {
      this.#timers.get(x.request)?.();
      this.#timers.delete(x.request);
    }
    this.#signedIn.delete(session);
    this.#write();
    await this.station.closeOf(session);
  }

  async #dispose(session: string) {
    const ctx = this.#contexts.get(session);
    if (ctx === undefined) return;
    this.#contexts.delete(session);
    this.#write();
    if (this.station.status().running) {
      (await this.station.passkeys()).forget(ctx);
      await this.station.send("Target.disposeBrowserContext", { browserContextId: ctx }).catch(() => {});
    }
  }

  /// The sign-in to `sites` in `session`'s chat's context, or in the station's own (`station`), as the vault keeps it
  /// (signins.ts `keptOf`): its cookies, and its passkeys (a chat's context only: the station's has no authenticator);
  /// the browser started if it is not running.
  async cookies(session: string, sites: string[], station: boolean): Promise<string> {
    const ctx = station ? undefined : await this.context(session);
    const { cookies } = await this.station.send("Storage.getCookies", ctx ? { browserContextId: ctx } : {});
    const passkeys = ctx === undefined ? [] : await (await this.station.passkeys()).read(ctx, sites);
    return keptOf({ cookies: siteCookies(cookies, sites), passkeys });
  }

  /// A sign-in granted (`request`): its cookies and passkeys of `sites` put into `session`'s chat's context (the browser
  /// started if it is not running), taken out again at `until` (unix seconds).
  async signIn(session: string, d: { request: string; sites: string[]; cookies: string; until: number }): Promise<void> {
    const state = stateOf(d.cookies);
    const cookies = siteCookies(state.cookies, d.sites);
    const passkeys = sitePasskeys(state.passkeys, d.sites);
    const ctx = await this.context(session);
    const x: SignedIn = { request: d.request, sites: d.sites, until: d.until };
    this.#signedIn.set(session, [...(this.#signedIn.get(session) ?? []).filter((y) => y.request !== d.request), x]);
    this.#write();
    if (cookies.length > 0) await this.station.send("Storage.setCookies", { browserContextId: ctx, cookies });
    await (await this.station.passkeys()).put(ctx, passkeys);
    log.info("browser", "a sign-in put into a chat's context", { session, request: d.request, sites: d.sites, cookies: cookies.length, passkeys: passkeys.length });
    this.#arm(session, x);
  }

  /// Takes out of `session`'s chat's context the sign-ins whose grant ended, their cookies given back as they were.
  async #due(session: string) {
    const now = this.#fibers.now() / 1000;
    const ended = (this.#signedIn.get(session) ?? []).filter((x) => x.until <= now);
    if (ended.length === 0) return;
    // Its context is not there (the browser is closed, or not taken up yet): taken out when it next is. One gone with
    // its Chrome took its cookies with it: nothing to take out, nothing new to give back.
    const ctx = this.#contexts.get(session);
    if (!this.station.status().running) return;
    this.#signedIn.set(session, (this.#signedIn.get(session) ?? []).filter((x) => x.until > now));
    this.#write();
    if (ctx === undefined) return;
    const { cookies: read } = await this.station.send("Storage.getCookies", { browserContextId: ctx });
    const keys = await this.station.passkeys();
    for (const x of ended) {
      const cookies = siteCookies(read, x.sites);
      if (cookies.length > 0) await this.station.send("Storage.setCookies", { browserContextId: ctx, cookies: expired(cookies) });
      const passkeys = await keys.takeOut(ctx, x.sites);
      log.info("browser", "a sign-in taken out of a chat's context as its grant ended", { session, request: x.request, sites: x.sites });
      if (cookies.length > 0 || passkeys.length > 0) this.#takenOut(session, x.request, keptOf({ cookies, passkeys }));
    }
  }

  /// This station process ends: lets go of the browser, which goes on running with the chats' contexts for the next
  /// one to take up.
  async close(): Promise<void> {
    for (const stop of this.#timers.values()) stop();
    this.#timers.clear();
    await this.station.close();
    await this.#fibers.close();
  }

  #read(): Kept | null {
    try {
      const v = JSON.parse(readFileSync(join(this.#dir, "contexts.json"), "utf8"));
      return typeof v?.ws === "string" && v.contexts && typeof v.contexts === "object" ? v : null;
    } catch {
      return null;
    }
  }

  #write() {
    try {
      mkdirSync(this.#dir, { recursive: true });
      writeFileSync(join(this.#dir, "contexts.json"), JSON.stringify({ ws: this.#ws ?? "", contexts: Object.fromEntries(this.#contexts), signedIn: Object.fromEntries(this.#signedIn) } satisfies Kept, null, 2) + "\n");
    } catch (e) {
      log.warn("browser", "the chats' contexts could not be written down", { error: (e as Error).message });
    }
  }
}
