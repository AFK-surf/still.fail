// Chats shared with other workspaces, from the pages (docs/chat-share.md): sharing a chat of this station (its starter
// or a workspace manager), and saying this workspace takes chats from a station of another (any member).
import { type Request, type Answer, error, json, percentDecode } from "../request.ts";
import type { Route } from "../admin.ts";
import type { Store } from "../../store/store.ts";
import type { ChatShares, Target } from "../../xshare/index.ts";

const segment = (s: string) => percentDecode(s.replace(/\+/g, "%2B"));

class Refused extends Error {
  status: number;
  constructor(status: number, message: string) {
    super(message);
    this.status = status;
  }
}

/// A request's JSON object: nothing is `{}`, as is anything not an object; more than a megabyte refused.
function input(r: Request): Record<string, any> {
  if (r.body.length > 1_000_000) throw new Refused(413, "request too large");
  if (r.body.length === 0) return {};
  let value: unknown;
  try {
    value = JSON.parse(r.body.toString("utf8"));
  } catch {
    throw new Refused(400, "invalid JSON");
  }
  return value !== null && typeof value === "object" && !Array.isArray(value) ? (value as Record<string, any>) : {};
}

const str = (v: unknown) => (typeof v === "string" ? v : "");

export const routes = ({ xshare, store }: { xshare?: ChatShares; store?: Store }): Route[] => {
  const answer = async (f: (x: ChatShares, s: Store) => Promise<unknown>): Promise<Answer> => {
    if (xshare === undefined || store === undefined) return error(503, "station starting");
    try {
      return json(200, JSON.stringify(await f(xshare, store)));
    } catch (e) {
      if (e instanceof Refused) return error(e.status, e.message);
      return error(400, (e as Error).message);
    }
  };
  return [
    {
      // Which other workspaces a chat is shared with (by its session key: what its link names); `to: []` stops.
      method: "PUT",
      pattern: /^\/*sessions\/+([^/]+)\/+xshare(?:\/.*)?$/,
      handle: (r, [k]) =>
        answer(async (x, s) => {
          const key = segment(k!);
          // Its own chat on the pages, else the Slack thread it is in.
          const home = s.getSession(key) === null ? null : (s.homeChat(key) ?? s.sessionThreads(key)[0]?.thread ?? null);
          if (home === null) throw new Refused(404, `no chat ${key} on this station`);
          const viewer = r.viewer;
          if (home.createdBy !== viewer.email && viewer.role !== "owner" && viewer.role !== "admin") {
            throw new Refused(403, "only the chat's starter or a workspace owner or admin may share it");
          }
          const i = input(r);
          if (!Array.isArray(i.to)) throw new Refused(400, "to: [{workspace, name, stations: [{id, name}]}]");
          const to: Target[] = i.to.map((t: any) => ({ workspace: str(t?.workspace), name: str(t?.name), stations: t?.stations }));
          return { xshare: await x.share(key, to, i.write === true, viewer.email) };
        }),
    },
    {
      // This workspace takes chats from that station of another workspace (said on one of its stations by a member).
      method: "PUT",
      pattern: /^\/*xshare\/+hosts(?:\/.*)?$/,
      handle: (r) =>
        answer(async (x) => {
          const i = input(r);
          await x.trust(str(i.workspace), str(i.name), str(i.station), str(i.stationName));
          return { ok: true };
        }),
    },
  ];
};
