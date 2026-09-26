// Managing a connect's Slack app from ember: its name, description, colour,
// icon and permissions live in the app's manifest, which Slack lets a
// workspace member change with an app configuration token. The token lasts 12
// hours; its refresh token (single use) yields the next pair, so ember keeps
// both and rotates as needed. Permission changes still need a person to
// approve them in Slack; ember hands them the link.
import { log } from "../log.ts";

/** Permissions in plain words. Each group adds its scopes and events to the app; "base" is always on. */
export const SLACK_GROUPS = {
  base: {
    label: "读取和回复消息",
    description: "被 @ 时收到消息，读取所在频道、私信和群聊的消息并回复。",
    scopes: ["app_mentions:read", "chat:write", "channels:history", "groups:history", "im:history", "mpim:history",
      "channels:read", "groups:read", "im:read", "mpim:read", "users:read"],
    events: ["app_mention", "message.channels", "message.groups", "message.im", "message.mpim"],
  },
  public: {
    label: "在没加入的公开频道发言",
    description: "不用先邀请，也能在公开频道回复。",
    scopes: ["chat:write.public", "channels:join"],
    events: [],
  },
  dm: {
    label: "主动发私信",
    description: "给人或多人开启私信对话。",
    scopes: ["im:write", "mpim:write"],
    events: [],
  },
  customize: {
    label: "用别的名字和头像发消息",
    description: "每条消息可以换显示名和头像。",
    scopes: ["chat:write.customize"],
    events: [],
  },
  files: {
    label: "读写文件",
    description: "读取消息里的附件，上传截图、日志等文件。",
    scopes: ["files:read", "files:write", "remote_files:read", "remote_files:write", "remote_files:share"],
    events: ["file_shared"],
  },
  reactions: {
    label: "表情回应、置顶和书签",
    description: "用表情标记进度，置顶消息，管理频道书签。",
    scopes: ["reactions:read", "reactions:write", "pins:read", "pins:write", "bookmarks:read", "bookmarks:write"],
    events: ["reaction_added", "reaction_removed"],
  },
  channels: {
    label: "创建和管理频道",
    description: "建频道、邀请成员，知道有人加入或新建频道。",
    scopes: ["channels:manage", "groups:write"],
    events: ["member_joined_channel", "channel_created"],
  },
  people: {
    label: "查看成员资料",
    description: "读取邮箱、个人资料、用户组、工作区信息和自定义表情。",
    scopes: ["users:read.email", "users.profile:read", "usergroups:read", "team:read", "emoji:read"],
    events: [],
  },
  extras: {
    label: "链接预览、提醒和状态",
    description: "展开链接、设置提醒、读取勿扰和通话状态。",
    scopes: ["links:read", "links:write", "reminders:read", "reminders:write", "dnd:read", "calls:read"],
    events: [],
  },
} as const satisfies Record<string, { label: string; description: string; scopes: readonly string[]; events: readonly string[] }>;

export type SlackGroup = keyof typeof SLACK_GROUPS;
export const SLACK_GROUP_IDS = Object.keys(SLACK_GROUPS) as SlackGroup[];

/** The app as the settings form shows it. */
export interface SlackAppSettings {
  name: string;
  displayName: string;
  description: string;
  longDescription: string;
  backgroundColor: string;
  groups: Record<SlackGroup, boolean>;
}

type Manifest = Record<string, any>;

/** Reads the form's view of a manifest. A group counts as on when all its scopes are there. */
export function settingsOf(manifest: Manifest): SlackAppSettings {
  const scopes = new Set<string>(manifest.oauth_config?.scopes?.bot ?? []);
  const groups = Object.fromEntries(SLACK_GROUP_IDS.map((g) => [g, SLACK_GROUPS[g].scopes.every((s) => scopes.has(s))])) as Record<SlackGroup, boolean>;
  return {
    name: String(manifest.display_information?.name ?? ""),
    displayName: String(manifest.features?.bot_user?.display_name ?? ""),
    description: String(manifest.display_information?.description ?? ""),
    longDescription: String(manifest.display_information?.long_description ?? ""),
    backgroundColor: String(manifest.display_information?.background_color ?? ""),
    groups,
  };
}

/**
 * Applies form edits to a manifest. Turning a group off removes only what no
 * group that stays on needs; scopes ember does not know about are kept.
 */
export function applySettings(manifest: Manifest, edit: Partial<SlackAppSettings>): Manifest {
  const next: Manifest = structuredClone(manifest);
  next.display_information ??= {};
  next.features ??= {};
  next.features.bot_user ??= { display_name: edit.displayName ?? edit.name ?? "ember", always_online: true };
  if (edit.name !== undefined) next.display_information.name = edit.name.trim();
  if (edit.displayName !== undefined) next.features.bot_user.display_name = edit.displayName.trim();
  if (edit.description !== undefined) setOrDelete(next.display_information, "description", edit.description.trim());
  if (edit.longDescription !== undefined) setOrDelete(next.display_information, "long_description", edit.longDescription.trim());
  if (edit.backgroundColor !== undefined) setOrDelete(next.display_information, "background_color", edit.backgroundColor.trim());
  if (edit.groups) {
    const on = SLACK_GROUP_IDS.filter((g) => g === "base" || (edit.groups![g] ?? settingsOf(manifest).groups[g]));
    const keepScopes = new Set<string>(on.flatMap((g) => SLACK_GROUPS[g].scopes));
    const keepEvents = new Set<string>(on.flatMap((g) => SLACK_GROUPS[g].events));
    const known = new Set<string>(SLACK_GROUP_IDS.flatMap((g) => SLACK_GROUPS[g].scopes));
    const knownEvents = new Set<string>(SLACK_GROUP_IDS.flatMap((g) => SLACK_GROUPS[g].events));
    const scopes: string[] = next.oauth_config?.scopes?.bot ?? [];
    const events: string[] = next.settings?.event_subscriptions?.bot_events ?? [];
    next.oauth_config ??= {};
    next.oauth_config.scopes ??= {};
    next.oauth_config.scopes.bot = unique([...scopes.filter((s) => !known.has(s) || keepScopes.has(s)), ...keepScopes]);
    next.settings ??= {};
    next.settings.event_subscriptions ??= {};
    next.settings.event_subscriptions.bot_events = unique([...events.filter((e) => !knownEvents.has(e) || keepEvents.has(e)), ...keepEvents]);
  }
  return next;
}

function setOrDelete(target: Record<string, unknown>, key: string, value: string): void {
  if (value) target[key] = value;
  else delete target[key];
}

function unique<T>(values: T[]): T[] {
  return [...new Set(values)];
}

export interface ConfigToken {
  accessToken: string;
  refreshToken: string;
  /** Epoch ms when the access token stops working. */
  expiresAt: number;
  /** The Slack workspace it makes apps in, and its name there. */
  teamId: string;
  team?: string;
}

export class SlackApiError extends Error {
  readonly code: string;
  readonly details: unknown;
  constructor(method: string, code: string, details?: unknown) {
    super(`${method}: ${code}${details ? ` ${JSON.stringify(details)}` : ""}`);
    this.code = code;
    this.details = details;
  }
}

async function call(method: string, token: string | null, params: Record<string, string> | FormData): Promise<Record<string, any>> {
  const body = params instanceof FormData ? params : new URLSearchParams(params);
  const response = await fetch(`https://slack.com/api/${method}`, {
    method: "POST",
    headers: token ? { authorization: `Bearer ${token}` } : {},
    body,
  });
  const data = await response.json() as Record<string, any>;
  if (!data.ok) throw new SlackApiError(method, String(data.error ?? `HTTP ${response.status}`), data.errors ?? undefined);
  return data;
}

/** An installation's code (from Slack's redirect) exchanged for its bot token, with the workspace it went into. */
export async function exchangeInstallCode(input: { clientId: string; clientSecret: string; code: string; redirectUri: string }): Promise<{ botToken: string; team: string | null }> {
  const data = await call("oauth.v2.access", null, { client_id: input.clientId, client_secret: input.clientSecret, code: input.code, redirect_uri: input.redirectUri });
  return { botToken: String(data.access_token ?? ""), team: data.team?.name ? String(data.team.name) : null };
}

/** Exchanges a refresh token for a fresh pair. The old refresh token stops working. */
export async function rotateConfigToken(refreshToken: string): Promise<ConfigToken> {
  const data = await call("tooling.tokens.rotate", null, { refresh_token: refreshToken.trim() });
  return {
    accessToken: String(data.token),
    refreshToken: String(data.refresh_token),
    expiresAt: Number(data.exp) * 1000,
    teamId: String(data.team_id ?? ""),
  };
}

/** Which app a bot token belongs to. */
export async function appIdOf(botToken: string): Promise<string> {
  const auth = await call("auth.test", botToken, {});
  const bot = await call("bots.info", botToken, { bot: String(auth.bot_id) });
  return String(bot.bot?.app_id ?? "");
}

/** Pages in Slack's app settings a person may need, by app id. */
export function slackAppLinks(appId: string) {
  const base = `https://api.slack.com/apps/${appId}`;
  return { settings: base, install: `${base}/install-on-team`, appToken: `${base}/general`, oauth: `${base}/oauth` };
}

/** The Slack workspace a configuration token is for, by name (auth.test with its access token). */
export async function teamOfConfigToken(accessToken: string): Promise<string | null> {
  const data = await call("auth.test", accessToken, {}).catch(() => null);
  return data?.team ? String(data.team) : null;
}

/**
 * The Slack app API with the configuration tokens, one per Slack workspace. `load` and `save` keep them in ember's
 * config, so a rotation survives restarts. An app is made with the token of the workspace chosen; an app already made
 * is read and changed with whichever token owns it (found once, by asking).
 */
export class SlackApps {
  readonly #load: () => ConfigToken[];
  readonly #save: (token: ConfigToken) => void;
  readonly #rotating = new Map<string, Promise<string>>();
  /** Which workspace's token owns an app, once known. */
  readonly #owner = new Map<string, string>();

  constructor(load: () => ConfigToken[], save: (token: ConfigToken) => void) {
    this.#load = load;
    this.#save = save;
  }

  get configured(): boolean {
    return this.#load().length > 0;
  }

  async exportManifest(appId: string): Promise<Manifest> {
    return (await this.#forApp(appId, "apps.manifest.export", { app_id: appId })).manifest as Manifest;
  }

  /** Validates, then updates. Returns whether Slack wants the permissions approved again. */
  async updateManifest(appId: string, manifest: Manifest): Promise<{ permissionsUpdated: boolean }> {
    const text = JSON.stringify(manifest);
    await this.#forApp(appId, "apps.manifest.validate", { app_id: appId, manifest: text });
    const data = await this.#forApp(appId, "apps.manifest.update", { app_id: appId, manifest: text });
    return { permissionsUpdated: Boolean(data.permissions_updated) };
  }

  /** Makes the app in a workspace (`team`); its OAuth credentials come only now, once. */
  async createApp(team: string, manifest: Manifest): Promise<{ appId: string; clientId: string; clientSecret: string }> {
    const data = await call("apps.manifest.create", await this.#token(team), { manifest: JSON.stringify(manifest) });
    const appId = String(data.app_id);
    this.#owner.set(appId, team);
    return { appId, clientId: String(data.credentials?.client_id ?? ""), clientSecret: String(data.credentials?.client_secret ?? "") };
  }

  async setIcon(appId: string, png: Buffer): Promise<void> {
    const form = new FormData();
    form.set("app_id", appId);
    form.set("file", new Blob([new Uint8Array(png)], { type: "image/png" }), "icon.png");
    await this.#forApp(appId, "apps.icon.set", form);
  }

  /** A call about an app, with the token that owns it: the one known, else each in turn until one is not refused. */
  async #forApp(appId: string, method: string, params: Record<string, string> | FormData): Promise<Record<string, any>> {
    const known = this.#owner.get(appId);
    if (known) return call(method, await this.#token(known), params);
    const tokens = this.#load();
    if (tokens.length === 0) throw new Error("还没有配置 Slack App 配置 token");
    let last: unknown = null;
    for (const token of tokens) {
      try {
        const data = await call(method, await this.#token(token.teamId), params);
        this.#owner.set(appId, token.teamId);
        return data;
      } catch (error) {
        last = error;
      }
    }
    throw last;
  }

  /** A working access token of a workspace, rotating first when the current one is about to expire. */
  #token(team: string): Promise<string> {
    const current = this.#load().find((t) => t.teamId === team);
    if (!current) return Promise.reject(new Error("这个 Slack 工作区没有配置 token"));
    if (current.expiresAt - Date.now() > 5 * 60_000) return Promise.resolve(current.accessToken);
    let rotating = this.#rotating.get(team);
    if (!rotating) {
      rotating = rotateConfigToken(current.refreshToken)
        .then((next) => {
          this.#save({ ...next, ...(current.team ? { team: current.team } : {}) });
          log.info("slack configuration token rotated", { team: next.teamId });
          return next.accessToken;
        })
        .finally(() => { this.#rotating.delete(team); });
      this.#rotating.set(team, rotating);
    }
    return rotating;
  }
}
