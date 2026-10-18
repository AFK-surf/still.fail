// GET /overview (admin/views.rs `overview`): the station as its settings pages show it — still.fail cloud, connects,
// profiles, the agents' processes, counts, the disk, logins, updates — as the viewer sees it. Answered on the main
// thread from what is in memory and the config; told again on /events when it changes (`overview`).
import { statfsSync } from "node:fs";
import { homedir } from "node:os";
import type { Accounts } from "../accounts/index.ts";
import { mask } from "../accounts/index.ts";
import type { Cloud } from "../cloud/state.ts";
import { type Viewer, readOnly } from "../mesh/credential.ts";
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


/// What the Slack side adds (src/slack): a connect's connection, the viewer's Slack workspaces and apps.
export type SlackView = {
  connection(connect: any): unknown;
  teams(viewer: Viewer): unknown[];
  apps(viewer: Viewer): unknown[];
};

export type OverviewDeps = {
  store: Store;
  hub: Hub;
  cloud: Cloud;
  config: () => any;
  accounts?: Accounts;
  updates?: Updates;
  slack?: SlackView;
  /// What macOS lets still.fail Helper do here, as the viewer is told it (routes/permissions.ts); none where there is no
  /// helper (not a Mac), or before the first look.
  permissions?: (viewer: Viewer) => unknown;
  /// A pinned root as the drive shows it (drive.ts `rootViewThrough`: one in a folder macOS protects by what still.fail
  /// Helper's grant is known to be, never listed by the station); default `rootView`.
  rootView?: (path: string) => RootView;
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
  const sessions = d.store.listSessions().filter((s) => sees(viewer, s.ws));
  // The agents' runtime processes; background jobs' groups are recorded too (to be reaped), but they are jobs.
  const processes = d.store.listProcesses().filter((p) => p.runtime !== "job");
  const memory = await processMemory(processes.map((p) => p.pgid));
  const connects = (Array.isArray(raw.connects) ? raw.connects : []).filter((c: any) => sees(viewer, typeof c?.workspace === "string" && c.workspace !== "" ? c.workspace : null)).map((c: any) => {
    const mode = c.mode ?? "multi-session";
    const slack = c.slack ?? {};
    const runtime = c.bind?.runtime;
    const nonEmpty = (v: unknown) => (typeof v === "string" && v !== "" ? v : null);
    return {
      // What it is known by: its bot's name in its Slack workspace, and that workspace.
      id: c.id,
      name: nonEmpty(slack.botName) ?? c.id,
      team: slack.team?.id ? (slack.team.name ?? "") : null,
      botImage: nonEmpty(slack.botImage),
      enabled: c.enabled ?? true,
      kind: c.kind ?? "slack",
      mode,
      requireMention: mode === "multi-session" ? true : (c.requireMention ?? true),
      bind: { runtime, model: nonEmpty(c.bind?.model), effort: nonEmpty(c.bind?.effort), profile: nonEmpty(c.bind?.profile) },
      slack: { appToken: mask(slack.appToken ?? ""), botToken: mask(slack.botToken ?? "") },
      connection: d.slack?.connection(c) ?? (c.enabled === false ? { state: "disabled" } : !slack.appToken || !slack.botToken ? { state: "no_tokens" } : { state: "starting" }),
      createdBy: c.createdBy?.id ? c.createdBy : null,
      sessions: sessions.filter((s) => s.connect === c.id).length,
      session: mode === "single-session" ? d.store.binding(c.id) : null,
    };
  });
  const states = sessions.map((s) => d.hub.processState(s.key));
  return {
    automaticDecisions: d.accounts ? decisionsView(d, viewer) : null,
    viewer: { via: "mesh", ...viewer },
    mesh: meshStatus(d.cloud, viewer),
    connects,
    profiles: d.accounts?.profilesView(viewer) ?? [],
    footprint: null,
    processes: processes.map((p) => {
      const kb = memory.get(p.pgid);
      return { ...p, rssMb: kb === undefined ? null : Math.round(kb / 1024) };
    }),
    counts: { sessions: sessions.length, running: states.filter((s) => s === "running").length, warm: states.filter((s) => s === "warm").length },
    slackUsers: d.store.slackIdentities(viewer.email),
    // The Slack workspaces the station can make and edit apps in itself (an app configuration token each).
    slackTeams: d.slack?.teams(viewer) ?? [],
    disk: diskRoom(d.hub.config().dataDir),
    logins: d.accounts?.loginsView(viewer) ?? [],
    apiProviders: d.accounts?.apiProviders() ?? [],
    machineLogins: d.accounts?.machineLogins() ?? [],
    // An OpenCode Go profile can be signed in to the OpenCode Console (accounts/console.ts) rather than given a key.
    consoleSignIn: d.accounts !== undefined,
    // It shares profiles and skills with its workspace's other stations (share/index.ts).
    sharing: d.accounts !== undefined,
    updates: d.updates?.get(lang) ?? [],
    slackApps: d.slack?.apps(viewer) ?? [],
    // The folders pinned in its drive (drive/drive.ts), each with whether it can be browsed now; a member who may write
    // browses every folder from the home (`anywhere`).
    // Those of a joined workspace browse only its pinned folders, never the whole machine.
    // The variables everything it starts for its agents runs with (ops/agent-env.ts): a proxy, mostly.
    agentEnv: agentEnvView(raw),
    drive: { roots: rootsOf(raw, viewer.home === false ? viewer.workspace : null).map((p) => (d.rootView ?? rootView)(p)), ...(readOnly(viewer) ? {} : { anywhere: true, home: homedir() }) },
    // What its search finds of the machine (docs/search.md): its files through Spotlight (macOS) or walked as asked, and
    // whether the person's own mail, messages and the like too.
    search: { files: platform.hasSpotlight ? "spotlight" : "walk", personal: raw?.search?.personal === true },
    // macOS's grants to still.fail Helper (a Mac's station only; a station from before them says none: not shown).
    ...withPermissions(d, viewer),
  };
}

function withPermissions(d: OverviewDeps, viewer: Viewer): { permissions?: unknown } {
  const permissions = d.permissions?.(viewer);
  return permissions === null || permissions === undefined ? {} : { permissions };
}

/// The automatic decisions as the viewer sees them: the checks of their workspace's chats only, and the archive policy of
/// their workspace (docs/multi-workspace.md: one each), which its owners and admins edit (`canEditPolicy`). The rest
/// (the rule, its model) is the station's, its workspaces' managers' alike.
function decisionsView(d: OverviewDeps, viewer: Viewer): unknown {
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
  const summary = store.listThreads("", session, null)[0];
  if (summary) return titleOf(summary.thread, summary.firstText, null);
  return store.getSession(session)?.title ?? session;
}
