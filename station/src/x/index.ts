// X on the station (docs/x.md): its connects as every platform's are kept (connects/connects.ts: connected as
// config.json and the station's workspace say, what X calls people in <data>/x-names.json), and where each is in what
// was said to it (<data>/x-threads.json).
import { join } from "node:path";
import type { Clock } from "effect";
import type { Connection } from "../connects/connections.ts";
import { type ConnectsOptions, makeConnects } from "../connects/connects.ts";
import { NAMES_FILE } from "../connects/keys.ts";
import type { NameBook } from "../connects/names.ts";
import { XSurface } from "./surface.ts";
import { XThreads } from "./threads.ts";
import type { XKeys } from "./web.ts";

type Json = any;

/// Someone on a connect's list: their account's id (what is checked) and handle (what is shown).
export type Allowed = { id: string; username: string };

/// An X connect as config.json has it, as far as its connection goes.
export type XConnect = XKeys & {
  id: string;
  enabled: boolean;
  botName: string | null;
  botImage: string | null;
  botUserId: string | null;
  botUsername: string | null;
  workspace?: string | null;
};

const nonEmpty = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);
const str = (v: unknown): string => (typeof v === "string" ? v : "");

export function xConnects(raw: Json): XConnect[] {
  return (Array.isArray(raw?.connects) ? raw.connects : [])
    .filter((c: Json) => c?.kind === "x")
    .map((c: Json): XConnect => {
      const x = c?.x ?? {};
      return {
        id: String(c?.id ?? ""),
        enabled: c?.enabled !== false,
        consumerKey: str(x.consumerKey),
        consumerSecret: str(x.consumerSecret),
        accessToken: str(x.accessToken),
        accessSecret: str(x.accessSecret),
        botName: nonEmpty(x.botName),
        botImage: nonEmpty(x.botImage),
        botUserId: nonEmpty(x.botUserId),
        botUsername: nonEmpty(x.botUsername),
        workspace: nonEmpty(c?.workspace),
      };
    });
}

/// A connect's list, as its config entry has it (`x.allow`).
export function allowedOf(entry: Json): Allowed[] {
  return (Array.isArray(entry?.x?.allow) ? entry.x.allow : []).flatMap((a: Json) => (typeof a?.id === "string" && a.id !== "" ? [{ id: a.id, username: str(a.username) }] : []));
}

/// A key as the pages are shown it.
export const maskKey = (s: string) => (s.length <= 4 ? (s === "" ? "" : "••••") : `••••${s.slice(-4)}`);

export type XOptions = ConnectsOptions & {
  clock?: Clock.Clock;
  /// How a connect's connection is made (tests); default an XSurface.
  create?: (connect: XConnect, book: NameBook, threads: XThreads) => Connection;
};

export type XParts = ReturnType<typeof makeX>;

export function makeX(options: XOptions) {
  const threads = new XThreads(join(options.data, "x-threads.json"));
  const entry = (id: string): Json => (Array.isArray(options.config.raw()?.connects) ? options.config.raw().connects : []).find((c: Json) => c?.id === id && c?.kind === "x") ?? null;
  const create =
    options.create ??
    ((c: XConnect, book: NameBook, t: XThreads) =>
      new XSurface({
        connect: c.id,
        keys: c,
        threads: t,
        book,
        clock: options.clock,
        // Read again for each poll: the list, its links and posts' length change without connecting again.
        allowed: () => new Set(allowedOf(entry(c.id)).map((a) => a.id)),
        links: () => entry(c.id)?.x?.links === true,
        maxLength: () => {
          const n = entry(c.id)?.x?.maxLength;
          return typeof n === "number" && n >= 280 && n <= 25_000 ? Math.floor(n) : 280;
        },
      }));
  const connects = makeConnects<XConnect>(options, {
    kind: "x",
    names: NAMES_FILE.x,
    connects: xConnects,
    credentials: (c) => (c.consumerKey === "" || c.consumerSecret === "" || c.accessToken === "" || c.accessSecret === "" ? null : [c.consumerKey, c.consumerSecret, c.accessToken, c.accessSecret].join("\n")),
    create: (c, book) => create(c, book, threads),
    // Its account's name, picture and handle.
    seen: (c, i) => {
      const username = i.team.replace(/^@/, "");
      if (c.botName === i.botName && c.botImage === i.botImage && c.botUserId === i.botUserId && c.botUsername === (username || null)) return null;
      return (entry) => {
        entry.x = entry.x !== null && typeof entry.x === "object" ? entry.x : {};
        entry.x.botName = i.botName;
        entry.x.botUserId = i.botUserId;
        if (username !== "") entry.x.botUsername = username;
        if (i.botImage !== null) entry.x.botImage = i.botImage;
        else delete entry.x.botImage;
      };
    },
  });

  return {
    ...connects,
    threads,
    /// What the overview says of an X connect besides what all connects say: its keys masked, its list.
    shown: (raw: Json): Record<string, unknown> => {
      const x = raw?.x ?? {};
      const live = connects.chat(String(raw?.id ?? ""))?.identity();
      const username = nonEmpty(x.botUsername) ?? (live && live.team !== "" ? live.team.replace(/^@/, "") : null);
      return {
        name: nonEmpty(x.botName) ?? live?.botName ?? raw?.id,
        team: username === null ? null : `@${username}`,
        botImage: nonEmpty(x.botImage),
        x: {
          consumerKey: maskKey(str(x.consumerKey)),
          consumerSecret: maskKey(str(x.consumerSecret)),
          accessToken: maskKey(str(x.accessToken)),
          accessSecret: maskKey(str(x.accessSecret)),
          username,
          allow: allowedOf(raw),
          links: x.links === true,
          maxLength: typeof x.maxLength === "number" ? x.maxLength : 280,
        },
      };
    },
  };
}
