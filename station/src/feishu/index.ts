// Feishu on the station (docs/feishu.md): its connects as every platform's are kept (connects/connects.ts: connected as
// config.json and the station's workspace say, what Feishu calls people and chats in <data>/feishu-names.json), where
// its chats' words go (<data>/feishu-threads.json), and the apps being made by a scan.
import { join } from "node:path";
import type { Clock } from "effect";
import type { Connection } from "../connects/connections.ts";
import { type ConnectsOptions, makeConnects } from "../connects/connects.ts";
import { NAMES_FILE } from "../connects/keys.ts";
import type { NameBook } from "../connects/names.ts";
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

export type FeishuOptions = ConnectsOptions & {
  clock?: Clock.Clock;
  /// How a connect's connection is made (tests); default a FeishuSurface.
  create?: (connect: FeishuConnect, book: NameBook, threads: FeishuThreads) => Connection;
};

export type FeishuParts = ReturnType<typeof makeFeishu>;

export function makeFeishu(options: FeishuOptions) {
  const threads = new FeishuThreads(join(options.data, "feishu-threads.json"));
  const registrations = new Registrations({ clock: options.clock });
  const create =
    options.create ??
    ((c: FeishuConnect, book: NameBook, t: FeishuThreads) => new FeishuSurface({ connect: c.id, appId: c.appId, appSecret: c.appSecret, domain: c.domain, threads: t, book, clock: options.clock }));
  const connects = makeConnects<FeishuConnect>(options, {
    kind: "feishu",
    names: NAMES_FILE.feishu,
    connects: feishuConnects,
    credentials: (c) => (c.appId === "" || c.appSecret === "" ? null : `${c.domain}\n${c.appId}\n${c.appSecret}`),
    create: (c, book) => create(c, book, threads),
    // Its bot's name and picture, its company.
    seen: (c, i) => {
      const tenant = i.teamId !== "" ? { key: i.teamId, name: i.team } : c.tenant;
      if (c.botName === i.botName && c.botImage === i.botImage && c.botOpenId === i.botUserId && JSON.stringify(c.tenant) === JSON.stringify(tenant)) return null;
      return (entry) => {
        entry.feishu = entry.feishu !== null && typeof entry.feishu === "object" ? entry.feishu : {};
        entry.feishu.botName = i.botName;
        entry.feishu.botOpenId = i.botUserId;
        if (i.botImage !== null) entry.feishu.botImage = i.botImage;
        else delete entry.feishu.botImage;
        if (tenant !== null) entry.feishu.tenant = tenant;
      };
    },
  });
  registrations.onChange(connects.tell);

  return {
    ...connects,
    threads,
    registrations,
    /// What the overview says of a Feishu connect besides what all connects say.
    shown: (raw: Json): Record<string, unknown> => {
      const f = raw?.feishu ?? {};
      const live = connects.chat(String(raw?.id ?? ""))?.identity();
      return {
        name: nonEmpty(f.botName) ?? live?.botName ?? raw?.id,
        team: nonEmpty(f.tenant?.name) ?? (live && live.team !== "" ? live.team : null),
        botImage: nonEmpty(f.botImage),
        feishu: { appId: typeof f.appId === "string" ? f.appId : "", appSecret: maskSecret(typeof f.appSecret === "string" ? f.appSecret : ""), domain: domainOf(f.domain) },
      };
    },
    close: async () => {
      await connects.close();
      await registrations.close();
    },
  };
}
