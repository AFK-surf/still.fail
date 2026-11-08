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
import { log } from "../ops/log.ts";
import { type CommaChats, type CommaIndexes, CommaSurface } from "./surface.ts";
import { CommaTasks } from "./tasks.ts";

type Json = any;

/// A Comma connect as config.json has it, as far as its connection goes.
export type CommaConnect = { id: string; enabled: boolean; server: string; token: string; workspace?: string | null };
type ScopedConnect = CommaConnect & { scopeHome: string | null; scopeVersion: number };

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
  /// The home workspace's index and Router. Called only after the previous station has exited.
  scope: (home: string) => { indexes: CommaIndexes; chats: CommaChats };
  /// The current index and Router are for the home workspace. Other workspaces receive an empty reset until scoped
  /// indexes are available, clearing rows older stations may have sent to them.
  empty: CommaIndexes;
  home: () => string | null;
  homeVersion: () => number;
  onHomeChange: (changed: () => void) => () => void;
  previousExited: Promise<void>;
};

export type CommaParts = ReturnType<typeof makeComma>;

export function makeComma(options: CommaOptions) {
  const tasks = new CommaTasks(join(options.data, "comma-tasks.json"));
  let closing = false;
  let configured = new Map(commaConnects(options.config.raw()).map((c) => [c.id, c]));
  // Update the guard before the connect manager begins its asynchronous reconciliation.
  const stopScope = options.config.listen((raw) => { configured = new Map(commaConnects(raw).map((c) => [c.id, c])); });
  let previousReady = false;
  void options.previousExited.then(() => { previousReady = true; }, () => {});
  const create =
    options.create ??
    ((c: ScopedConnect, book: NameBook, t: CommaTasks) => {
      const home = c.scopeHome, version = c.scopeVersion;
      const isHome = home !== null && (c.workspace === null || c.workspace === undefined || c.workspace === home);
      const inScope = () => {
        if (closing) return false;
        // Also notice a config edited by another process before sending a page or answering a Router request.
        options.config.raw();
        const now = configured.get(c.id);
        return now !== undefined && now.enabled && now.server === c.server && now.token === c.token &&
          (now.workspace ?? null) === (c.workspace ?? null) && (options.inWorkspace?.(c.workspace ?? null) ?? true) &&
          options.home() === home && options.homeVersion() === version;
      };
      const scoped = () => {
        if (!previousReady || home === null || !inScope()) throw new Error("the workspace is handing over; retry");
        return options.scope(home);
      };
      const chats: CommaChats | null = isHome ? {
        read: (ref, after, limit) => scoped().chats.read(ref, after, limit),
        say: (ref, text, key, requester, connect) => scoped().chats.say(ref, text, key, requester, connect),
      } : null;
      return new CommaSurface({ connect: c.id, server: c.server, token: c.token, name: hostname(), tasks: t, store: options.store,
        models: () => options.models?.(c.id) ?? [], book, stats: isHome ? () => scoped().indexes : options.empty,
        chats, inScope, previousExited: options.previousExited });
    });
  const connects = makeConnects<ScopedConnect>(options, {
    kind: "comma",
    names: NAMES_FILE.comma,
    connects: (raw) => commaConnects(raw).map((c) => ({ ...c, scopeHome: options.home(), scopeVersion: options.homeVersion() })),
    // A workspace edit changes what this connection is allowed to see, even if its token is unchanged.
    credentials: (c) => (c.server === "" || c.token === "" ? null : JSON.stringify([c.server, c.token, c.workspace ?? null, c.scopeHome, c.scopeVersion])),
    create: (c, book) => create(c, book, tasks),
    seen: () => null,
  });
  // Reconcile with a new snapshot even when the connection's configured token did not change.
  const stopHome = options.onHomeChange(() => {
    void connects.reconcile().catch((error) => log.warn("comma", "connects not brought in line with the workspace", { error: (error as Error).message }));
  });

  return {
    ...connects,
    close: async () => { closing = true; stopHome(); stopScope(); await connects.close(); },
    tasks,
    /// What the overview says of a Comma connect besides what all connects say.
    shown: (raw: Json): Record<string, unknown> => {
      const c = raw?.comma ?? {};
      return { name: "Comma", team: null, botImage: null, comma: { server: nonEmpty(c.server) ?? "", token: maskToken(nonEmpty(c.token) ?? "") } };
    },
  };
}
