// The admin API (the Rust station's admin/mod.rs `route`): a table of routes, each a method, a path pattern and what answers
// it, gathered from src/api/routes (one module a part of the API). Reads go to the readers (off the main thread); what
// is not here answers 404 as an unknown route does.
import { runtimeCompatible } from "./runtime-compat.ts";
import { BUILD_HEADER, stationBuild } from "./oldest.ts";
import { join } from "node:path";
import type { ConfigFile } from "../ops/config.ts";
import type { Cloud } from "../cloud/state.ts";
import { type ScreenHub, ScreenRefused } from "../screens/hub.ts";
import { USER_TAB_ID } from "../screens/source.ts";
import type { SimDebug } from "../screens/sim-debug.ts";
import type { Readers } from "../read/pool.ts";
import { HttpError } from "../read/views.ts";
import { type Answer, type Request, error, json, queryPairs } from "./request.ts";
import { routes as chats } from "./routes/chats.ts";
import { routes as usage } from "./routes/usage.ts";
import { routes as sessions } from "./routes/sessions.ts";
import { routes as events } from "./routes/events.ts";
import { routes as marks } from "./routes/marks.ts";
import { routes as updates } from "./routes/updates.ts";
import { routes as accounts } from "./routes/accounts.ts";
import { routes as xshare } from "./routes/xshare.ts";
import { routes as hub, uploadPath } from "./routes/hub.ts";
import { routes as deviceTools } from "./routes/tools.ts";
import { routes as agentEnv } from "./routes/agent-env.ts";
import { routes as networkSettings } from "./routes/network.ts";
import { restarter } from "../ops/restart.ts";
import { routes as contextSettings } from "./routes/context.ts";
import { routes as presetRoutes } from "./routes/presets.ts";
import { routes as starRoutes } from "./routes/stars.ts";
import { routes as diagnosticsSettings } from "./routes/diagnostics.ts";
import { routes as drive } from "./routes/drive.ts";
import { routes as workspaces } from "./routes/workspaces.ts";
import { connectRoutes } from "./routes/connects.ts";
import { type Drive, stationDrive } from "../drive/drive.ts";
import type { CardChoice, StationParts } from "../parts.ts";
import { HelperFiles } from "../helper/files.ts";
import type { HelperApp } from "../helper/app.ts";
import type { HelperGrants } from "../helper/grants.ts";
import { routes as permissions } from "./routes/permissions.ts";
import { platform } from "../platform/index.ts";
import type { AgentsParts } from "../sessions/agents.ts";
import type { Store } from "../store/store.ts";
import type { Events } from "./events.ts";
import { Host } from "./host.ts";
import { previewTarget, proxyPreview } from "../jobs/preview.ts";
import type { Clock } from "effect";
import { liveClock } from "../ops/fibers.ts";
import { readOnly } from "../mesh/credential.ts";
import { elsewhere } from "./seen.ts";
import { reviewUndecided } from "../sessions/review.ts";
import { tr } from "../ops/i18n.ts";

/// What a read-only member (a viewer, contract §4) may still ask besides reads: marks of their own (read, kept,
/// dismissed), which change nothing anyone else sees.
const OWN_MARKS = /^\/*threads\/+[^/]+\/+(read|hidden|muted|dismissed|closed-card)(?:\/.*)?$/;
/// Reads that send what the client holds (routes/changed.ts), and several reads in one (`batch`).
const READS = /^\/*(changed\/+(chats|threads|sessions)|batch)$/;
/// What a batch may read (POST /batch): the history a client brings onto its device in the background, each a read
/// whose answer is JSON. At most BATCH_MOST of them, BATCH_AT_ONCE at a time.
const BATCHED = [/^\/threads\/\d+\/entries$/, /^\/threads\/\d+\/letters$/, /^\/threads\/\d+$/, /^\/sessions\/[^/]+$/, /^\/sessions\/[^/]+\/timeline$/];
const BATCH_MOST = 64;
const BATCH_AT_ONCE = 4;

/// Whether `r` is one a read-only member may make: reads (GET, HEAD, and a list's changes), and their own marks.
export function readOnlyMay(r: { method: string; path: string }): boolean {
  return r.method === "GET" || r.method === "HEAD" || (r.method === "PUT" && OWN_MARKS.test(r.path)) || (r.method === "POST" && READS.test(r.path));
}

export type Handler = (r: Request, args: string[]) => Promise<Answer>;
export type Route = { method: string; pattern: RegExp; handle: Handler };
/// What a route has to answer with.
export type Tools = {
  /// A read in a reader thread (src/read/ops.ts), answered as JSON; its error as `{error}` with its status.
  read(r: Request, op: string, args: unknown): Promise<Answer>;
  /// The machine's state, shared by GET /host and the events.
  host: Host;
  /// The event streams, once the station's store is open (the write side).
  events?: Events;
  /// Whether that session is there.
  sessionExists(key: string): boolean;
  /// The station's store, for what is written (on this thread); none while the station starts.
  store?: Store;
  /// The station's data directory (stillfail.db, sessions/, thumbs/).
  data?: string;
  /// The hub, the jobs and the rest of the agents' side, for what needs a session run, stopped or changed; none where
  /// there are no agents (tests of reads).
  agents?: AgentsParts;
  /// The part whose own kind of options card `card` is (parts.ts `cardChoice`): who may choose on it, and what then.
  cardChoice?(card: unknown): CardChoice | undefined;
};

/// What the admin API answers with besides the readers: the write side, once there.
export type AdminDeps = {
  events?: Events; store?: Store; host?: Host; clock?: Clock.Clock; screens?: ScreenHub;
  /// The agents' side: made after the admin API in the station (services.ts AgentsSide), so asked for as a request comes;
  /// given whole in tests, its routes then made here too (`agentsRoutes`).
  agents?: AgentsParts | (() => AgentsParts | undefined);
  /// config.json, the data directory and where the station stands with its control plane, for the platform's routes
  /// (the drive, the device tools, the workspaces); the agents' when not given (tests).
  config?: ConfigFile;
  data?: string;
  cloud?: Cloud;
  /// still.fail Helper (macOS): the drive's protected folders go through it.
  helper?: HelperApp | null;
  /// What macOS lets it do: one look at its grants and its window asking for them (the drive's, the page's).
  grants?: HelperGrants | null;
  /// The station's drive (services.ts StationDrive); one is made for the routes when none is given.
  drive?: Drive;
  /// The station's parts in its own process (parts.ts): their routes after the platform's, and what of theirs a
  /// read-only member may write.
  parts?: StationParts;
};

/// The header a write's key comes in, and how long an answer is kept.
const ONCE_KEY = "idempotency-key";
const ONCE_KEEP_MS = 10 * 60_000;
type Kept = { status: number; headers: Record<string, string>; body: Buffer };
/// A key's first write: its answer once there (none: not kept), and when it was kept.
type Slot = { at: number | null; answer: Promise<Kept | null> };

export class Admin {
  private slots = new Map<string, Slot>();
  private routes: Route[];
  /// What the routes are given; the station's parts' too (parts.ts).
  private tools: Tools;
  private readers: Readers;

  readonly host: Host;

  private deps: AdminDeps;

  constructor(readers: Readers, deps: AdminDeps = {}) {
    this.deps = deps;
    this.readers = readers;
    this.host = deps.host ?? new Host(readers.data);
    const agentsNow = () => (typeof deps.agents === "function" ? deps.agents() : deps.agents);
    const given = typeof deps.agents === "function" ? undefined : deps.agents;
    const config = deps.config ?? given?.config;
    const data = deps.data ?? config?.data;
    const cloud = deps.cloud ?? given?.cloud;
    const tools: Tools = {
      read: async (r, op, args) => {
        try {
          const signal = r.method === "GET" || (r.method === "POST" && READS.test(r.path)) ? r.signal : undefined;
          const options = { background: r.background === true, signal };
          // (as bytes, passed on as the reader gave them; a test's stand-in for the readers may give text alone)
          return json(200, "readBytes" in this.readers ? await this.readers.readBytes(op, args, r.lang, options) : await (this.readers as Readers).read(op, args, r.lang, options));
        } catch (e) {
          return error(e instanceof HttpError ? e.status : 500, (e as Error).message);
        }
      },
      host: this.host,
      events: deps.events,
      sessionExists: (key) => deps.store?.getSession(key) != null,
      store: deps.store,
      data: data ?? readers.data,
      get agents() {
        return agentsNow();
      },
      cardChoice: (card) => deps.parts?.cardChoiceOf(card),
    };
    this.tools = tools;
    this.routes = [...chats(tools), ...usage(tools), ...sessions(tools), ...events(tools), ...marks(tools), ...hub(tools),
      ...(config ? networkSettings({ config, changed: () => deps.events?.overviewChanged(), ...(data !== undefined ? { restart: () => restarter(data) } : {}) }) : []),
      ...(config ? deviceTools({ config, changed: () => deps.events?.overviewChanged() }) : []),
      ...(cloud && data !== undefined ? workspaces({ cloud, data, changed: () => deps.events?.overviewChanged() }) : []),
      ...(config && data !== undefined
        ? drive({
            config,
            // The station's (services.ts StationDrive); made here when not given (tests).
            drive:
              deps.drive ??
              stationDrive(
                config,
                () => agentsNow()?.hub.config().profiles.map((p) => p.home) ?? [],
                // The folders macOS keeps from the station, through still.fail Helper; their roots told again as its grants change.
                given?.helperFiles !== undefined
                  ? given.helperFiles
                  : deps.helper && platform.hasFolderPermissions
                    ? new HelperFiles({ helper: deps.helper, ...(deps.grants ? { grants: deps.grants } : {}), changed: () => deps.events?.overviewChanged() })
                    : null,
              ),
            changed: () => deps.events?.overviewChanged(),
            // Beside the files uploaded for a message (routes/hub.ts), swept as they are.
            stage: (name) => uploadPath(join(data, "uploads"), name),
          })
        : []),
      // What macOS lets still.fail Helper do here, a grant asked for from a member's app.
      ...(deps.grants ? permissions({ grants: deps.grants }) : []),
      // The screens members see and drive; a view of one is a stream of its own (mesh/screens.ts).
      ...(deps.screens
        ? [
            { method: "GET", pattern: /^\/screens$/, handle: async (r: Request) => (await deps.screens!.refresh(), json(200, JSON.stringify(deps.screens!.listed(r.lang)))) },
            { method: "POST", pattern: /^\/screens\/browser$/, handle: async (r: Request) => openBrowserScreen(deps.screens!, r) },
            // A person closes one (a tab of the browser): it leaves the list as it goes (`screens` on the event stream).
            { method: "POST", pattern: /^\/screens\/([^/]+)\/close$/, handle: async (r: Request, [raw]: string[]) => closeScreen(deps.screens!, r, raw!) },
            { method: "POST", pattern: /^\/screens\/([^/]+)\/open-url$/, handle: async (r: Request, [raw]: string[]) => openScreenUrl(deps.screens!, r, raw!) },
            { method: "POST", pattern: /^\/screens\/([^/]+)\/reload$/, handle: async (r: Request, [raw]: string[]) => actScreen(deps.screens!, r, raw!, (id) => deps.screens!.reloadScreen(id)) },
            { method: "POST", pattern: /^\/screens\/([^/]+)\/back$/, handle: async (r: Request, [raw]: string[]) => actScreen(deps.screens!, r, raw!, (id) => deps.screens!.historyScreen(id, -1)) },
            { method: "POST", pattern: /^\/screens\/([^/]+)\/forward$/, handle: async (r: Request, [raw]: string[]) => actScreen(deps.screens!, r, raw!, (id) => deps.screens!.historyScreen(id, 1)) },
            { method: "POST", pattern: /^\/screens\/([^/]+)\/sleep$/, handle: async (r: Request, [raw]: string[]) => actScreen(deps.screens!, r, raw!, (id) => deps.screens!.sleepScreen(id)) },
            { method: "POST", pattern: /^\/screens\/([^/]+)\/views\/end$/, handle: async (r: Request, [raw]: string[]) => screenViews(r, raw!, (id) => ({ ended: deps.screens!.endViews(id, byOf(r)) })) },
            { method: "POST", pattern: /^\/screens\/([^/]+)\/views\/([^/]+)\/end$/, handle: async (r: Request, [raw, view]: string[]) => screenViews(r, raw!, (id) => (deps.screens!.endView(id, decodeURIComponent(view!), byOf(r)), {})) },
            { method: "POST", pattern: /^\/screens\/([^/]+)\/views\/([^/]+)\/watch$/, handle: async (r: Request, [raw, view]: string[]) => screenViews(r, raw!, (id) => (deps.screens!.watchOnly(id, decodeURIComponent(view!)), {})) },
            // A person debugging an app on a simulator: its apps' logs (a poll, `after` from the last answer's `next`) and restart.
            { method: "GET", pattern: /^\/screens\/([^/]+)\/logs$/, handle: async (r: Request, [raw]: string[]) => screenDebug(deps.screens!, r, raw!, async (d) => d.logs(Math.max(0, Number(r.query.find(([k]) => k === "after")?.[1]) || 0))) },
            { method: "GET", pattern: /^\/screens\/([^/]+)\/apps$/, handle: async (r: Request, [raw]: string[]) => screenDebug(deps.screens!, r, raw!, async (d) => ({ apps: await d.apps() })) },
            { method: "GET", pattern: /^\/screens\/([^/]+)\/settings$/, handle: async (r: Request, [raw]: string[]) => screenDebug(deps.screens!, r, raw!, async (d) => d.settings()) },
            {
              method: "POST",
              pattern: /^\/screens\/([^/]+)\/settings$/,
              handle: async (r: Request, [raw]: string[]) =>
                screenDebug(deps.screens!, r, raw!, async (d) => {
                  const { name, value } = JSON.parse(r.body.toString("utf8") || "{}") as { name?: unknown; value?: unknown };
                  if (typeof name !== "string" || typeof value !== "string" || !(await d.setSetting(name, value))) throw new ScreenRefused(400, "station.screen.noSetting");
                  return d.settings();
                }),
            },
            { method: "GET", pattern: /^\/screens\/([^/]+)\/chrome\/(\d)\/(\d)$/, handle: async (r: Request, [raw, panel, turn]: string[]) => screenChrome(deps.screens!, r, raw!, Number(panel), Number(turn)) },
            { method: "POST", pattern: /^\/screens\/([^/]+)\/screenshot$/, handle: async (r: Request, [raw]: string[]) => screenDebug(deps.screens!, r, raw!, async (d) => ({ png: (await d.screenshot()).toString("base64") })) },
            ...simActions(deps.screens),
            // Its movie, the drive's way for the viewer to download (none: nothing was going on).
            { method: "POST", pattern: /^\/screens\/([^/]+)\/record\/stop$/, handle: async (r: Request, [raw]: string[]) => screenDebug(deps.screens!, r, raw!, async (d) => (await d.recordStop()) ?? {}) },
            {
              method: "POST",
              pattern: /^\/screens\/([^/]+)\/install$/,
              handle: async (r: Request, [raw]: string[]) =>
                screenDebug(deps.screens!, r, raw!, async (d) => {
                  const path = (JSON.parse(r.body.toString("utf8") || "{}") as { path?: unknown }).path;
                  const app = typeof path === "string" ? await d.install(path) : null;
                  if (app === null) throw new ScreenRefused(400, "station.screen.notAnApp");
                  return { app };
                }),
            },
            {
              method: "POST",
              pattern: /^\/screens\/([^/]+)\/relaunch$/,
              handle: async (r: Request, [raw]: string[]) =>
                screenDebug(deps.screens!, r, raw!, async (d) => {
                  const app = (JSON.parse(r.body.toString("utf8") || "{}") as { app?: unknown }).app;
                  if (typeof app !== "string" || !(await d.relaunch(app))) throw new ScreenRefused(404, "station.screen.noApp");
                  return {};
                }),
            },
          ]
        : []),
      // The agents' side's own (sessions/agents.ts says them as a part in the station; given whole, a test's).
      ...(given ? agentsRoutes(given, { store: deps.store, events: deps.events }) : []),
    ];
  }

  async handle(r: Request): Promise<Answer> {
    // Who asks is remembered by name, as the cloud's names (`deps.names`): what chats show of people who wrote.
    if (r.viewer.name !== "") this.readers.names.set(r.viewer.email, r.viewer.name);
    // A write with a key is done once, however often it is asked; the key is the viewer's own.
    const key = Object.entries(r.headers).find(([k]) => k.toLowerCase() === ONCE_KEY)?.[1];
    const keyed = key !== undefined && key !== "" && key.length <= 200 && r.method !== "GET" && r.method !== "HEAD";
    const answer = keyed ? await this.once(`${r.viewer.email}\0${r.path}\0${key}`, () => this.answer(r)) : await this.answer(r);
    // Every answer says this station keeps writes to once, and its build (api/oldest.ts).
    answer.headers["stillfail-idempotent"] = "1";
    answer.headers[BUILD_HEADER] = stationBuild();
    return runtimeCompatible(r, answer);
  }

  /// `write`'s answer, or the answer the first write under `key` had: while the first is under way the
  /// others wait for it; a 5xx is not kept (the write may not have happened: asked again, it is tried again).
  private async once(key: string, write: () => Promise<Answer>): Promise<Answer> {
    const now = (this.deps.clock ?? liveClock).currentTimeMillisUnsafe();
    for (const [k, slot] of this.slots) if (slot.at !== null && now - slot.at >= ONCE_KEEP_MS) this.slots.delete(k);
    for (;;) {
      const slot = this.slots.get(key);
      if (slot === undefined) break;
      const kept = await slot.answer;
      if (kept !== null) return { status: kept.status, headers: { ...kept.headers }, body: kept.body };
      // The first one's was not kept: this one tries, unless another got there first.
      if (this.slots.get(key) === slot) this.slots.delete(key);
    }
    let settle: (kept: Kept | null) => void = () => {};
    const slot: Slot = { at: null, answer: new Promise<Kept | null>((resolve) => (settle = resolve)) };
    this.slots.set(key, slot);
    let kept: Kept;
    try {
      const answer = await write();
      const parts: Buffer[] = [];
      if (Buffer.isBuffer(answer.body)) parts.push(answer.body);
      else for await (const chunk of answer.body) parts.push(Buffer.from(chunk));
      kept = { status: answer.status, headers: answer.headers, body: Buffer.concat(parts) };
    } catch (e) {
      settle(null);
      this.slots.delete(key);
      throw e;
    }
    if (kept.status < 500) {
      slot.at = (this.deps.clock ?? liveClock).currentTimeMillisUnsafe();
      settle(kept);
    } else {
      settle(null);
      this.slots.delete(key);
    }
    return { status: kept.status, headers: { ...kept.headers }, body: kept.body };
  }

  private async answer(r: Request): Promise<Answer> {
    // A viewer reads: no message sent, nothing changed (previews included); a module says what of its own a viewer
    // changes too (their reading progress, say: its manifest's `viewerWrites`).
    if (readOnly(r.viewer) && !readOnlyMay(r) && this.deps.parts?.mayView(r) !== true) return error(403, "read-only members cannot change this station");
    if (r.method === "POST" && /^\/*batch$/.test(r.path)) return this.batch(r);
    // A session, chat or job of another workspace than the viewer's is none for them (api/seen.ts).
    const hidden = this.deps.store ? elsewhere(this.deps.store, r.path, r.viewer) : null;
    if (hidden !== null) return error(404, hidden);
    // A web service on this machine, through its preview's path: any method, its answer as it comes.
    const preview = previewTarget(r.path);
    if (preview !== null) {
      const [port, target] = preview;
      const headers = Object.entries(r.headers).map(([k, v]): [string, string] => [k.toLowerCase(), v]);
      const answer = await proxyPreview(r.method, headers, r.body.length > 0 ? r.body : null, port, target + (r.search ?? ""), r.lang);
      const joined: Record<string, string> = {};
      for (const [name, value] of answer.headers) joined[name] = name in joined ? `${joined[name]}, ${value}` : value;
      return { status: answer.status, headers: joined, body: answer.body };
    }
    for (const route of [...this.routes, ...(this.deps.parts?.allRoutes(this.tools) ?? [])]) {
      const found = r.method === route.method ? route.pattern.exec(r.path) : null;
      if (found) return route.handle(r, found.slice(1));
    }
    return error(404, `no route ${r.method} ${r.path}`);
  }

  /// Several reads in one (POST /batch `{ gets }`, each a path with its query): each answered as its GET is, all in one
  /// answer, `{ answers: [{ status, body }] }` in their order, and compressed as one. A client brings a station's history
  /// onto its device so in the background: a read a request, a new device made some 500 of them for one station, each
  /// compressed on its own (and not at all under 512 bytes). Only the reads in BATCHED.
  private async batch(r: Request): Promise<Answer> {
    if (r.body.length > 1_000_000) return error(413, "request too large");
    let gets: unknown;
    try {
      gets = (JSON.parse(r.body.toString("utf8")) as { gets?: unknown }).gets;
    } catch {
      gets = undefined;
    }
    if (!Array.isArray(gets) || gets.length > BATCH_MOST || gets.some((g) => typeof g !== "string")) return error(400, `gets: at most ${BATCH_MOST} paths to read`);
    const paths = gets as string[];
    const answers: string[] = [];
    let next = 0;
    const work = async () => {
      for (let i = next++; i < paths.length; i = next++) {
        if (r.signal?.aborted) return;
        const at = paths[i]!.indexOf("?");
        const path = at < 0 ? paths[i]! : paths[i]!.slice(0, at);
        const a = BATCHED.some((p) => p.test(path))
          ? await this.answer({ ...r, background: true, method: "GET", path, query: at < 0 ? [] : queryPairs(paths[i]!.slice(at + 1)), search: at < 0 ? "" : paths[i]!.slice(at), body: Buffer.alloc(0) })
          : error(400, `not read in a batch: ${path}`);
        const text = Buffer.isBuffer(a.body) ? a.body.toString("utf8") : "";
        const isJson = Buffer.isBuffer(a.body) && (a.headers["content-type"] ?? "").startsWith("application/json") && text !== "";
        answers[i] = `{"status":${a.status},"body":${isJson ? text : JSON.stringify(text)}}`;
      }
    };
    await Promise.all(Array.from({ length: Math.min(BATCH_AT_ONCE, paths.length) }, work));
    // A cancelled batch has no answer to keep under an idempotency key; a retry must read its pages again.
    if (r.signal?.aborted) return error(503, "read cancelled");
    return json(200, `{"answers":[${answers.join(",")}]}`);
  }
}

/// The agents' side's routes (sessions/agents.ts says them as a part of the station): the station's and runtimes'
/// updates, the variables its agents run with, chats shared with other workspaces, the profiles and accounts, every
/// connect's edits (each kind's part says its own: connects/part.ts), and the overview as the settings pages show it.
export function agentsRoutes(agents: AgentsParts, deps: { store?: Store; events?: Events }): Route[] {
  return [
    ...(agents.config
      ? connectRoutes({
          config: agents.config,
          data: agents.hub.config().dataDir,
          hub: () => agents.hub,
          overview: (viewer, lang) => agents.overview(viewer, lang),
          place: () => agents.place(),
          entry: (kind) => agents.connectKinds?.get(kind)?.entry,
          heldBy: agents.heldBy,
          reconnect: async (kind, id) => void (await agents.connectKinds?.get(kind)?.reconnect(id)),
        })
      : []),
    ...(agents.updates ? updates({ updates: agents.updates }) : []),
    ...(agents.config ? agentEnv({ config: agents.config, changed: () => deps.events?.overviewChanged(), restart: () => agents.hub.everyChanged() }) : []),
    ...(agents.hub ? presetRoutes({ presets: agents.hub.presets, reposDir: () => agents.hub.reposDir(), index: agents.hub.repoIndex, clones: agents.hub.clones, changed: () => deps.events?.presetsChanged() }) : []),
    ...(agents.hub ? starRoutes({ kept: agents.hub.store, told: (ws, sub) => deps.events?.tell("stars", { workspace: ws }, `stars\0${ws}\0${sub}`, { workspace: ws, subs: [sub] }) }) : []),
    ...(agents.config ? contextSettings({ config: agents.config, changed: () => deps.events?.overviewChanged() }) : []),
    ...(agents.config ? diagnosticsSettings({ config: agents.config, changed: () => deps.events?.overviewChanged() }) : []),
    ...(agents.xshare ? xshare({ xshare: agents.xshare, store: deps.store }) : []),
    ...(agents.accounts
      ? accounts({
          accounts: agents.accounts,
          sharing: agents.sharing,
          overview: (r) => agents.overview(r.viewer, r.lang),
          ...(deps.store ? { policies: { store: deps.store, review: () => void reviewUndecided(agents.hub).catch(() => {}) } } : {}),
        })
      : []),
    ...(agents.overview ? [{ method: "GET", pattern: /^\/overview$/, handle: async (r: Request) => json(200, JSON.stringify(await agents.overview(r.viewer, r.lang))) }] : []),
  ];
}

/// A simulator's logs, apps and restart: only for those who may drive it (what apps log may be private; a read-only
/// member only sees the screen). 404 no such screen, 405 nothing to debug on it, 502 simctl failed.
/// What a person does of a device as Device Hub would, each with what it is told.
function simActions(screens: ScreenHub) {
  const route = (path: string, act: (d: SimDebug, said: Record<string, unknown>) => Promise<void>) => ({
    method: "POST",
    pattern: new RegExp(`^/screens/([^/]+)/${path}$`),
    handle: async (r: Request, [raw]: string[]) =>
      screenDebug(screens, r, raw!, async (d) => {
        await act(d, JSON.parse(r.body.toString("utf8") || "{}"));
        return {};
      }),
  });
  return [
    route("location", async (d, { at }) => {
      if ((at !== undefined && typeof at !== "string") || !(await d.location((at as string | undefined) ?? null))) throw new ScreenRefused(400, "station.screen.badPlace");
    }),
    route("status-bar", async (d, { tidy }) => d.statusBar(tidy === true)),
    route("biometrics", async (d, { what }) => {
      if (typeof what !== "string" || !(await d.biometrics(what))) throw new ScreenRefused(400, "station.screen.noSetting");
    }),
    route("uninstall", async (d, { app }) => {
      if (typeof app !== "string" || !(await d.uninstall(app))) throw new ScreenRefused(404, "station.screen.noApp");
    }),
    route("record", async (d, { panel }) => d.recordStart(panel === "inner" || panel === "cover" ? panel : null)),
    route("push", async (d, { app, text }) => {
      if (typeof app !== "string" || typeof text !== "string" || !(await d.push(app, text))) throw new ScreenRefused(404, "station.screen.noApp");
    }),
  ];
}

async function screenDebug(screens: ScreenHub, r: Request, raw: string, answer: (debug: SimDebug) => Promise<unknown>): Promise<Answer> {
  if (readOnly(r.viewer)) return error(403, "a read-only member does not read an app's logs");
  let id: string;
  try {
    id = decodeURIComponent(raw);
  } catch {
    return error(404, tr(r.lang, "station.screen.notFound"));
  }
  try {
    return json(200, JSON.stringify(await answer(screens.debugOf(id))));
  } catch (e) {
    if (e instanceof ScreenRefused) return error(e.status, tr(r.lang, e.key, e.args));
    // (simctl's own last line: what is before it is the command it ran and how it came to that)
    const said = (e as Error).message.split("\n").map((l) => l.trim()).filter(Boolean).at(-1) ?? "";
    return error(502, tr(r.lang, "station.screen.debugFailed", { said }));
  }
}

/// GET /screens/<id>/chrome/<panel>/<turn>: a simulator's case, its pictures made of what Xcode has on this Mac.
async function screenChrome(screens: ScreenHub, r: Request, raw: string, panel: number, turn: number): Promise<Answer> {
  let id: string;
  try {
    id = decodeURIComponent(raw);
  } catch {
    return error(404, tr(r.lang, "station.screen.notFound"));
  }
  try {
    return json(200, JSON.stringify(await screens.chromeOf(id, panel, turn)));
  } catch (e) {
    if (e instanceof ScreenRefused) return error(e.status, tr(r.lang, e.key, e.args));
    return error(502, tr(r.lang, "station.screen.debugFailed", { said: (e as Error).message.split("\n").at(-1) ?? "" }));
  }
}

/// Who a view's person is told ended it.
const byOf = (r: Request) => r.viewer.name || r.viewer.email;

/// POST /screens/<id>/views/…: a view ended or made to only look, by a member who may drive the screen (a read-only one
/// is refused with every other write, Admin's own check). 404 no such screen or view (it ended meanwhile), 405 an agent's.
async function screenViews(r: Request, raw: string, act: (id: string) => unknown): Promise<Answer> {
  try {
    return json(200, JSON.stringify(act(decodeURIComponent(raw))));
  } catch (e) {
    if (e instanceof ScreenRefused) return error(e.status, tr(r.lang, e.key, e.args));
    if (e instanceof URIError) return error(404, tr(r.lang, "station.screen.notFound"));
    throw e;
  }
}

/// POST /screens/<id>/close: 404 no such screen, 405 one not closed from here (the desktop), 502 the browser refused.
async function closeScreen(screens: ScreenHub, r: Request, raw: string): Promise<Answer> {
  return actScreen(screens, r, raw, (id) => screens.closeScreen(id));
}

async function actScreen(screens: ScreenHub, r: Request, raw: string, act: (id: string) => Promise<void>): Promise<Answer> {
  let id: string;
  try {
    id = decodeURIComponent(raw);
  } catch {
    return error(404, tr(r.lang, "station.screen.notFound"));
  }
  try {
    await act(id);
    return json(200, "{}");
  } catch (e) {
    if (e instanceof ScreenRefused) return error(e.status, tr(r.lang, e.key, e.args));
    return error(502, tr(r.lang, "station.screen.failed", { said: (e as Error).message }));
  }
}

async function openBrowserScreen(screens: ScreenHub, r: Request): Promise<Answer> {
  let url: unknown;
  let id: unknown;
  try {
    ({ url, id } = JSON.parse(r.body.toString("utf8") || "{}") as { url?: unknown; id?: unknown });
  } catch {
    return error(400, tr(r.lang, "station.screen.badUrl"));
  }
  if (typeof url !== "string") return error(400, tr(r.lang, "station.screen.badUrl"));
  // (the id the app made for it, so its view opened as it was pressed: `u_` and 12 hex digits)
  if (id !== undefined && (typeof id !== "string" || !USER_TAB_ID.test(id))) return error(400, "id: u_ and 12 hex digits");
  try {
    const screen = await screens.openBrowser(url, id as string | undefined);
    return json(200, JSON.stringify({ screen }));
  } catch (e) {
    if (e instanceof ScreenRefused) return error(e.status, tr(r.lang, e.key, e.args));
    return error(502, tr(r.lang, "station.screen.failed", { said: (e as Error).message }));
  }
}

async function openScreenUrl(screens: ScreenHub, r: Request, raw: string): Promise<Answer> {
  if (readOnly(r.viewer)) return error(403, "a read-only member does not open a link on a screen");
  let id: string;
  try {
    id = decodeURIComponent(raw);
  } catch {
    return error(404, tr(r.lang, "station.screen.notFound"));
  }
  let url: unknown;
  try {
    url = (JSON.parse(r.body.toString("utf8") || "{}") as { url?: unknown }).url;
  } catch {
    return error(400, tr(r.lang, "station.screen.badUrl"));
  }
  const source = screens.get(id);
  try {
    if (typeof url !== "string") {
      if (source === undefined) throw new ScreenRefused(404, "station.screen.notFound");
      if (source.openUrl === undefined && source.debug === undefined) throw new ScreenRefused(405, "station.screen.noDebug");
      throw new ScreenRefused(400, "station.screen.badUrl");
    }
    await screens.openUrl(id, url);
    return json(200, "{}");
  } catch (e) {
    if (e instanceof ScreenRefused) return error(e.status, tr(r.lang, e.key, e.args));
    if (source?.debug !== undefined) {
      const said = (e as Error).message.split("\n").map((l) => l.trim()).filter(Boolean).at(-1) ?? "";
      return error(502, tr(r.lang, "station.screen.debugFailed", { said }));
    }
    return error(502, tr(r.lang, "station.screen.failed", { said: (e as Error).message }));
  }
}
