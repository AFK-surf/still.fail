// GET /overview (admin/views.rs `overview`): the station as its settings pages show it — still.fail cloud, connects,
// profiles, the agents' processes, counts, the disk, logins, updates — as the viewer sees it. Answered on the main
// thread from what is in memory and the config; told again on /events when it changes (`overview`).
import { statfsSync } from "node:fs";
import { homedir } from "node:os";
import type { Accounts } from "../accounts/index.ts";
import type { Cloud } from "../cloud/state.ts";
import { type Viewer, managesStation, readOnly } from "../mesh/credential.ts";
import { platform } from "../platform/index.ts";
import type { Lang } from "../ops/i18n.ts";
import type { Hub } from "../sessions/hub.ts";
import type { Store } from "../store/store.ts";
import type { Updates } from "../updates/updates.ts";
import { type RootView, rootView, rootsOf } from "../drive/drive.ts";
import { sees } from "../store/rows.ts";
import { titleOf } from "../read/views.ts";
import { policyView } from "../sessions/archive-policy.ts";
import { agentEnvView } from "./routes/agent-env.ts";
import { networkView } from "../mesh/settings.ts";
import { contextView } from "./routes/context.ts";
import { diagnosticsView } from "./routes/diagnostics.ts";
import type { ConnectKind } from "../connects/connections.ts";

export type OverviewDeps = {
  store: Store;
  hub: Hub;
  cloud: Cloud;
  config: () => any;
  accounts?: Accounts;
  updates?: Updates;
  /// How each kind's connects show (connects/part.ts), by kind; a kind not there shows as just its config.
  connectKinds?: Map<string, ConnectKind>;
  /// What macOS lets still.fail Helper do here, as the viewer is told it (routes/permissions.ts); none where there is no
  /// helper (not a Mac), or before the first look.
  permissions?: (viewer: Viewer) => unknown;
  /// A pinned root as the drive shows it (drive.ts `rootViewThrough`: one in a folder macOS protects by what still.fail
  /// Helper's grant is known to be, never listed by the station); default `rootView`.
  rootView?: (path: string) => RootView;
  /// The modules beside the station (modules/modules.ts), each named and whether it runs now.
  modules?: () => { id: string; running: boolean }[];
};

/// This station's link to still.fail cloud, as the pages show it (server.rs MeshFile::status): in the viewer's workspace
/// (docs/multi-workspace.md), its home one for no one in particular.
export function meshStatus(cloud: Cloud, viewer?: Viewer): Record<string, unknown> {
  const s = cloud.state;
  if (s === null) return { state: "off", origin: null, station: null, workspace: null, workspaceId: null, name: null };
  const m = viewer === undefined ? null : cloud.membership(viewer.workspace);
  const v: Record<string, unknown> = {
    state: s.removed_at !== undefined ? "removed" : "running",
    origin: s.origin ?? null,
    station: s.station ?? null,
    workspace: m?.workspace_name ?? s.workspace_name ?? null,
    workspaceId: m?.workspace ?? s.workspace ?? null,
    name: m?.name ?? s.name ?? null,
  };
  if (s.removed_at !== undefined) v.removedAt = s.removed_at;
  return v;
}

/// Memory of each recorded runtime process group (kB).
async function processMemory(pgids: number[]): Promise<Map<number, number>> {
  return pgids.length === 0 ? new Map() : platform.groupMemory(pgids);
}

/// processMemory, as measured within MEMORY_KEPT_MS for the same groups: every overview (each viewer's, at each change)
/// asked it of `ps` anew.
const MEMORY_KEPT_MS = 5_000;
const memoryKept = new WeakMap<object, { at: number; pgids: string; memory: Map<number, number> }>();
async function keptMemory(d: OverviewDeps, pgids: number[]): Promise<Map<number, number>> {
  const key = pgids.join(",");
  const kept = memoryKept.get(d.store);
  const now = d.store.now();
  if (kept !== undefined && kept.pgids === key && now - kept.at < MEMORY_KEPT_MS) return kept.memory;
  const memory = await processMemory(pgids);
  memoryKept.set(d.store, { at: now, pgids: key, memory });
  return memory;
}

/// The data disk's room: what clients warn of when it runs low.
function diskRoom(path: string): unknown {
  try {
    const s = statfsSync(path);
    return { freeBytes: s.bavail * s.bsize, totalBytes: s.blocks * s.bsize };
  } catch {
    return null;
  }
}

export async function overview(d: OverviewDeps, viewer: Viewer, lang: Lang): Promise<unknown> {
  const raw = d.config() ?? {};
  // What is of the viewer's workspace (docs/multi-workspace.md): its chats, and the connects added in it.
  // (Counted by connect from an index, not every session's row; the processes not cold are the hub's few.)
  const counted = d.store.sessionCounts().filter((c) => sees(viewer, c.ws));
  const sessionsOf = (connect: string | null) => counted.reduce((n, c) => (connect === null || c.connect === connect ? n + c.n : n), 0);
  const states = [...d.hub.processes()].filter(([key]) => sees(viewer, d.store.getSession(key)?.ws ?? null)).map(([, state]) => state);
  // The agents' runtime processes; background jobs' groups are recorded too (to be reaped), but they are jobs.
  const processes = d.store.listProcesses().filter((p) => p.runtime !== "job");
  const memory = await keptMemory(d, processes.map((p) => p.pgid));
  const connects = (Array.isArray(raw.connects) ? raw.connects : []).filter((c: any) => sees(viewer, typeof c?.workspace === "string" && c.workspace !== "" ? c.workspace : null)).map((c: any) => {
    const mode = c.mode ?? "multi-session";
    const runtime = c.bind?.runtime;
    const nonEmpty = (v: unknown) => (typeof v === "string" && v !== "" ? v : null);
    const kind = typeof c.kind === "string" && c.kind !== "" ? c.kind : "slack";
    const shown = {
      id: c.id,
      // What it is known by (its bot's name on its platform, and its workspace there), as its kind says: its id till then.
      name: c.id,
      team: null,
      botImage: null,
      enabled: c.enabled ?? true,
      kind,
      mode,
      requireMention: mode === "multi-session" ? true : (c.requireMention ?? true),
      bind: { runtime, model: nonEmpty(c.bind?.model), effort: nonEmpty(c.bind?.effort), profile: nonEmpty(c.bind?.profile) },
      // Every connect has Slack's tokens for the pages (masked: connects/part.ts; none for another kind's).
      slack: { appToken: "", botToken: "" },
      connection: c.enabled === false ? { state: "disabled" } : { state: "starting" },
      createdBy: c.createdBy?.id ? c.createdBy : null,
      sessions: sessionsOf(c.id),
      session: mode === "single-session" ? d.store.binding(c.id) : null,
    };
    const own = d.connectKinds?.get(kind);
    return own === undefined ? shown : { ...shown, ...own.shown(c), connection: own.connection(c) ?? shown.connection };
  });
  return {
    automaticDecisions: d.accounts ? decisionsView(d, viewer) : null,
    archiving: archivingView(raw, viewer),
    viewer: { via: "mesh", ...viewer },
    mesh: meshStatus(d.cloud, viewer),
    connects,
    profiles: d.accounts?.profilesView(viewer) ?? [],
    footprint: null,
    processes: processes.map((p) => {
      const kb = memory.get(p.pgid);
      return { ...p, rssMb: kb === undefined ? null : Math.round(kb / 1024) };
    }),
    counts: { sessions: sessionsOf(null), running: states.filter((s) => s === "running").length, warm: states.filter((s) => s === "warm").length },
    slackUsers: d.store.slackIdentities(viewer.email),
    disk: diskRoom(d.hub.config().dataDir),
    logins: d.accounts?.loginsView(viewer) ?? [],
    apiProviders: d.accounts?.apiProviders() ?? [],
    machineLogins: d.accounts?.machineLogins() ?? [],
    // An OpenCode Go profile can be signed in to the OpenCode Console (accounts/console.ts) rather than given a key.
    consoleSignIn: d.accounts !== undefined,
    // It shares profiles and skills with its workspaces' other stations (share/index.ts).
    sharing: d.accounts !== undefined,
    updates: d.updates?.get(lang) ?? [],
    // The folders pinned in its drive (drive/drive.ts), each with whether it can be browsed now; a member who may write
    // browses every folder from the home (`anywhere`).
    // Those of a joined workspace browse only its pinned folders, never the whole machine.
    // The variables everything it starts for its agents runs with (ops/agent-env.ts): a proxy, mostly.
    agentEnv: agentEnvView(raw),
    // How a session whose prompt cache is over goes on (routes/context.ts): afresh, by itself, when set.
    context: contextView(raw),
    // Whether it sends its log to still.fail (routes/diagnostics.ts).
    diagnostics: diagnosticsView(raw),
    network: networkView(raw),
    drive: { roots: rootsOf(raw, viewer.home === false ? viewer.workspace : null).map((p) => (d.rootView ?? rootView)(p)), ...(readOnly(viewer) ? {} : { anywhere: true, home: homedir() }) },
    // What its search finds of the machine (docs/search.md): its files through Spotlight (macOS) or walked as asked, and
    // whether the person's own mail, messages and the like too.
    search: { files: platform.hasSpotlight ? "spotlight" : "walk", personal: raw?.search?.personal === true },
    // macOS's grants to still.fail Helper (a Mac's station only; a station from before them says none: not shown).
    ...withPermissions(d, viewer),
    // The modules beside it (docs/station-modules.md), for clients to show theirs: said only where there is one.
    ...withModules(d),
  };
}

function withModules(d: OverviewDeps): { modules?: { id: string; running: boolean }[] } {
  const modules = d.modules?.() ?? [];
  return modules.length === 0 ? {} : { modules };
}

/// How its chats go to the archive on their own (sessions/lifecycle.ts autoArchive): after so many days idle (0: never),
/// Slack's sessions stopped at a block after theirs, and whether only those the archive review recommended. Everyone
/// sees it (why their chats went); its managers change it (PUT /archiving).
function archivingView(raw: any, viewer: Viewer) {
  const days = (v: unknown, fallback: number) => (typeof v === "number" && Number.isFinite(v) ? Math.max(0, v) : fallback);
  return { days: days(raw?.autoArchiveDays, 1), slackDays: days(raw?.slackArchiveDays, 3), reviewed: raw?.autoArchiveReviewed === true, canEdit: managesStation(viewer) };
}

function withPermissions(d: OverviewDeps, viewer: Viewer): { permissions?: unknown } {
  const permissions = d.permissions?.(viewer);
  return permissions === null || permissions === undefined ? {} : { permissions };
}

/// The automatic decisions as the viewer sees them: the checks of their workspace's chats only, and the archive policy of
/// their workspace (docs/multi-workspace.md: one each), which its owners and admins edit (`canEditPolicy`). The rest
/// (the rule, its model) is the station's, its workspaces' managers' alike.
function decisionsView(d: OverviewDeps, viewer: Viewer): unknown {
  // Made again only once a check or the policy is written, the rule or its models change, or DECISIONS_KEPT_MS on (the
  // last days' window moves, a chat is renamed): each making reads the checks of the last days and names their chats.
  const stamp = JSON.stringify([d.store.decisionsVersion(), d.config()?.automaticDecisions ?? null, d.accounts!.decisionModels()]);
  const whose = `${viewer.role}\0${viewer.home}\0${viewer.workspace ?? ""}\0${viewer.email}`;
  let kept = decisionsKept.get(d.store);
  if (kept === undefined) decisionsKept.set(d.store, (kept = new Map()));
  const now = d.store.now();
  const was = kept.get(whose);
  if (was !== undefined && was.stamp === stamp && now - was.at < DECISIONS_KEPT_MS) return structuredClone(was.view);
  const view = madeDecisionsView(d, viewer);
  kept.set(whose, { at: now, stamp, view: structuredClone(view) });
  return view;
}

/// How long the automatic decisions are kept as they were made at most (decisionsView).
const DECISIONS_KEPT_MS = 60_000;
const decisionsKept = new WeakMap<object, Map<string, { at: number; stamp: string; view: unknown }>>();

function madeDecisionsView(d: OverviewDeps, viewer: Viewer): unknown {
  const view = d.accounts!.automaticDecisionsView(viewer);
  const mine = (session: unknown) => typeof session === "string" && sees(viewer, d.store.getSession(session)?.ws ?? null);
  const manages = viewer.role === "owner" || viewer.role === "admin";
  if (Array.isArray(view?.recent)) view.recent = view.recent.filter((row: any) => mine(row?.session));
  if (view?.policy !== undefined || (manages && viewer.home === false)) {
    view.policy = policyView(d.store, viewer.home === false ? viewer.workspace : null, mine, (session) => chatTitleOf(d.store, session));
    view.canEditPolicy = manages;
  }
  return view;
}

/// What a session's chat is called in the chat list; its key only where it has no chat.
function chatTitleOf(store: Store, session: string): string {
  const chat = store.sessionChat(session);
  if (chat) return titleOf(chat.thread, chat.firstText, null);
  return store.getSession(session)?.title ?? session;
}
