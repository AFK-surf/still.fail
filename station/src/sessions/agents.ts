// The agents' side of the station (server.rs `App::start`): the hub with its drivers, background jobs, tasks for other
// stations, the agents' tools and their door (/mcp). Made here and given to the rest; nothing else starts an agent.
//
// What the previous station process ran goes on (docs/station-ts.md, 已定 1): a station that stops hands its sessions
// over (run/handover.json) and the next takes them up, runtimes and all, from their runners. Under the launcher the
// next process is up before the previous one hands over: it takes up only once that one is gone (run/hub.json says
// which process holds the sessions), and opens the agents' door only then, so no call reaches a hub without its session.
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Context, Effect, Layer, Schedule, Stream, SubscriptionRef } from "effect";
import { Fibers, wall } from "../ops/fibers.ts";
import { ClaudeDriver } from "../agents/claude.ts";
import { CodexDriver } from "../agents/codex.ts";
import { DshDriver } from "../agents/dsh.ts";
import { GrokDriver } from "../agents/grok.ts";
import { CursorDriver } from "../agents/cursor.ts";
import { HermesDriver } from "../agents/hermes.ts";
import { DevinDriver } from "../agents/devin.ts";
import { Jobs, notifyEndpoint, screenEndpoint } from "../jobs/jobs.ts";
import { liveMemory } from "../jobs/memory.ts";
import { WorkspaceWatch, type WorkspaceReading } from "../jobs/workspace-size.ts";
import { Remote, followRoster } from "../jobs/remote.ts";
import { ConfigFile } from "../ops/config.ts";
import { DISK_EVERY_MS, DISK_LOW_BYTES, diskFree } from "../ops/disk.ts";
import { lentFile, placeIn, sandboxConfig, sandboxed } from "../agents/sandbox.ts";
import type { Control } from "../ops/launcher.ts";
import { log } from "../ops/log.ts";
import { mcpPortFile, ownData, portsToTry, rememberedMcpPort } from "../ops/files.ts";
import { AdminHost, ControlPlane, Events, Grants, HelperFolders, Key, ModulePackages, Modules, Own, Parts, Paths, Peers, Previous, Readers, ScreenRegistry, StationConfig, Store, Up, AgentsSide, MeshSide } from "../services.ts";
import { claudeCredentialsFile, codexAuthFile } from "../agents/machine-logins.ts";
import { permissionsView } from "../api/routes/permissions.ts";
import { Gpus } from "../jobs/gpu.ts";
import { Net, measure } from "../jobs/load.ts";
import { Notifier } from "../cloud/notify.ts";
import type { Cloud as CloudState } from "../cloud/state.ts";
import { screenTools } from "../tools/screen.ts";
import { permissionTools } from "../tools/permissions.ts";
import { HelperFiles } from "../helper/files.ts";
import { Places } from "../ops/places.ts";
import { platform } from "../platform/index.ts";
import { Computer, computerTools } from "../tools/computer.ts";
import { archiveTools } from "../tools/archive.ts";
import { chatTools } from "../tools/chat.ts";
import { type AgentsDoor, type PeerRoute, openAgentsDoor } from "../tools/http.ts";
import { jobTools } from "../tools/jobs.ts";
import { forwardTools } from "../tools/forward.ts";
import { Forwards } from "../mesh/peer-forward.ts";
import { nameOf, peerNamed } from "../mesh/peer-http.ts";
import { McpEndpoint, UNBOUND_REFUSAL } from "../tools/mcp.ts";
import { remoteTools } from "../tools/remote.ts";
import { workspaceSizeTools } from "../tools/workspace-size.ts";
import { type Accounts, checkConfig, makeAccounts } from "../accounts/index.ts";
import { Sharing } from "../share/index.ts";
import { ChatShares } from "../xshare/index.ts";
import { overview } from "../api/overview.ts";
import type { ConnectKind } from "../connects/connections.ts";
import { agentsRoutes } from "../api/admin.ts";
import type { ChatSurface } from "./chat.ts";
import { rootViewThrough } from "../drive/drive.ts";
import type { Viewer } from "../mesh/credential.ts";
import type { Lang } from "../ops/i18n.ts";
import { type Updates, makeUpdates } from "../updates/updates.ts";
import { hubConfig } from "./config.ts";
import type { TailState } from "../read/tail.ts";
import { ColdRooms } from "./cold.ts";
import { Hub } from "./hub.ts";
import { roomOf } from "./footprint.ts";
import { InternalChat } from "./internal.ts";
import { autoArchive, expireArchived, relieveArchived } from "./lifecycle.ts";
import { fromPeer, sender } from "./messages.ts";
import { CREATE, NOTICE, createForPeer, noticeForPeer } from "./opened.ts";
import { chatsTouched, forPeer, READ } from "./others.ts";
import { FILE, fileForPeer, PUT, putForPeer } from "./peer-files.ts";
import { reviewUndecided, startReview } from "./review.ts";
import { readAgentEnvFrom } from "../ops/agent-env.ts";

/// server.rs `encode` (encodeURIComponent).
const encode = encodeURIComponent;

/// How often the sandboxes nothing runs in are looked for (hub.ts `sweepSandboxes`).
const SWEEP_MS = 3 * 60_000;
/// How many threads archived to files are brought back into the database at a time, a second apart (store.ts
/// `bringInArchived`): each a file read and its entries written, the main thread's.
const BRING_IN = 20;

export type AgentsParts = {
  /// The agents' predecessor-exit wait, also used before binding the mesh socket.
  previousGone: Promise<void>;
  hub: Hub;
  jobs: Jobs;
  remote: Remote;
  mcp: McpEndpoint;
  config: ConfigFile;
  updates: Updates;
  accounts: Accounts;
  /// What this station shares with the workspace's other stations, and uses of theirs.
  sharing: Sharing;
  /// Chats shared with other workspaces, and theirs shared with this one.
  xshare: ChatShares;
  /// Where the agents' door sends /peer requests: the mesh's way to other stations' web services, once it is up
  /// (mesh/peer-http.ts).
  peers: { route: PeerRoute | null };
  /// Ports of other stations forwarded here (mesh/peer-forward.ts).
  forwards: Forwards;
  /// The connects' chats the hub takes and posts to (Slack's, slack/module.ts; Feishu's, feishu/module.ts): each part
  /// says those of its connects, and a connect's chat is whichever part has it.
  surfaces(chats: (connect: string) => ChatSurface | undefined): void;
  /// How a kind of connect (config.json's `kind`) shows, is edited and is connected again, as its part says
  /// (connects/part.ts); and those said.
  connectKind(kind: string, view: ConnectKind): void;
  connectKinds: Map<string, ConnectKind>;
  /// What a part does as the station takes its sessions up and as its workspaces change (`Along`).
  along(a: Along): void;
  /// Whether the sessions are taken up (the process before is gone), and whether the station is in its workspace.
  taken(): boolean;
  bound(): boolean;
  /// A session's page in the app (`<origin>/o/…`), in still.fail cloud only.
  pageOf(key: string): string | undefined;
  /// Where the station is in its control plane while in a workspace.
  place(): { origin: string; workspace: string; station: string; name: string } | null;
  /// Where the station stands with its control plane: the workspaces it is in (docs/multi-workspace.md).
  cloud: CloudState;
  /// Its relay as the mesh sees it, for what other stations are told of its load (jobs/load.ts).
  net: Net;
  /// GET /overview as `viewer` sees it.
  overview(viewer: Viewer, lang: Lang): Promise<unknown>;
  /// The folders macOS protects, through still.fail Helper (helper/files.ts), shared by the drive and the directories
  /// people and agents name (ops/places.ts); null where there is no helper for them.
  helperFiles?: HelperFiles | null;
};

/// What a part of the agents' side does along with them (slack/module.ts), awaited in the order the agents need: as the
/// sessions are taken up in a workspace (`taken`, before they recover), as the station comes into its workspace
/// (`joined`, before they recover), as it leaves it (`left`, once they are suspended, before the jobs stop), and as one
/// of the workspaces it joined is left or back (`changed`).
export type Along = { taken?(): Promise<void>; joined?(): Promise<void>; left?(): Promise<void>; changed?(): Promise<void> };

export class Agents extends Context.Service<Agents, AgentsParts>()("stillfail/Agents") {}

export const AgentsLive = (control: Control) =>
  Layer.effect(
    Agents,
    Effect.gen(function* () {
      const { data, app } = yield* Paths;
      const store = yield* Store;
      const plane = yield* ControlPlane;
      const cloud = plane.state;
      const readers = yield* Readers;
      const events = yield* Events;
      const key = yield* Key;
      const screens = yield* ScreenRegistry;
      const grants = yield* Grants;
      const host = yield* AdminHost;
      const modules = yield* Modules;
      const own = yield* Own;
      const up = yield* Up;
      const parts = yield* Parts;
      const previous = (yield* Previous).gone;
      const run = join(data, "run");
      const config = yield* StationConfig;
      // An edit is taken only if it checks out as config.rs `parse_config` would have it.
      config.check = checkConfig;
      // What it starts for its agents runs with the variables set in it (ops/agent-env.ts).
      readAgentEnvFrom(() => config.raw());
      const place = () => {
        const s = cloud.state;
        return s && s.workspace && !cloud.removed() ? s : null;
      };
      const bound = () => place() !== null;
      // Session pages are still.fail cloud's (`<origin>/o/…`); other control planes have none to link to.
      // In the workspace its chat is in (docs/multi-workspace.md).
      const pageOf = (key: string) => {
        const s = place();
        const ws = store.getSession(key)?.ws ?? s?.workspace;
        return s && plane.spec().pages && (ws === s.workspace || cloud.membership(ws!) !== null) ? `${s.origin}/o/${ws}/${s.station}/${encode(key)}` : undefined;
      };

      // Each profile running the models its last check found besides those config.json names (the accounts, once made).
      let found = (_: string): readonly string[] | null => null;
      const settings = () => hubConfig(config.raw(), data, (id) => found(id));
      // The folders macOS protects (Documents, Desktop, Downloads, disks) through still.fail Helper: the drive's and
      // the directories people and agents name (ops/places.ts), never touched on the station's thread.
      const helperFiles = yield* HelperFolders;
      const places = new Places({ helper: helperFiles });
      // What other stations of the workspace share with this one, and what it shares (made below, once the accounts are).
      let sharing: Sharing | null = null;
      const borrowed = (p: unknown) => sharing?.borrowedSubscription(p) === true;
      // In sandboxes a subscription's login stays here: each process there is lent a short-lived one, as a borrowed
      // subscription's is (agents/sandbox.ts).
      const lentToSandbox = (p: any) => !borrowed(p) && p?.access?.kind === "subscription" && sandboxed(data);
      const hermes = new HermesDriver({ data });
      const codex = new CodexDriver({
        data,
        currentProfile: (id) => settings().profiles.find((p) => p.id === id),
        lent: {
          borrowed: (p) => borrowed(p) || lentToSandbox(p),
          write: (p) => (borrowed(p) ? sharing!.lendCodex(p) : sharing!.lendOwnCodex(p, lentFile(data, p.home))),
        },
      });
      // What the parts of the agents' side add (slack/module.ts): the connects' chats, their overview, and what they do
      // as the station takes its sessions up and as its workspaces change, in the order the agents need.
      const surfaceChats: ((connect: string) => ChatSurface | undefined)[] = [];
      const connectKinds = new Map<string, ConnectKind>();
      const along: Along[] = [];
      const cold = new ColdRooms(() => hub);
      const hub = new Hub({
        config: settings,
        store,
        // The connects' chats (Slack's: slack/module.ts, which says them below); the station's own chat is the hub's.
        chats: (id) => {
          for (const chats of surfaceChats) {
            const chat = chats(id);
            if (chat !== undefined) return chat;
          }
          return undefined;
        },
        drivers: [
          new ClaudeDriver({
            data,
            machineToken: (env, rejected) => accounts.machineToken(env, rejected),
            lent: {
              borrowed: (p) => borrowed(p) || (lentToSandbox(p) && p.machine !== true),
              token: (p, rejected) => (borrowed(p) ? sharing!.lendClaude(p, rejected) : accounts.claudeToken(p, rejected)),
            },
          }),
          codex,
          new DshDriver({ data }),
          new GrokDriver({ data }),
          new CursorDriver({ data }),
          new DevinDriver({ data }),
          hermes,
        ],
        mcpUrl: () => door?.url ?? "",
        internal: new InternalChat(),
        link: pageOf,
        workspaces: () => cloud.memberships().map((m) => m.workspace),
        cold,
        places,
      });
      // No turn until the agents' door is open: a runtime started before has no MCP endpoint, and Codex does not
      // connect to it again for that thread.
      hub.hold("starting");
      // Background jobs and web services: their agents told through the hub; a service's link is its session's page
      // with its port.
      const jobs = new Jobs({
        store,
        data,
        notify: (session, text) => {
          try {
            hub.notify(session, text);
          } catch (error) {
            log.warn("jobs", "job notice not given", { session, error: (error as Error).message });
          }
        },
        link: (session, job) => {
          const page = pageOf(session);
          return page ? `${page}?service=${encode(job)}` : null;
        },
      });
      const remote = new Remote({ data, store, jobs, notify: (session, text) => hub.notify(session, text), places: hub.places, bus: yield* Peers });
      // Measure only working chats, and only station-owned workspaces. A chat's remote workspaces are measured on the
      // machines that hold them; an offline or older station supplies no reading until it can answer.
      const workingRow = (row: NonNullable<ReturnType<typeof store.getSession>>, jobsRunning: Set<string>): boolean =>
        row.archivedAt === null && (row.running || hub.processState(row.key) === "running" || jobsRunning.has(row.key) || store.lastTurn(row.key)?.declared === "waiting");
      const working = (key: string): boolean => {
        const row = store.getSession(key);
        return row !== null && workingRow(row, new Set(store.jobsRunning().map((j) => j.sessionKey)));
      };
      const workspaceWatch: WorkspaceWatch = new WorkspaceWatch({
        data,
        clock: hub.clock,
        working,
        notify: (session, text) => hub.notify(session, text),
        readings: async () => {
          const jobsRunning = new Set(store.jobsRunning().map((j) => j.sessionKey));
          return (await Promise.all(store.liveSessions().filter((s) => workingRow(s, jobsRunning)).map(async (s) => {
            const found: WorkspaceReading[] = [];
            if (roomOf(data, s.workspace) !== null) {
              const size = remote.workspaceReader.size(s.workspace, workspaceWatch.limit(s.key, ""));
              if (size !== null) found.push({ session: s.key, station: "", name: "this station", path: s.workspace, ...size });
            }
            const targets = remote.workspaceTargets(s.key);
            if (targets) {
              const others = await Promise.all(targets.stations.map(async (station): Promise<WorkspaceReading | null> => {
                const size = await remote.workspaceSize(s.key, station, workspaceWatch.limit(s.key, station)).catch(() => null);
                return size ? { session: s.key, station, name: nameOf(cloud, station), ...size } : null;
              }));
              found.push(...others.filter((r): r is WorkspaceReading => r !== null));
            }
            return found;
          }))).flat();
        },
      });
      workspaceWatch.start();
      yield* Effect.addFinalizer(() => Effect.promise(() => workspaceWatch.close()));
      // What the agents run here, watched for the machine's memory (jobs/memory.ts): their agents told when it is much,
      // the largest stopped only when the machine is about to run out.
      const memory = liveMemory({ data, store, jobs, notify: (session, text) => hub.notify(session, text), clock: hub.clock });
      memory.start();
      yield* Effect.addFinalizer(() => Effect.promise(() => memory.close()));
      // Tasks of stations no longer in the workspace, or no longer allowed, stop: once the mesh is up, and as the roster
      // or the config changes.
      let roster: (() => void) | null = null;
      remote.bus.whenAttached(() => void (roster = followRoster(cloud, remote, config)));
      yield* Effect.addFinalizer(() => Effect.sync(() => roster?.()));
      hub.setJobs(jobs);
      // Ports of other stations forwarded here (mesh/peer-forward.ts), each its session's: through the mesh's way, once
      // it is up (`peers`, below).
      const meshSide = yield* MeshSide;
      const peers = meshSide.peers;
      const forwards = new Forwards({
        route: () => peers.route,
        resolve: (station) => {
          const { id } = peerNamed(cloud, station);
          return { id, name: nameOf(cloud, id) };
        },
        jobs: {
          job: (id) => {
            const job = store.getJob(id);
            return job ? { session: job.sessionKey, state: job.state, port: job.port } : null;
          },
          changes: (changed) => store.subscribe((change) => {
            if (change.type === "job" || change.type === "jobRemoved") changed(change.id);
          }),
        },
        clock: hub.clock,
      });
      hub.onClose((session) => {
        remote.closeSession(session);
        if (!store.getSession(session)) workspaceWatch.forget(session);
        computer.closeSession(session);
        forwards.closeSession(session);
        parts.endSession(session);
      });
      // How busy this station is, told to the others' station_list (`describe`): the host page's measurements, the
      // GPUs (looked at once now, so the first to ask need not wait), what runs here and the relay.
      const gpus = new Gpus();
      void gpus.read().catch(() => null);
      const net = meshSide.net;
      remote.setLoad(() =>
        measure({
          host,
          gpus,
          running: () => {
            const j = store.runningJobs();
            return { remoteTasks: j.remote, jobs: j.jobs, services: j.services, turns: hub.running() };
          },
          relay: () => net.seen(),
        }),
      );
      // What other stations' sessions ask of this one's chats: those of the workspace asked in (`ws`; none: any, once
      // xshare checked what is shared).
      const local = async (peer: string, request: any, ws: string | null = null) => {
        switch (request?.method) {
          case READ:
            return forPeer(hub, peer, request, ws);
          case FILE:
            return fileForPeer(hub, request, ws);
          case PUT:
            return putForPeer(hub, peer, request, ws);
          case CREATE:
            return createForPeer(hub, peer, request, ws);
          case NOTICE:
            return noticeForPeer(hub, peer, request, ws);
          default:
            return fromPeer(hub, peer, request, ws);
        }
      };
      // A station of the workspace asking for a session of another of its workspaces (`as`, docs/multi-workspace.md)
      // reaches what is shared with that one only.
      const inbox = async (peer: string, request: any, workspace?: string) =>
        typeof request?.as === "string" && workspace !== undefined && request.as !== workspace ? xshare.outside(peer, request, workspace) : local(peer, request, workspace ?? null);
      remote.setInbox(inbox);
      // Chats shared with other workspaces, and theirs shared with this one (docs/chat-share.md): their stations are
      // asked and heard through it, for those chats only.
      const xshare = new ChatShares({
        data, store, cloud,
        ask: (station, request) => remote.ask(station, request),
        link: (chat) => hub.link(chat) ?? null,
        // As its messages are headed; a chat not named yet by what was first said in it.
        title: (chat) => {
          let named = chat;
          try {
            named = sender(hub, chat)[0];
          } catch {}
          const first = named === chat ? (store.listThreads("", chat, null)[0]?.firstText ?? "") : "";
          return first.trim() !== "" ? Array.from(first.trim().split(/\s+/u).join(" ")).slice(0, 80).join("") : named;
        },
        touches: (request) => chatsTouched(hub, request),
        inbox: (peer, request) => local(peer, request),
        chatWs: (chat) => hub.wsOf(chat),
      });
      hub.onPeer((station, request) => xshare.send(station, request, (r) => remote.ask(station, r)));
      hub.onOutsideChats((ws) => xshare.borrowed(ws));
      remote.setOutside({ inside: (peer, request, ws) => xshare.inside(peer, request, ws), outside: (peer, request, ws) => xshare.outside(peer, request, ws) });

      // The agents' own hands on the screens: a session's view of one shows among its people as its chat.
      const computer = new Computer({
        hub: screens,
        base: () => {
          const s = place();
          return s && plane.spec().pages ? `${s.origin}/w/${s.workspace}/s/${s.station}` : null;
        },
        name: (session) => {
          let title = session;
          try {
            title = sender(hub, session)[0];
          } catch {}
          return `agent: ${title}`;
        },
      });
      // The profiles' homes elsewhere and the machine's runtime logins are the station's own too (ops/own.ts): never
      // reached through the drive, the device tools or a search.
      own.add(() => [...hub.config().profiles.map((p) => p.home), claudeCredentialsFile(process.env), codexAuthFile(process.env)]);
      const tools = [
        ...chatTools(hub),
        ...archiveTools(hub),
        ...remoteTools(remote),
        ...workspaceSizeTools(workspaceWatch, remote),
        ...jobTools(jobs, (key) => store.getSession(key)?.workspace ?? null, hub.places),
        ...screenTools(screens, () => {
          const s = place();
          return s && plane.spec().pages ? `${s.origin}/w/${s.workspace}/s/${s.station}` : null;
        }),
        // What macOS lets still.fail Helper do here, and a grant asked of a person (docs/remote-screens.md "Grants").
        ...permissionTools(grants, () => {
          const s = place();
          return s && plane.spec().pages ? `${s.origin}/w/${s.workspace}/s/${s.station}` : null;
        }),
        ...computerTools(computer),
        ...forwardTools(forwards),
      ];
      // The station's and the runtimes' versions, read at start and every few hours; updated from the pages, or by
      // itself while nothing runs and nothing is asked of it (auto update), watched or not.
      const updates = makeUpdates({
        app,
        data,
        config,
        // Where its releases are: still.fail cloud's origin, Comma's `/stations` (ControlPlane.releaseBase).
        origin: () => plane.releaseBase(),
        running: () => hub.running(),
      });
      // The packages of the modules the station installs itself, read and updated with the rest (a line each).
      updates.add(yield* ModulePackages);
      updates.start();
      // `stillfail update --beta|--stable` asks a running station by SIGHUP (run/channel-ask).
      control.on("hup", () => updates.answerChannelAsk());

      // Outside a workspace its agents do not reach out of it: their outward tools are refused.
      // So are those of a session of a workspace the station has left (docs/multi-workspace.md).
      const inItsWorkspace = (session: string) => {
        const ws = store.getSession(session)?.ws ?? null;
        return ws === null || cloud.membership(ws) !== null;
      };
      // The agents' tools, and those the station's parts add as they are made (parts.ts).
      const mcp = new McpEndpoint((token) => store.sessionByToken(token)?.key, () => [...tools, ...parts.allTools()], (session) => (bound() && inItsWorkspace(session) ? undefined : UNBOUND_REFUSAL));

      let taken = false;

      // Profiles, sign-ins, allowances and the machine's own logins; the Claude driver's machine token renewed by it.
      // (As the first of the station's workspaces it is in calls it, the home one first.)
      const hostName = (p: any) => {
        const host = p?.share?.host;
        return cloud.memberships().flatMap((m) => m.peers).find((x) => x?.id === host)?.name ?? host ?? null;
      };
      const accounts: Accounts = makeAccounts({
        data, store, config, hub, reviewUndecided: () => startReview(hub), codex: () => codex as any, hermes: () => hermes, following: () => events.inUse() || hub.anyRunning(), checkOnStart: true,
        workspaces: () => hub.workspaces(),
        shared: { status: (p) => sharing!.status(p), view: (p) => sharing?.profileView(p) ?? null, hostName },
      });
      found = accounts.found;
      accounts.start();
      sharing = new Sharing({
        data, config, cloud,
        ask: (station, workspace, request) => remote.ask(station, workspace === null ? request : { workspace, ...request }),
        agentHome: () => settings().agentHome,
        env: process.env as Record<string, string | undefined>,
        claudeToken: (p, rejected) => accounts.claudeToken(p, rejected),
        // In sandboxes no Codex here holds the refresh token: it is renewed here whenever it runs out.
        codexRenewRunning: async (id) => !sandboxed(data) && (await codex.renewLogin(id)),
        status: async (id) => { const h = await accounts.lentHealth(id); return { check: h.check ?? null, quota: h.quota ?? null }; },
        changed: () => events.overviewChanged(),
        recheck: () => accounts.recheckBorrowed(),
      });
      remote.setShares((peer, request, workspace) => sharing!.handle(peer, request, workspace));
      sharing.start();
      xshare.start();
      const platformView = (viewer: Viewer, lang: Lang) => overview({ store, hub, cloud, config: () => config.raw(), accounts, updates, connectKinds, rootView: (p) => rootViewThrough(p, helperFiles), modules: () => modules.listed(), ...(grants ? { permissions: (v: Viewer) => permissionsView(grants, v) } : {}) }, viewer, lang);
      // And the fields the station's parts add (parts.ts).
      const view = async (viewer: Viewer, lang: Lang) => ({ ...((await platformView(viewer, lang)) as object), ...(await parts.overviewOf(viewer, lang)) });

      hub.live.heldTold = (key, message) => events.heldTold(key, message);
      // A transcript's past is read by the readers, which keep where its reading stands (read/transcripts.ts): the live
      // view goes on from there, and gives a listener what it lacks from them, none of it read on the main thread.
      hub.live.history = {
        state: async (key) => (JSON.parse(await readers.read("transcriptState", { key }, "zh")) as { states: TailState[] | null }).states,
        page: async (key, before, limit, brief) => JSON.parse(await readers.read("timeline", { key, before: String(before), limit: String(limit), lang: "zh", ...(brief ? { brief: "1" } : {}) }, "zh")),
      };
      hub.threadList = async () => JSON.parse(await readers.read("threadList", {}, "zh"));
      hub.latestMessages = async (thread, limit) => JSON.parse(await readers.read("latestMessages", { thread, limit }, "zh"));
      hub.followRunning();
      // The readers say what runs, and which chats clients made: the hub's.
      readers.processes = () => hub.processes();
      readers.clientKeys = () => hub.clientKeys();
      events.follow({
        live: (key, from, last, send, brief) => {
          const id = hub.live.subscribe(key, from, last, send, brief);
          return () => hub.live.unsubscribe(key, id);
        },
        // The sessions at work, followed by the station itself: told to the streams that follow them, in brief.
        held: () => hub.live.held(),
        heldNow: (key) => hub.live.now(key),
        overview: view,
        processState: (key) => hub.processState(key),
        followed: () => accounts.followed(),
      });
      // A runtime installed or updated from the pages: the machine's logins read again.
      updates.onRuntimeChanged((kind, installed) => {
        void accounts.machine?.refresh();
        // Installed: the sessions whose start found it missing take what waits.
        if (installed) hub.installed(kind);
        // Codex updated: its app-servers of the old version are replaced (their files are gone).
        void codex.runtimeChanged().catch((error) => log.warn("agents::codex", "codex app-servers not checked after an update", { error: String(error) }));
      });
      // A session found its runtime not installed: the pages read it again (removed since they last did).
      hub.onRuntimeMissing((runtime) => updates.missing(runtime));
      // What the overview shows changes: told on the event streams.
      const unlistenOverview = [
        accounts.onChange(() => events.overviewChanged()),
        updates.changes(() => events.overviewChanged()),
        // macOS's grants to still.fail Helper (the station's page shows them as they change).
        grants?.onChange(() => events.overviewChanged()) ?? (() => {}),
        config.listen(() => (events.overviewChanged(), events.rowsChanged(null))),
        cloud.listen(() => events.overviewChanged()),
      ];

      // In a workspace, or out of it, as cloud.json says, from now on; and in which of them (docs/multi-workspace.md).
      let inWorkspace = bound();
      let joinedNow = new Set(cloud.memberships().filter((m) => !m.home).map((m) => m.workspace));
      let homeNow = cloud.home();
      const follow = async () => {
        const now = bound();
        const joined = new Set(cloud.memberships().filter((m) => !m.home).map((m) => m.workspace));
        // A new home workspace. One it had joined took over from a home it was taken out of: the old home's chats
        // (those that say no workspace) are said to be that one's, so they stay out of the new home's sight. Moved
        // (enrolled again elsewhere): its chats of the old home go along, as they always did.
        const home = cloud.home();
        if (home !== null && homeNow !== null && home !== homeNow) {
          if (joinedNow.has(home)) store.setSessionsWs(null, homeNow);
          else store.setSessionsWs(homeNow, null);
        }
        if (home !== null) homeNow = home;
        const left = [...joinedNow].filter((w) => !joined.has(w) && cloud.memberships()[0]?.workspace !== w);
        const back = [...joined].filter((w) => !joinedNow.has(w));
        joinedNow = joined;
        if (now && now === inWorkspace) {
          for (const ws of left) {
            log.warn("station", "out of a workspace it had joined: its sessions' runtimes end", { workspace: ws });
            await hub.leftWorkspace(ws);
          }
          for (const ws of back) hub.backIn(ws);
          // Its connects: those of a workspace left disconnect, those of one back connect.
          if (left.length > 0 || back.length > 0) for (const a of along) await a.changed?.();
        }
        if (now === inWorkspace) return;
        inWorkspace = now;
        if (now) {
          log.info("station", "in a workspace: connects, turns and jobs go on");
          for (const a of along) await a.joined?.();
          hub.recover();
          jobs.relaunch();
          hub.release("unbound");
        } else {
          const why = cloud.removed() ? "the station was removed from its workspace" : "the station is in no workspace";
          log.warn("station", "out of its workspace: ending the agents' runtimes, stopping jobs and services", { why });
          hub.hold("unbound");
          await hub.suspendAll();
          for (const a of along) await a.left?.();
          await jobs.stopAll(why);
        }
      };
      yield* plane.changes.pipe(
        Stream.runForEach(() => Effect.promise(follow)),
        Effect.forkScoped,
      );

      // Sandboxes of sessions nothing runs in, left by a process that ended some other way than going idle: stopped.
      yield* Effect.promise(() => hub.sweepSandboxes().catch(() => {})).pipe(
        Effect.repeat(Schedule.spaced(SWEEP_MS)),
        Effect.forkScoped,
      );

      let door: AgentsDoor | null = null;
      const peerRoute = () => peers.route;
      const partRoutes = () => parts.doorRoutes();
      let handing = false;
      // Taken up once the previous process is gone; then the door opens, and what was cut off resumes.
      const start = async () => {
        // The station made whole (its parts, which say what they do along: `along`), then the process before it gone.
        await Effect.runPromise(Effect.gen(function* () {
          if (!(yield* SubscriptionRef.get(up))) yield* SubscriptionRef.changes(up).pipe(Stream.filter((now) => now), Stream.runHead);
        }));
        await previous;
        mkdirSync(run, { recursive: true });
        writeFileSync(join(run, "hub.json"), JSON.stringify({ pid: process.pid }) + "\n");
        if (!inWorkspace) hub.hold("unbound");
        await hub.takeUp();
        // The launcher's socket; on its own, as the launcher's ports.rs would: the port config.json names; else the one
        // remembered (the agents left running know it), 4750 on the machine's own data directory, any free one.
        const named = config.raw()?.http?.port;
        const notified = (authorization: string | undefined, body: Buffer) => notifyEndpoint(jobs, authorization, body);
        const screened = (authorization: string | undefined, body: Buffer) => screenEndpoint(jobs, authorization, body);
        if (control.mcpFd !== undefined) door = await openAgentsDoor({ fd: control.mcpFd }, mcp, notified, peerRoute, partRoutes, screened);
        // Behind the launcher's entrance (launcher.ts `ports`): any port here, its port the one agents are told.
        else if (control.ports) door = await openAgentsDoor({ port: 0, shown: control.ports.mcp }, mcp, notified, peerRoute, partRoutes, screened);
        else {
          const remembered = rememberedMcpPort(data);
          const tries = portsToTry(named === undefined ? undefined : Number(named), remembered, 4750, ownData(data));
          for (const [i, port] of tries.entries()) {
            try {
              door = await openAgentsDoor({ port }, mcp, notified, peerRoute, partRoutes, screened);
              break;
            } catch (error) {
              // The one remembered is passed over whatever keeps it; the usual one only when it is taken.
              const passed = (port === remembered && port !== 4750) || (error as NodeJS.ErrnoException).code === "EADDRINUSE";
              if (!passed || i === tries.length - 1) throw error;
            }
          }
          writeFileSync(mcpPortFile(data), `{"port":${door!.port}}\n`);
        }
        const opened = door!;
        jobs.setNotifyUrl(opened.url.replace(/\/mcp$/, "/jobs/notify"));
        // What it starts runs in sandboxes while config.json says so; their programs reach the door at its port there.
        placeIn(data, () => sandboxConfig(config.raw()), () => [opened.port], settings().agentHome);
        // Taken over and serving: the launcher's entrance comes here now (not before: launcher/src/lifecycle.rs).
        control.serving("mcp", opened.port);
        log.info("station", "agents' door open", { url: opened.url });
        // Processes taken up that were told another address start again (the port could not be had again).
        hub.toolsAt(opened.url);
        parts.doorOpen(opened.url);
        taken = true;
        hub.release("starting");
        if (inWorkspace) {
          for (const a of along) await a.taken?.();
          hub.recover();
          jobs.relaunch();
        } else if (cloud.removed()) {
          // Removed, and the station stopped before it stopped its jobs (or crashed): what still runs is ended now.
          await jobs.stopAll("the station was removed from its workspace");
        }
      };
      yield* Effect.forkScoped(Effect.promise(() => start().catch((e) => {
        log.error("hub", "the agents' side did not start", { error: (e as Error).message });
        control.failed(`the agents' side did not start: ${(e as Error).message}`);
      })));


      // What the chats' people hear about while no client of theirs runs: pushed by the control plane.
      const notifier = new Notifier(store, readers, cloud, (notices, ws) => Effect.runPromise(plane.notify(notices, ws)));

      // What runs on a clock here (on the hub's): ended at the handover, below.
      const time = new Fibers("station", hub.clock);

      // Chats idle long enough go to the archive: looked at when the next one comes due, and every ten minutes for what
      // was idle but not done (a job up, unread, at a block) and is done since, or the setting changed.
      const archiving = () => {
        let next: number | null = null;
        try {
          next = autoArchive(hub, hub.now());
        } catch (error) {
          log.warn("hub", "auto-archiving failed", { error: (error as Error).message });
        }
        time.after(Math.min(600_000, next === null ? Infinity : next - hub.now()), archiving);
      };
      time.after(60_000, archiving);

      // Chats archived long enough keep only their history and the files sent in them: looked at when the next one
      // comes due, and every hour for the setting changed.
      const emptying = async () => {
        let next: number | null = null;
        try {
          next = await expireArchived(hub, hub.now());
        } catch (error) {
          log.warn("hub", "emptying long-archived workspaces failed", { error: (error as Error).message });
        }
        time.after(Math.min(3_600_000, next === null ? Infinity : next - hub.now()), emptying);
      };
      time.after(300_000, emptying);

      // The disk of the station's data low: the mirrors of other stations' tasks not in use go, then archived
      // workspaces before their time (ops/disk.ts).
      const relieving = async () => {
        const free = () => {
          try {
            return diskFree(data);
          } catch {
            return Infinity;
          }
        };
        try {
          if (free() < DISK_LOW_BYTES) {
            await remote.relieve(hub.now());
            await relieveArchived(hub, free);
          }
        } catch (error) {
          log.warn("hub", "making room on the disk failed", { error: (error as Error).message });
        }
        time.after(DISK_EVERY_MS, relieving);
      };
      time.after(DISK_EVERY_MS, relieving);

      // The threads a station before wrote out to their archive files, back into the database a few at a time
      // (store.ts `bringInArchived`), once the devices have come back from the start.
      let broughtIn = 0;
      const bringingIn = () => {
        let left: number;
        try {
          const step = store.bringInArchived(BRING_IN);
          broughtIn += step.brought;
          left = step.left;
        } catch (error) {
          log.warn("store", "archived threads not brought back into the database", { error: (error as Error).message });
          return;
        }
        if (left > 0) time.after(1_000, bringingIn);
        else if (broughtIn > 0) log.info("store", "the threads archived to files are back in the database", { n: broughtIn });
      };
      time.after(120_000, bringingIn);

      // What the Rust station's archiving left (the transcripts kept twice): once, when the devices have come back.
      time.after(180_000, () => cold.finishLegacyCopies());

      // The archive review turned on, or given another model: the done chats no decision has answered are reviewed then,
      // not only the ones that end all_done from now on; and once after the start (the profiles' checks read by then).
      const reviewing = () => void reviewUndecided(hub).catch((error) => log.warn("hub", "reviewing done chats failed", { error: (error as Error).message }));
      let rule = hub.config().automaticDecisions.completion;
      const unlistenRule = config.listen(() => {
        const now = hub.config().automaticDecisions.completion;
        const changed = now.enabled && (!rule.enabled || now.model !== rule.model);
        rule = now;
        if (changed) reviewing();
      });
      time.after(120_000, reviewing);

      // A drain (SIGUSR1), asked before a restart: said at once. Nothing need wait for the running turns: stopping hands
      // them over to the next start (their runtimes run on under their runners), and holding turns meanwhile kept
      // people's messages waiting for up to 10 minutes.
      control.on("drain", () => {
        log.info("station", "drained: running turns are handed over to the next start");
        writeFileSync(join(run, "drained"), "idle\n");
        control.drained("idle");
      });

      // Stopping hands the sessions over, whether to the next process now (handover) or the next start: their runtimes
      // run on under their runners.
      yield* Effect.addFinalizer(() =>
        Effect.promise(async () => {
          if (handing) return;
          handing = true;
          await time.close();
          await sharing?.close();
          await xshare.close();
          unlistenRule();
          notifier.close();
          await door?.close(30_000);
          await forwards.close();
          try {
            await hub.handOver();
          } catch (error) {
            log.warn("hub", "sessions not handed over; they resume the usual way", { error: (error as Error).message });
            await hub.shutdown();
          }
          await jobs.shutdown();
          await updates.close();
          await accounts.close();
          for (const stop of unlistenOverview) stop();
          if (existsSync(join(run, "hub.json"))) {
            try {
              if (JSON.parse(readFileSync(join(run, "hub.json"), "utf8")).pid === process.pid) rmSync(join(run, "hub.json"), { force: true });
            } catch {}
          }
        }),
      );
      const self = Agents.of({ pageOf, previousGone: previous, hub, jobs, remote, mcp, config, updates, accounts, sharing: sharing!, xshare, peers, forwards, overview: view, surfaces: (chats) => void surfaceChats.push(chats), connectKind: (kind, view) => void connectKinds.set(kind, view), connectKinds, along: (a) => void along.push(a), taken: () => taken, bound, cloud, net, helperFiles, place: () => { const s = place(); return s ? { origin: s.origin, workspace: s.workspace, station: s.station, name: s.name } : null; } });
      // The admin API asks for the agents' side as a request comes (services.ts AgentsSide); its routes are a part.
      (yield* AgentsSide).current = self;
      // And what the mesh asks of it (services.ts MeshSide).
      meshSide.outside = xshare;
      meshSide.forwarded = (port) => forwards.forwarded(port);
      meshSide.runtimes = () => hub.config().profiles.flatMap((p) => p.runtimes);
      parts.routes(agentsRoutes(self, { store, events }));
      return self;
    }),
  );
