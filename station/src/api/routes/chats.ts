// The chat list and a chat's messages (admin/mod.rs: GET /chats, GET /threads/:id/entries).
import { type Request, error, param } from "../request.ts";
import type { Route, Tools } from "../admin.ts";
import { changed } from "./changed.ts";

const chatsOf = (r: Request) => ({ viewer: r.viewer, archived: param(r, "archived") === "1" });

export const routes = ({ read }: Tools): Route[] => [
  { method: "GET", pattern: /^\/chats$/, handle: (r: Request) => read(r, "chats", chatsOf(r)) },
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
];
