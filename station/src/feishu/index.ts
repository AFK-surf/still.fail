// Feishu on the station (docs/feishu.md): the Feishu connects' connections as config.json and the station's workspace
// say (as src/slack/index.ts keeps Slack's), what Feishu calls people and chats (<data>/feishu-names.json), where its
// chats' words go (<data>/feishu-threads.json), and the apps being made by a scan.
import { join } from "node:path";
import type { Clock } from "effect";
import type { ConfigFile } from "../ops/config.ts";
import { log } from "../ops/log.ts";
import type { ChatEvent, ChatSurface } from "../sessions/chat.ts";
import type { Store } from "../store/store.ts";
import { type ConnectState, type Connection, Connections } from "../slack/connections.ts";
import { NameBook } from "../slack/names.ts";
import { shownIdentity } from "../slack/surface.ts";
import { Registrations } from "./register.ts";
import { FeishuSurface } from "./surface.ts";
import { FeishuThreads } from "./threads.ts";
import { type Domain, domainOf } from "./web.ts";

type Json = any;

/// A Feishu connect as config.json has it, as far as its connection goes.
export type FeishuConnect = {
  id: string;
  enabled: boolean;
  appId: string;
  appSecret: string;
  domain: Domain;
  botName: string | null;
  botImage: string | null;
  botOpenId: string | null;
  tenant: { key: string; name: string } | null;
  workspace?: string | null;
};

const nonEmpty = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

export function feishuConnects(raw: Json): FeishuConnect[] {
  return (Array.isArray(raw?.connects) ? raw.connects : [])
    .filter((c: Json) => c?.kind === "feishu")
    .map((c: Json): FeishuConnect => {
      const f = c?.feishu ?? {};
      const tenant = f.tenant;
      return {
        id: String(c?.id ?? ""),
        enabled: c?.enabled !== false,
        appId: typeof f.appId === "string" ? f.appId : "",
        appSecret: typeof f.appSecret === "string" ? f.appSecret : "",
        domain: domainOf(f.domain),
        botName: nonEmpty(f.botName),
        botImage: nonEmpty(f.botImage),
        botOpenId: nonEmpty(f.botOpenId),
        tenant: tenant !== null && typeof tenant === "object" && nonEmpty(tenant.key) !== null ? { key: tenant.key, name: typeof tenant.name === "string" ? tenant.name : "" } : null,
        workspace: nonEmpty(c?.workspace),
      };
    });
}

/// An app's secret as the pages are shown it.
export const maskSecret = (s: string) => (s.length <= 4 ? (s === "" ? "" : "••••") : `••••${s.slice(-4)}`);

export type FeishuOptions = {
  data: string;
  store: Store;
  config: ConfigFile;
  receive: (connect: string, event: ChatEvent) => Promise<void>;
  bound: () => boolean;
  inWorkspace?: (workspace: string | null) => boolean;
  clock?: Clock.Clock;
  /// How a connect's connection is made (tests); default a FeishuSurface.
  create?: (connect: FeishuConnect, book: NameBook, threads: FeishuThreads) => Connection;
};

export type FeishuParts = ReturnType<typeof makeFeishu>;

export function makeFeishu(options: FeishuOptions) {
  const { config, store } = options;
  const names = new NameBook(join(options.data, "feishu-names.json"), { saveAfterMs: 200, learnAfterMs: 400 });
  names.onLearn(() => {
    for (const session of store.listSessions()) store.notify(session.key);
  });
  const threads = new FeishuThreads(join(options.data, "feishu-threads.json"));
  const registrations = new Registrations({ clock: options.clock });
  const create =
    options.create ??
    ((c: FeishuConnect, book: NameBook, t: FeishuThreads) => new FeishuSurface({ connect: c.id, appId: c.appId, appSecret: c.appSecret, domain: c.domain, threads: t, book, clock: options.clock }));
  const connections = new Connections<FeishuConnect>(
    (c) => create(c, names, threads),
    options.receive,
    (c) => (c.appId === "" || c.appSecret === "" ? null : `${c.domain}\n${c.appId}\n${c.appSecret}`),
  );
  const connects = () => feishuConnects(config.raw());
  const connect = (id: string) => connects().find((c) => c.id === id);

  let closed = false;
  const reconcile = async () => {
    if (closed) return;
    if (options.bound()) await connections.reconcile(connects().filter((c) => options.inWorkspace?.(c.workspace ?? null) ?? true));
    else await connections.stopAll();
  };

  /// Keeps what each connected connect is known by (its bot's name and picture, its company): it shows by them while it
  /// is not connected too.
  const rememberIdentities = () => {
    const changed: [string, Json][] = [];
    for (const c of connects()) {
      const identity = connections.chat(c.id)?.identity();
      if (!identity || identity.botUserId === "") continue;
      const tenant = identity.teamId !== "" ? { key: identity.teamId, name: identity.team } : c.tenant;
      const same = c.botName === identity.botName && c.botImage === identity.botImage && c.botOpenId === identity.botUserId && JSON.stringify(c.tenant) === JSON.stringify(tenant);
      if (!same) changed.push([c.id, { botName: identity.botName, botImage: identity.botImage, botOpenId: identity.botUserId, tenant }]);
    }
    if (changed.length === 0) return;
    try {
      config.update((raw) => {
        for (const c of Array.isArray(raw.connects) ? raw.connects : []) {
          const found = changed.find(([id]) => id === c.id);
          if (!found || c.kind !== "feishu") continue;
          const seen = found[1];
          c.feishu = c.feishu !== null && typeof c.feishu === "object" ? c.feishu : {};
          c.feishu.botName = seen.botName;
          c.feishu.botOpenId = seen.botOpenId;
          if (seen.botImage !== null) c.feishu.botImage = seen.botImage;
          else delete c.feishu.botImage;
          if (seen.tenant !== null) c.feishu.tenant = seen.tenant;
        }
      });
    } catch (error) {
      log.warn("feishu", "feishu identities not kept", { error: (error as Error).message });
    }
  };
  let remembering = false;
  const listeners = new Set<() => void>();
  const tell = () => {
    for (const listener of listeners) {
      try {
        listener();
      } catch {}
    }
  };
  connections.onChange(() => {
    tell();
    if (remembering || closed) return;
    remembering = true;
    setImmediate(() => {
      remembering = false;
      if (!closed) rememberIdentities();
    });
  });
  registrations.onChange(tell);

  const unlisten = config.listen(() => {
    void reconcile().catch((error) => log.warn("feishu", "feishu connects not brought in line with the config", { error: (error as Error).message }));
  });

  return {
    connections,
    names,
    threads,
    registrations,
    chats: (id: string): ChatSurface | undefined => connections.chat(id),
    chat: (id: string): Connection | undefined => connections.chat(id),
    connects,
    reconcile,
    stopAll: () => connections.stopAll(),
    state: (c: string | FeishuConnect): ConnectState | null => {
      const found = typeof c === "string" ? connect(c) : c;
      return found ? connections.state(found) : null;
    },
    onChange: (listener: () => void) => {
      listeners.add(listener);
      return () => listeners.delete(listener);
    },
    /// What the overview says of a Feishu connect besides what all connects say.
    shown: (raw: Json): Record<string, unknown> => {
      const f = raw?.feishu ?? {};
      const live = connections.chat(String(raw?.id ?? ""))?.identity();
      return {
        name: nonEmpty(f.botName) ?? live?.botName ?? raw?.id,
        team: nonEmpty(f.tenant?.name) ?? (live && live.team !== "" ? live.team : null),
        botImage: nonEmpty(f.botImage),
        slack: { appToken: "", botToken: "" },
        feishu: { appId: typeof f.appId === "string" ? f.appId : "", appSecret: maskSecret(typeof f.appSecret === "string" ? f.appSecret : ""), domain: domainOf(f.domain) },
      };
    },
    close: async () => {
      closed = true;
      unlisten();
      listeners.clear();
      await connections.stopAll();
      await registrations.close();
      await names.close();
    },
  };
}
