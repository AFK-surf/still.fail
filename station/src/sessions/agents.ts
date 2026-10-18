// The agents' side of the station (server.rs `App::start`): the hub with its drivers, background jobs, tasks for other
// stations, the agents' tools and their door (/mcp). Made here and given to the rest; nothing else starts an agent.
//
// What the previous station process ran goes on (docs/station-ts.md, 已定 1): a station that stops hands its sessions
// over (run/handover.json) and the next takes them up, runtimes and all, from their runners. Under the launcher the
// next process is up before the previous one hands over: it takes up only once that one is gone (run/hub.json says
// which process holds the sessions), and opens the agents' door only then, so no call reaches a hub without its session.
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { Context, Effect, Layer, Stream } from "effect";
import { Fibers, wall } from "../ops/fibers.ts";
import { ClaudeDriver } from "../agents/claude.ts";
import { CodexDriver } from "../agents/codex.ts";
import { DshDriver } from "../agents/dsh.ts";
import { Jobs, notifyEndpoint } from "../jobs/jobs.ts";
import { Remote, followRoster } from "../jobs/remote.ts";
import { ConfigFile } from "../ops/config.ts";
import type { Control } from "../ops/launcher.ts";
import { log } from "../ops/log.ts";
import { mcpPortFile, ownData, portsToTry, rememberedMcpPort } from "../ops/files.ts";
import { AdminHost, ControlPlane, Events, Grants, HelperFolders, Key, ModulePackages, Modules, Own, Parts, Paths, Peers, Previous, Readers, ScreenRegistry, StationConfig, Store } from "../services.ts";
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
import { endedNotice, loginTools, promptNotice } from "../tools/login.ts";
import { Logins } from "../logins/index.ts";
import { readOnly } from "../mesh/credential.ts";
import { McpEndpoint, UNBOUND_REFUSAL } from "../tools/mcp.ts";
import { remoteTools } from "../tools/remote.ts";
import { UsageCounter } from "../usage/counter.ts";
import { Search } from "../search/search.ts";
import { FileSearch } from "../search/files.ts";
import { rootsOf } from "../drive/drive.ts";
import { SEARCH, searchForPeer, searchTools } from "../tools/search.ts";
import { sessionUsage } from "../read/usage.ts";
import { type Accounts, checkConfig, makeAccounts } from "../accounts/index.ts";
import { Sharing } from "../share/index.ts";
import { ChatShares } from "../xshare/index.ts";
import { overview } from "../api/overview.ts";
import { rootViewThrough } from "../drive/drive.ts";
import { type SlackParts, makeConnections } from "../slack/index.ts";
import type { Viewer } from "../mesh/credential.ts";
import type { Lang } from "../ops/i18n.ts";
import { type Updates, makeUpdates } from "../updates/updates.ts";
import { hubConfig } from "./config.ts";
import { inBrief } from "./live.ts";
import { ColdRooms } from "./cold.ts";
import { Hub } from "./hub.ts";
import { InternalChat } from "./internal.ts";
import { autoArchive } from "./lifecycle.ts";
import { fromPeer, sender } from "./messages.ts";
import { CREATE, NOTICE, createForPeer, noticeForPeer } from "./opened.ts";
import { chatsTouched, forPeer, READ } from "./others.ts";
import { FILE, fileForPeer, PUT, putForPeer } from "./peer-files.ts";
import { reviewUndecided, startReview } from "./review.ts";
import { readAgentEnvFrom } from "../ops/agent-env.ts";

/// server.rs `encode` (encodeURIComponent).
const encode = encodeURIComponent;

export type AgentsParts = {
  /// The agents' predecessor-exit wait, also used before binding the mesh socket.
  previousGone: Promise<void>;
  hub: Hub;
  jobs: Jobs;
  remote: Remote;
  mcp: McpEndpoint;
  config: ConfigFile;
  usage: UsageCounter;
  /// What a search finds on this station (docs/search.md).
  search: Search;
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
  /// The station's logins to command-line tools (docs/remote-login.md).
  logins: Logins;
  slack: SlackParts;
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

      const settings = () => hubConfig(config.raw(), data);
      // The folders macOS protects (Documents, Desktop, Downloads, disks) through still.fail Helper: the drive's and
      // the directories people and agents name (ops/places.ts), never touched on the station's thread.
      const helperFiles = yield* HelperFolders;
      const places = new Places({ helper: helperFiles });
      // What other stations of the workspace share with this one, and what it shares (made below, once the accounts are).
      let sharing: Sharing | null = null;
      const borrowed = (p: unknown) => sharing?.borrowedSubscription(p) === true;
      const codex = new CodexDriver({
        data,
        currentProfile: (id) => settings().profiles.find((p) => p.id === id),
        lent: { borrowed, write: (p) => sharing!.lendCodex(p) },
      });
      const hub = new Hub({
        config: settings,
        store,
        // The connects' Slack (made below); the station's own chat is the hub's.
        chats: (id) => slack.chats(id),
        drivers: [
          new ClaudeDriver({ data, machineToken: (env, rejected) => accounts.machineToken(env, rejected), lent: { borrowed, token: (p, rejected) => sharing!.lendClaude(p, rejected) } }),
          codex,
          new DshDriver({ data }),
        ],
        mcpUrl: () => door?.url ?? "",
        internal: new InternalChat(),
        link: pageOf,
        workspaces: () => cloud.memberships().map((m) => m.workspace),
        cold: new ColdRooms(() => hub),
        places,
      });
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
      // Tasks of stations no longer in the workspace, or no longer allowed, stop: once the mesh is up, and as the roster
      // or the config changes.
      let roster: (() => void) | null = null;
      remote.bus.whenAttached(() => void (roster = followRoster(cloud, remote, config)));
      yield* Effect.addFinalizer(() => Effect.sync(() => roster?.()));
      hub.setJobs(jobs);
      // Ports of other stations forwarded here (mesh/peer-forward.ts), each its session's: through the mesh's way, once
      // it is up (`peers`, below).
      const peers: { route: PeerRoute | null } = { route: null };
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
        computer.closeSession(session);
        forwards.closeSession(session);
      });
      // How busy this station is, told to the others' station_list (`describe`): the host page's measurements, the
      // GPUs (looked at once now, so the first to ask need not wait), what runs here and the relay.
      const gpus = new Gpus();
      void gpus.read().catch(() => null);
      const net = new Net();
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
          case SEARCH:
            return searchForPeer({ search, link: (session) => hub.link(session) }, request, ws, cloud.home());
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
      // The station's logins to command-line tools (docs/remote-login.md): each told on the event streams as it changes;
      // one an agent started tells that agent as it ends, its cards closed.
      const logins = new Logins({ data, clock: hub.clock });
      const loginLink = (session: string | null, id: string) => {
        const s = place();
        if (!s || !plane.spec().pages) return null;
        const ws = (session ? store.getSession(session)?.ws : null) ?? s.workspace;
        return `${s.origin}/w/${ws}/s/${s.station}/login/${encode(id)}`;
      };
      /// The logins whose agent was told they ask something (once a time they do).
      const asking = new Set<string>();
      const unlistenLogins = [
        logins.changes((change) => {
          const login = logins.get(change.login);
          if (!login) return;
          events.machineLogins({ login }, { login: Logins.limited(login) }, readOnly, `login\0${login.id}`);
          // Asking something again after its person's browser step (az picking a subscription, say): its agent answers.
          const asks = login.waiting && login.endedAt === undefined && logins.hadBrowserStep(login.id);
          if (asks && !asking.has(login.id) && login.chat) {
            try {
              hub.notify(login.chat, promptNotice(logins, login, loginLink(login.chat, login.id)));
            } catch (error) {
              log.warn("logins", "an agent was not told its login asks something", { login: login.id, error: (error as Error).message });
            }
          }
          if (asks) asking.add(login.id);
          else asking.delete(login.id);
        }),
        // Told: the agent that started it, and each that posted its card (one may post a card for a login under way).
        logins.onEnded((login, starter) => {
          let carded: string[] = [];
          try {
            carded = store.closeLoginCards(login.id);
          } catch (error) {
            log.warn("logins", "a login's cards were not closed", { login: login.id, error: (error as Error).message });
          }
          for (const session of new Set([...(starter.chat ? [starter.chat] : []), ...carded])) {
            try {
              hub.notify(session, endedNotice(login, loginLink(session, login.id)));
            } catch (error) {
              log.warn("logins", "an agent was not told a login ended", { login: login.id, session, error: (error as Error).message });
            }
          }
        }),
      ];
      // The profiles' homes elsewhere and the machine's runtime logins are the station's own too (ops/own.ts): never
      // reached through the drive, the device tools or a search.
      own.add(() => [...hub.config().profiles.map((p) => p.home), claudeCredentialsFile(process.env), codexAuthFile(process.env)]);
      // What a search finds here, looked for as it is asked (docs/search.md): the machine's files too.
      const search = new Search({
        data,
        files: new FileSearch({
          protect: () => own.paths(),
          roots: (ws) => rootsOf(config.raw(), ws),
          personal: () => config.raw()?.search?.personal === true,
          // Documents, Desktop and Downloads through still.fail Helper, where it holds their grant (looked at in the
          // background where not known yet; nothing asks for one on a search's behalf).
          helper: helperFiles
            ? {
                granted: (tops) => {
                  const unknown = tops.filter((t) => helperFiles.known(t) === undefined);
                  if (unknown.length > 0) helperFiles.check(unknown);
                  return tops.filter((t) => helperFiles.known(t)?.state === "granted");
                },
                search: (top, query, most, protect) => helperFiles.search(top, query, most, protect),
              }
            : null,
        }),
      });
      const tools = [
        ...chatTools(hub),
        ...archiveTools(hub),
        ...remoteTools(remote),
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
        ...loginTools({
          logins: () => logins,
          // The chat's starter: whom the agent works for.
          starter: (session) => {
            const row = store.getSession(session);
            const email = row?.createdBy ?? "";
            // Its chat's name; one not named yet, by what was first said in it (as a shared chat is titled).
            let chatTitle: string | null = null;
            try {
              chatTitle = sender(hub, session)[0];
            } catch {}
            if (chatTitle === null || chatTitle === session) {
              const first = store.listThreads("", session, null)[0]?.firstText?.trim() ?? "";
              chatTitle = first !== "" ? Array.from(first.split(/\s+/u).join(" ")).slice(0, 80).join("") : null;
            }
            return { by: { email, name: readers.names.get(email) ?? "" }, workspace: row?.ws ?? place()?.workspace ?? null, chat: session, chatTitle };
          },
          link: (session, id) => loginLink(session, id),
        }),
      ];
      tools.push(...searchTools({
        search,
        workspaceOf: (session) => {
          const row = store.getSession(session);
          if (!row) return null;
          const home = cloud.home();
          return { workspace: row.ws ?? home ?? "", home: row.ws === null || row.ws === home };
        },
        link: (session) => hub.link(session),
        stations: async (workspace) => {
          const roster = await remote.ask("", { method: "peers", workspace });
          const own = place()?.station ?? "";
          return (Array.isArray(roster?.stations) ? roster.stations : [])
            .filter((e: any) => typeof e?.id === "string" && e.id !== "")
            .map((e: any) => ({ id: e.id, name: typeof e.name === "string" ? e.name : e.id, here: e.id === own }));
        },
        ask: (station, request) => remote.ask(station, request),
      }));
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

      // The connects' Slack: connected while the station is in its workspace, once the sessions are taken up (a
      // Socket Mode event goes to one connection of an app; two processes' would split them).
      const slack: SlackParts = makeConnections({
        data, store, config, receive: (connect, event) => hub.receive(connect, event), bound: () => taken && bound(),
        inWorkspace: (ws) => ws === null || cloud.membership(ws) !== null,
      });
      let taken = false;
      // The names the pages show of Slack people and channels are the readers' (from the names book); a connection
      // looks up those it does not know yet as it hears of them: who wrote, and where.
      const learn = (thread: number, people: string[]) => {
        const t = store.getThread(thread);
        if (t === null || t.surface === "ember") return;
        const connect = store.threadSessions(thread).map((m) => m.connect).find((c) => c !== "ember");
        const chat = connect === undefined ? undefined : slack.chat(connect);
        if (chat === undefined) return;
        chat.knownChannel?.(t.channel);
        for (const user of people) chat.knownPerson?.(user);
      };
      const unlearn = store.subscribe((change) => {
        if (change.type === "thread") learn(change.id, [...new Set(change.entries.filter((e) => e.authorKind === "person").map((e) => e.author))]);
      });
      // A connect connected: the Slack threads people read lately, learned once.
      const learned = new Set<string>();
      const unlearnConnected = slack.onChange(() => {
        for (const c of slack.connects()) {
          if (learned.has(c.id) || slack.state(c.id)?.state !== "connected") continue;
          learned.add(c.id);
          for (const t of store.listThreads("", null, null).slice(0, 200)) {
            if (t.sessions.some((m) => m.connect === c.id)) learn(t.thread.id, [...t.people.flatMap((p) => (p.startsWith(`slack:${c.id}:`) ? [p.slice(`slack:${c.id}:`.length)] : []))]);
          }
        }
      });

      // Profiles, sign-ins, allowances and the machine's own logins; the Claude driver's machine token renewed by it.
      const hostName = (p: any) => {
        const host = p?.share?.host;
        return cloud.state?.peers.find((x) => x?.id === host)?.name ?? host ?? null;
      };
      const accounts: Accounts = makeAccounts({
        data, store, config, hub, reviewUndecided: () => startReview(hub), codex: () => codex as any, following: () => events.inUse(), checkOnStart: true,
        workspaces: () => hub.workspaces(),
        shared: { status: (p) => sharing!.status(p), view: (p) => sharing?.profileView(p) ?? null, hostName },
      });
      accounts.start();
      sharing = new Sharing({
        data, config, cloud,
        // What the station shares is its home workspace's (docs/multi-workspace.md).
        ask: (station, request) => remote.ask(station, { workspace: cloud.home() ?? undefined, ...request }),
        agentHome: () => settings().agentHome,
        env: process.env as Record<string, string | undefined>,
        claudeToken: (p, rejected) => accounts.claudeToken(p, rejected),
        codexRunning: (id) => codex.running(id),
        status: (id) => { const h = accounts.health(id); return { check: h.check ?? null, quota: h.quota ?? null }; },
        changed: () => events.overviewChanged(),
        recheck: () => accounts.recheckBorrowed(),
      });
      remote.setShares(async (peer, request, workspace) => {
        if (workspace !== undefined && workspace !== cloud.home()) throw new Error("this station shares profiles and skills with its home workspace's stations only");
        return sharing!.handle(peer, request);
      });
      sharing.start();
      xshare.start();
      const slackView = {
        connection: (c: any) => slack.state(c.id),
        teams: (viewer: Viewer) => slack.overview(viewer.email).slackTeams,
        apps: (viewer: Viewer) => slack.overview(viewer.email).slackApps,
      };
      const platformView = (viewer: Viewer, lang: Lang) => overview({ store, hub, cloud, config: () => config.raw(), accounts, updates, slack: slackView, rootView: (p) => rootViewThrough(p, helperFiles), modules: () => modules.listed(), ...(grants ? { permissions: (v: Viewer) => permissionsView(grants, v) } : {}) }, viewer, lang);
      // And the fields the station's parts add (parts.ts).
      const view = async (viewer: Viewer, lang: Lang) => ({ ...((await platformView(viewer, lang)) as object), ...(await parts.overviewOf(viewer, lang)) });

      // The readers say what runs, and which chats clients made: the hub's.
      readers.processes = () => hub.processes();
      readers.clientKeys = () => hub.clientKeys();
      events.follow({
        live: (key, from, last, send, brief) => {
          const id = hub.live.subscribe(key, from, last, brief ? inBrief(send) : send);
          return () => hub.live.unsubscribe(key, id);
        },
        overview: view,
        processState: (key) => hub.processState(key),
        followed: () => accounts.followed(),
        loginScreen: (id, send) => logins.follow(id, send),
      });
      // A runtime installed or updated from the pages: the machine's logins read again.
      updates.onRuntimeChanged(() => {
        void accounts.machine?.refresh();
        // Codex updated: its app-servers of the old version are replaced (their files are gone).
        void codex.runtimeChanged().catch((error) => log.warn("agents::codex", "codex app-servers not checked after an update", { error: String(error) }));
      });
      // What the overview shows changes: told on the event streams.
      const unlistenOverview = [
        accounts.onChange(() => events.overviewChanged()),
        // The sidebar names connects and their Slack workspaces.
        slack.onChange(() => (events.overviewChanged(), events.rowsChanged(null))),
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
          if (left.length > 0 || back.length > 0) await slack.reconcile();
        }
        if (now === inWorkspace) return;
        inWorkspace = now;
        if (now) {
          log.info("station", "in a workspace: connects, turns and jobs go on");
          await slack.reconcile();
          hub.recover();
          jobs.relaunch();
          hub.release("unbound");
        } else {
          const why = cloud.removed() ? "the station was removed from its workspace" : "the station is in no workspace";
          log.warn("station", "out of its workspace: ending the agents' runtimes, stopping jobs and services", { why });
          hub.hold("unbound");
          await hub.suspendAll();
          await slack.stopAll();
          await jobs.stopAll(why);
        }
      };
      yield* plane.changes.pipe(
        Stream.runForEach(() => Effect.promise(follow)),
        Effect.forkScoped,
      );

      let door: AgentsDoor | null = null;
      const peerRoute = () => peers.route;
      let handing = false;
      // Taken up once the previous process is gone; then the door opens, and what was cut off resumes.
      const start = async () => {
        await previous;
        mkdirSync(run, { recursive: true });
        writeFileSync(join(run, "hub.json"), JSON.stringify({ pid: process.pid }) + "\n");
        if (!inWorkspace) hub.hold("unbound");
        await hub.takeUp();
        // The launcher's socket; on its own, as the launcher's ports.rs would: the port config.json names; else the one
        // remembered (the agents left running know it), 4750 on the machine's own data directory, any free one.
        const named = config.raw()?.http?.port;
        const notified = (authorization: string | undefined, body: Buffer) => notifyEndpoint(jobs, authorization, body);
        if (control.mcpFd !== undefined) door = await openAgentsDoor({ fd: control.mcpFd }, mcp, notified, peerRoute);
        // Behind the launcher's entrance (launcher.ts `ports`): any port here, its port the one agents are told.
        else if (control.ports) door = await openAgentsDoor({ port: 0, shown: control.ports.mcp }, mcp, notified, peerRoute);
        else {
          const remembered = rememberedMcpPort(data);
          const tries = portsToTry(named === undefined ? undefined : Number(named), remembered, 4750, ownData(data));
          for (const [i, port] of tries.entries()) {
            try {
              door = await openAgentsDoor({ port }, mcp, notified, peerRoute);
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
        // Taken over and serving: the launcher's entrance comes here now (not before: launcher/src/lifecycle.rs).
        control.serving("mcp", opened.port);
        log.info("station", "agents' door open", { url: opened.url });
        // Processes taken up that were told another address start again (the port could not be had again).
        hub.toolsAt(opened.url);
        taken = true;
        if (inWorkspace) {
          await slack.reconcile();
          if (slack.connects().length === 0) log.warn("station", "no connect is connected; add or enable one in the workspace's settings");
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

      // What the agents spent, read from their transcripts: now, and after each turn ends.
      const usage = new UsageCounter({ store, config: () => ({ dataDir: data, profiles: settings().profiles }), clock: hub.clock });
      usage.start();
      // An execution's details show its calls as counted here, as the usage page does, and are told when more are.
      hub.live.countWith({ of: (key) => sessionUsage(store.usageOfSession(key)), ask: () => usage.soon() });
      search.start();
      const unsubscribeCounted = store.subscribe((change) => {
        if (change.type === "usage") hub.live.usageCounted();
      });

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
          for (const stop of unlistenLogins) stop();
          await logins.close();
          await sharing?.close();
          await xshare.close();
          unlistenRule();
          notifier.close();
          // Slack's events go to the next process from now on.
          unlearn();
          unlearnConnected();
          await slack.close();
          await door?.close(30_000);
          await forwards.close();
          try {
            await hub.handOver();
          } catch (error) {
            log.warn("hub", "sessions not handed over; they resume the usual way", { error: (error as Error).message });
            await hub.shutdown();
          }
          await jobs.shutdown();
          unsubscribeCounted();
          await usage.stop();
          await search.stop();
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
      return Agents.of({ pageOf, previousGone: previous, hub, jobs, remote, mcp, config, usage, search, updates, accounts, sharing: sharing!, xshare, peers, forwards, logins, slack, overview: view, cloud, net, helperFiles, place: () => { const s = place(); return s ? { origin: s.origin, workspace: s.workspace, station: s.station, name: s.name } : null; } });
    }),
  );
