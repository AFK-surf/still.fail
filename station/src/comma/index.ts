// Comma on the station: its connects as every platform's are kept (connects/connects.ts: connected as config.json and
// the station's workspace say, what Comma calls its people in <data>/comma-names.json), and the Comma Tasks their
// agents work in (<data>/comma-tasks.json). A Comma connect is made of the line Comma's still.fail plugin shows:
// `comma <server> <token>`.
import { hostname } from "node:os";
import { join } from "node:path";
import type { Connection } from "../connects/connections.ts";
import { type ConnectsOptions, makeConnects } from "../connects/connects.ts";
import { NAMES_FILE } from "../connects/keys.ts";
import type { NameBook } from "../connects/names.ts";
import type { CommaStats } from "./stats.ts";
import { type CommaChats, CommaSurface } from "./surface.ts";
import { CommaTasks } from "./tasks.ts";

type Json = any;

/// A Comma connect as config.json has it, as far as its connection goes.
export type CommaConnect = { id: string; enabled: boolean; server: string; token: string; workspace?: string | null };

const nonEmpty = (v: unknown): string | null => (typeof v === "string" && v !== "" ? v : null);

export function commaConnects(raw: Json): CommaConnect[] {
  return (Array.isArray(raw?.connects) ? raw.connects : [])
    .filter((c: Json) => c?.kind === "comma")
    .map((c: Json): CommaConnect => ({
      id: String(c?.id ?? ""),
      enabled: c?.enabled !== false,
      server: nonEmpty(c?.comma?.server) ?? "",
      token: nonEmpty(c?.comma?.token) ?? "",
      workspace: nonEmpty(c?.workspace),
    }));
}

/// The line Comma's still.fail plugin shows, `comma <server> <token>`, as its server and token; null when it is not one.
export function commaLine(line: string): { server: string; token: string } | null {
  const words = line.trim().split(/\s+/);
  if (words.length !== 3 || words[0] !== "comma") return null;
  const [, server, token] = words as [string, string, string];
  let url: URL;
  try {
    url = new URL(server);
  } catch {
    return null;
  }
  if ((url.protocol !== "https:" && url.protocol !== "http:") || !/^[A-Za-z0-9_-]{8,512}$/.test(token)) return null;
  return { server: url.origin, token };
}

/// A token as the pages are shown it.
export const maskToken = (s: string) => (s.length <= 4 ? (s === "" ? "" : "••••") : `••••${s.slice(-4)}`);

export type CommaOptions = ConnectsOptions & {
  /// How a connect's connection is made (tests); default a CommaSurface.
  create?: (connect: CommaConnect, book: NameBook, tasks: CommaTasks) => Connection;
  /// The workspace's statistics its connections send Comma (stats.ts).
  stats?: CommaStats | null;
  /// The chats of its Task index as the Router reads and writes in them (module.ts).
  chats?: CommaChats | null;
};

export type CommaParts = ReturnType<typeof makeComma>;

export function makeComma(options: CommaOptions) {
  const tasks = new CommaTasks(join(options.data, "comma-tasks.json"));
  const create =
    options.create ??
    ((c: CommaConnect, book: NameBook, t: CommaTasks) =>
      new CommaSurface({ connect: c.id, server: c.server, token: c.token, name: hostname(), tasks: t, store: options.store, models: () => options.models?.(c.id) ?? [], book, stats: options.stats ?? null, chats: options.chats ?? null }));
  const connects = makeConnects<CommaConnect>(options, {
    kind: "comma",
    names: NAMES_FILE.comma,
    connects: commaConnects,
    credentials: (c) => (c.server === "" || c.token === "" ? null : `${c.server}\n${c.token}`),
    create: (c, book) => create(c, book, tasks),
    seen: () => null,
  });

  return {
    ...connects,
    tasks,
    /// What the overview says of a Comma connect besides what all connects say.
    shown: (raw: Json): Record<string, unknown> => {
      const c = raw?.comma ?? {};
      return { name: "Comma", team: null, botImage: null, comma: { server: nonEmpty(c.server) ?? "", token: maskToken(nonEmpty(c.token) ?? "") } };
    },
  };
}
