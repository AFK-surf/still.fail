// The chat list and a chat's messages (admin/mod.rs: GET /chats, GET /threads/:id/entries), and its letters.
import { type Request, error, param } from "../request.ts";
import type { Route, Tools } from "../admin.ts";
import { changed } from "./changed.ts";

/// `page`: the archive a page at a time (read/views.ts `archivedPage`), from its first (`page=`) or on from where one ended.
const chatsOf = (r: Request) => ({ viewer: r.viewer, archived: param(r, "archived") === "1", page: param(r, "page") ?? undefined });

/// `session=<key>&thread=<id>`, repeated: only the items a change of those can touch (read/views.ts `chatRows`), and the
/// ids of those (one not among the items now is gone from the list), for a device that makes its rows itself.
const all = (r: Request, name: string) => r.query.filter(([k]) => k === name).map(([, v]) => v);
const scoped = (r: Request) => ({ viewer: r.viewer, sessions: all(r, "session"), threads: all(r, "thread").filter((id) => /^\d+$/.test(id)).map(Number) });

export const routes = ({ read }: Tools): Route[] => [
  {
    method: "GET",
    pattern: /^\/chats$/,
    handle: (r: Request) => {
      const some = r.query.some(([k]) => k === "session" || k === "thread");
      // `marks=1`: what a device that makes the sidebar itself cannot make of it (read/views.ts `chatMarks`).
      if (param(r, "marks") === "1") return read(r, "chatMarks", { viewer: r.viewer, scope: some ? (({ sessions, threads }) => ({ sessions, threads }))(scoped(r)) : null });
      // `shared=1`: the chat list as the station makes it once for everyone (read/views.ts `sharedChats`), what the viewer
      // sees of it: a device puts what is the viewer's own on it itself (client/core-ts/src/chat-row.ts).
      if (param(r, "shared") === "1") return read(r, "sharedChats", some ? scoped(r) : { viewer: r.viewer, sessions: null, threads: null });
      return some ? read(r, "chatRows", scoped(r)) : read(r, "chats", chatsOf(r));
    },
  },
  { method: "POST", pattern: /^\/changed\/chats$/, handle: (r: Request) => changed(read, r, "chats", chatsOf(r), "id") },
  {
    method: "GET",
    pattern: /^\/threads\/([^/]+)\/entries$/,
    handle: async (r: Request, [id]: string[]) => {
      // A thread id is an i64 in the Rust route; one that is no number is no thread.
      if (!/^[+-]?\d+$/.test(id)) return error(404, `unknown thread ${id}`);
      return read(r, "entries", { viewer: r.viewer, thread: Number(id), params: r.query });
    },
  },
  {
    // its letters, kept in their own log (store/schema.ts LETTERS)
    method: "GET",
    pattern: /^\/threads\/([^/]+)\/letters$/,
    handle: async (r: Request, [id]: string[]) => {
      if (!/^[+-]?\d+$/.test(id)) return error(404, `unknown thread ${id}`);
      return read(r, "letters", { viewer: r.viewer, thread: Number(id), params: r.query });
    },
  },
];
