// Slack on the station (server.rs's part of it, admin/slack.rs `remember_identities`): its connects as every
// platform's are kept (connects/connects.ts: connected as config.json and the station's workspace say, the names Slack
// gives people and channels in <data>/slack-names.json), and the app API with the configuration tokens in config.json.
import type { Clock } from "effect";
import { maskValue as mask } from "../ops/agent-env.ts";
import type { Connection } from "../connects/connections.ts";
import { type ConnectsOptions, makeConnects } from "../connects/connects.ts";
import { NAMES_FILE } from "../connects/keys.ts";
import type { NameBook } from "../connects/names.ts";
import { log } from "../ops/log.ts";
import { type ConfigToken, SlackApps, type SlackAppLinks, appIdOf, slackAppLinks, upsertToken, withStopEvent } from "./apps.ts";
import { SlackSurface } from "./surface.ts";
import { SlackClient } from "./web.ts";

type Json = any;

/// A connect as config.json has it, as far as its connection goes (config.rs `Connect`, `SlackTokens`).
export type SlackConnect = {
  id: string;
  enabled: boolean;
  appToken: string;
  botToken: string;
  appId: string | null;
  /// Its Slack workspace, as last seen.
  team: { id: string; name: string } | null;
  botName: string | null;
  botImage: string | null;
  /// Who added or was handed the connect: only their configuration token maintains its app.
  owner: string | null;
  /// The still.fail workspace it was added in (docs/multi-workspace.md); null: the station's home one.
  workspace?: string | null;
};

/// What a connect is called: its bot's name in its Slack workspace, else its id.
export const connectName = (c: SlackConnect) => c.botName ?? c.id;

const nonEmpty = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

/// What a Slack connect is known by in the overview (its config.json entry `raw`): its bot's name in its Slack workspace
/// and that workspace, as last seen; its tokens masked.
export function slackShown(raw: Json): Record<string, unknown> {
  const slack = raw?.slack ?? {};
  return {
    name: nonEmpty(slack.botName) ?? raw?.id,
    team: slack.team?.id ? (slack.team.name ?? "") : null,
    botImage: nonEmpty(slack.botImage),
    slack: { appToken: mask(slack.appToken ?? ""), botToken: mask(slack.botToken ?? "") },
  };
}

/// config.json's Slack connects (those of no other kind), as their connections read them.
export function slackConnects(raw: Json): SlackConnect[] {
  return (Array.isArray(raw?.connects) ? raw.connects : []).filter((c: Json) => c?.kind === undefined || c?.kind === null || c?.kind === "slack").map((c: Json): SlackConnect => {
    const slack = c?.slack ?? {};
    const team = slack.team;
    return {
      id: String(c?.id ?? ""),
      enabled: c?.enabled !== false,
      appToken: typeof slack.appToken === "string" ? slack.appToken : "",
      botToken: typeof slack.botToken === "string" ? slack.botToken : "",
      appId: nonEmpty(slack.appId),
      team: team !== null && typeof team === "object" && nonEmpty(team.id) !== null ? { id: team.id, name: typeof team.name === "string" ? team.name : "" } : null,
      botName: nonEmpty(slack.botName),
      botImage: nonEmpty(slack.botImage),
      owner: nonEmpty(c?.createdBy?.id),
      workspace: nonEmpty(c?.workspace),
    };
  });
}

export type SlackOptions = ConnectsOptions & {
  /// Where Slack's Web API is (tests: a stand-in); default $STILLFAIL_SLACK_API, else Slack.
  client?: SlackClient;
  /// Socket Mode's ping and silence limits (tests make them short).
  pingMs?: number;
  staleMs?: number;
  /// The clock the surfaces' pings, retries and status lines run on (tests: a TestClock).
  clock?: Clock.Clock;
  /// How a connect's connection is made (tests); default a SlackSurface.
  create?: (connect: SlackConnect, book: NameBook, client: SlackClient) => Connection;
};

/// What is not yet anyone's of config.json's Slack parts, filtered as config.rs `parse_config` does.
export function configTokens(raw: Json): ConfigToken[] {
  return (Array.isArray(raw?.slackConfigTokens) ? raw.slackConfigTokens : []).filter(
    (t: Json) => t !== null && typeof t === "object" && typeof t.refreshToken === "string" && t.refreshToken !== "" && typeof t.teamId === "string" && t.teamId !== "" && typeof t.by === "string" && t.by !== "",
  );
}

/// A Slack app the station made with someone's configuration token, waiting for its connect (config.rs `SlackAppMade`).
export type SlackAppMade = {
  appId: string;
  name: string;
  teamId: string;
  by: string;
  created: number;
  oauth?: { state: string; clientId: string; clientSecret: string; redirectUri: string; install: string; botToken?: string; installedTeam?: string };
};

export function madeApps(raw: Json): SlackAppMade[] {
  return (Array.isArray(raw?.slackApps) ? raw.slackApps : []).filter(
    (a: Json) => a !== null && typeof a === "object" && typeof a.appId === "string" && a.appId !== "" && typeof a.by === "string" && a.by !== "",
  );
}

export type SlackParts = ReturnType<typeof makeConnections>;

export function makeConnections(options: SlackOptions) {
  const { config } = options;
  const client = options.client ?? new SlackClient();
  let onWorking = (_id: string) => {};
  const create =
    options.create ??
    ((c: SlackConnect, book: NameBook, web: SlackClient) =>
      new SlackSurface({ appToken: c.appToken, botToken: c.botToken, client: web, connect: c.id, book, pingMs: options.pingMs, staleMs: options.staleMs, clock: options.clock, onWorking: () => onWorking(c.id) }));
  const connects = makeConnects<SlackConnect>(options, {
    kind: "slack",
    names: NAMES_FILE.slack,
    connects: slackConnects,
    credentials: (c) => (c.appToken === "" || c.botToken === "" ? null : `${c.appToken}\n${c.botToken}`),
    create: (c, book) => create(c, book, client),
    // Its Slack workspace and its bot's name there, as Slack says now.
    seen: (c, i) => {
      if (i.teamId === "") return null;
      if (c.team !== null && c.team.id === i.teamId && c.team.name === i.team && c.botName === i.botName && c.botImage === i.botImage) return null;
      return (entry) => {
        entry.slack = entry.slack !== null && typeof entry.slack === "object" ? entry.slack : {};
        entry.slack.team = { id: i.teamId, name: i.team };
        entry.slack.botName = i.botName;
        if (i.botImage !== null) entry.slack.botImage = i.botImage;
        else delete entry.slack.botImage;
      };
    },
  });

  // The configuration tokens are config.json's; a rotated one is kept there.
  const apps = new SlackApps({
    client,
    load: () => configTokens(config.raw()),
    save: (token) => {
      try {
        config.update((raw) => {
          raw.slackConfigTokens = upsertToken(Array.isArray(raw.slackConfigTokens) ? raw.slackConfigTokens : [], token);
        });
      } catch (error) {
        log.warn("slack", "slack configuration token not saved", { error: (error as Error).message });
      }
    },
  });

  // Upgrade connected apps as well as new ones. A configuration token lets the station maintain that app; Slack still
  // decides whether its owner may edit it. Try once per configuration, and again when a token or connection changes.
  const attempted = new Map<string, string>();
  const completed = new Map<string, string>();
  const upgrading = new Map<string, Promise<void>>();
  const retryAtEnd = new Set<string>();
  let closed = false;
  const upgradeStops = () => {
    if (closed) return;
    if (!options.bound()) {
      attempted.clear();
      return;
    }
    const tokens = configTokens(config.raw());
    for (const c of connects.connects()) {
      if (!c.enabled || !(options.inWorkspace?.(c.workspace ?? null) ?? true) || connects.state(c.id)?.state !== "connected") {
        attempted.delete(c.id);
        continue;
      }
      const connection = connects.chat(c.id);
      const team = connection?.workspace() ?? c.team?.id ?? null;
      const own = tokens.filter((t) => c.owner !== null && t.by === c.owner);
      if (own.length === 0) continue;
      const versionOf = (all: ConfigToken[]) => JSON.stringify([c.appId, team, connection?.botUserId(), c.owner, all.filter((t) => t.by === c.owner).map((t) => [t.teamId, t.expiresAt])]);
      const version = versionOf(tokens);
      if (upgrading.has(c.id) || completed.get(c.id) === version || attempted.get(c.id) === version) continue;
      attempted.set(c.id, version);
      const work = (async () => {
        const app = c.appId ?? await appIdOf(client, c.botToken);
        if (!app) throw new Error("the Slack app id is unavailable");
        let applicable = false;
        await apps.editManifest(c.owner!, app, (manifest) => {
          const current = connects.connects().find((entry) => entry.id === c.id);
          if (closed || !options.bound() || !(options.inWorkspace?.(c.workspace ?? null) ?? true) ||
              !current?.enabled || current.owner !== c.owner || current.appId !== c.appId || current.botToken !== c.botToken ||
              connects.state(c.id)?.state !== "connected") return null;
          if (!manifest || typeof manifest !== "object") throw new Error("Slack returned no app manifest");
          applicable = true;
          return withStopEvent(manifest);
        });
        if (applicable) completed.set(c.id, versionOf(configTokens(config.raw())));
      })().catch((error) => log.warn("slack", "could not enable the native stop button", { connect: c.id, error: (error as Error)?.message ?? String(error) }))
        .finally(() => {
          upgrading.delete(c.id);
          if (retryAtEnd.delete(c.id) && completed.get(c.id) !== attempted.get(c.id)) attempted.delete(c.id);
          upgradeStops();
        });
      upgrading.set(c.id, work);
    }
  };
  onWorking = (id) => {
    if (upgrading.has(id)) retryAtEnd.add(id);
    else attempted.delete(id);
    upgradeStops();
  };
  const offChanges = connects.onChange(upgradeStops);
  const offConfig = config.listen(upgradeStops);

  return {
    ...connects,
    reconcile: async () => {
      await connects.reconcile();
      upgradeStops();
    },
    close: async () => {
      closed = true;
      offChanges();
      offConfig();
      const [result] = await Promise.allSettled([connects.close(), ...upgrading.values()]);
      if (result?.status === "rejected") throw result.reason;
    },
    apps,
    client,
    /// What the overview says of Slack for a viewer (views.rs): the apps they made that wait for a connect, and the
    /// Slack workspaces they can make apps in (never a token).
    overview: (viewer: string) => slackOverview(config.raw(), viewer),
  };
}

/// The overview's Slack parts for a viewer (admin/views.rs `overview`'s slackApps, `slack_teams`).
export function slackOverview(raw: Json, by: string): { slackApps: Json[]; slackTeams: Json[] } {
  const tokens = configTokens(raw);
  const slackApps = madeApps(raw)
    .filter((a) => a.by === by)
    .map((a) => {
      const links: SlackAppLinks = slackAppLinks(a.appId, a.teamId);
      return {
        appId: a.appId,
        name: a.name,
        teamId: a.teamId,
        team: tokens.find((t) => t.teamId === a.teamId)?.owner?.team ?? null,
        created: a.created,
        links,
        install: a.oauth?.install ?? null,
        state: a.oauth?.state ?? null,
        installed: typeof a.oauth?.botToken === "string",
        installedTeam: a.oauth?.installedTeam ?? null,
      };
    });
  const slackTeams = tokens
    .filter((t) => t.by === by)
    .map((t) => ({ teamId: t.teamId, name: t.owner?.team ? t.owner.team : t.teamId, owner: t.owner ?? null }));
  return { slackApps, slackTeams };
}

export { Connections, shownIdentity } from "../connects/connections.ts";
export type { ConnectState, Connection, SocketStatus } from "../connects/connections.ts";
export { SlackSurface, toEvent, identityOf, verifySlackTokens } from "./surface.ts";
export type { SlackIdentity } from "./surface.ts";
export { NameBook } from "../connects/names.ts";
export { ThreadStatus } from "./status.ts";
export { SlackClient, SlackApiError, apiBase } from "./web.ts";
export * from "./apps.ts";
