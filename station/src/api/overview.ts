// GET /overview (admin/views.rs `overview`): the station as its settings pages show it — still.fail cloud, connects,
// profiles, the agents' processes, counts, the disk, logins, updates — as the viewer sees it. Answered on the main
// thread from what is in memory and the config; told again on /events when it changes (`overview`).
import { execFile } from "node:child_process";
import { statfsSync } from "node:fs";
import { promisify } from "node:util";
import type { Accounts } from "../accounts/index.ts";
import { mask } from "../accounts/index.ts";
import type { Cloud } from "../cloud/state.ts";
import type { Viewer } from "../mesh/credential.ts";
import type { Lang } from "../ops/i18n.ts";
import type { Hub } from "../sessions/hub.ts";
import type { Store } from "../store/store.ts";
import type { Updates } from "../updates/updates.ts";

const run = promisify(execFile);

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
};

/// This station's link to still.fail cloud, as the pages show it (server.rs MeshFile::status).
export function meshStatus(cloud: Cloud): Record<string, unknown> {
  const s = cloud.state;
  if (s === null) return { state: "off", origin: null, station: null, workspace: null, workspaceId: null, name: null };
  const v: Record<string, unknown> = {
    state: s.removed_at !== undefined ? "removed" : "running",
    origin: s.origin ?? null,
    station: s.station ?? null,
    workspace: s.workspace_name ?? null,
    workspaceId: s.workspace ?? null,
    name: s.name ?? null,
  };
  if (s.removed_at !== undefined) v.removedAt = s.removed_at;
  return v;
}

/// Memory of each recorded runtime process group, from ps (kB).
async function processMemory(pgids: number[]): Promise<Map<number, number>> {
  const rss = new Map<number, number>();
  if (pgids.length === 0) return rss;
  if (process.platform === "win32") return windowsMemory(pgids);
  try {
    const { stdout } = await run("ps", ["-axo", "pgid=,rss="]);
    for (const line of stdout.split("\n")) {
      const [pgid, kb] = line.trim().split(/\s+/).map(Number);
      if (pgid !== undefined && kb !== undefined && pgids.includes(pgid)) rss.set(pgid, (rss.get(pgid) ?? 0) + kb);
    }
  } catch {}
  return rss;
}

/// On Windows a group is its leader's process tree (a runner's job holds no other): each leader's working set and its
/// descendants', from Win32_Process (kB).
async function windowsMemory(pgids: number[]): Promise<Map<number, number>> {
  const rss = new Map<number, number>();
  try {
    const script = "Get-CimInstance Win32_Process | ForEach-Object { \"$($_.ProcessId) $($_.ParentProcessId) $($_.WorkingSetSize)\" }";
    const { stdout } = await run("powershell", ["-NoProfile", "-NonInteractive", "-Command", script], { windowsHide: true, maxBuffer: 16 << 20 });
    const children = new Map<number, number[]>();
    const bytes = new Map<number, number>();
    for (const line of stdout.split(/\r?\n/)) {
      const [pid, parent, size] = line.trim().split(/\s+/).map(Number);
      if (!Number.isInteger(pid) || !Number.isInteger(parent) || !Number.isFinite(size)) continue;
      bytes.set(pid!, size!);
      if (pid !== parent) children.set(parent!, [...(children.get(parent!) ?? []), pid!]);
    }
    for (const pgid of pgids) {
      if (!bytes.has(pgid)) continue;
      let total = 0;
      const seen = new Set<number>();
      for (const queue = [pgid]; queue.length > 0; ) {
        const pid = queue.pop()!;
        if (seen.has(pid)) continue;
        seen.add(pid);
        total += bytes.get(pid) ?? 0;
        queue.push(...(children.get(pid) ?? []));
      }
      rss.set(pgid, Math.round(total / 1024));
    }
  } catch {}
  return rss;
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
  const sessions = d.store.listSessions();
  // The agents' runtime processes; background jobs' groups are recorded too (to be reaped), but they are jobs.
  const processes = d.store.listProcesses().filter((p) => p.runtime !== "job");
  const memory = await processMemory(processes.map((p) => p.pgid));
  const connects = (Array.isArray(raw.connects) ? raw.connects : []).map((c: any) => {
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
    automaticDecisions: d.accounts?.automaticDecisionsView(viewer) ?? null,
    viewer: { via: "mesh", ...viewer },
    mesh: meshStatus(d.cloud),
    connects,
    profiles: d.accounts?.profilesView() ?? [],
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
    logins: d.accounts?.loginsView() ?? [],
    apiProviders: d.accounts?.apiProviders() ?? [],
    machineLogins: d.accounts?.machineLogins() ?? [],
    // It shares profiles and skills with its workspace's other stations (share/index.ts).
    sharing: d.accounts !== undefined,
    updates: d.updates?.get(lang) ?? [],
    slackApps: d.slack?.apps(viewer) ?? [],
  };
}
