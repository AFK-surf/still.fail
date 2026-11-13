// The copies of this station's chats (replica/copies.ts), as its settings ask of them: on a station with no chat of its
// own, one of the lost stations' copies the overview's `copies.restorable` offers taken back (POST /copies/restore
// `{station, gen, from: {station}}`). The workspace's owners and admins.
import { type Request, error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { managesStation } from "../../mesh/credential.ts";
import type { Copies } from "../../replica/copies.ts";
import type { Retire } from "../../replica/retire.ts";
import { Refused } from "../../mesh/bus.ts";

const body = (r: Request): any => {
  try {
    return JSON.parse(r.body.toString("utf8") || "{}") ?? {};
  } catch {
    return null;
  }
};

export const routes = ({ copies, retire }: { copies: Copies; retire: Retire }): Route[] => [
  // This station retired from the asker's workspace: its chats there go on on `to` (replica/retire.ts). The
  // workspace's owners and admins; GET /retire/preview says what it would move; DELETE calls it off (refused, in words, where it cannot be), POST /retire/again tries
  // a step that failed again now.
  {
    method: "POST",
    pattern: /^\/retire$/,
    handle: async (r: Request) => {
      if (!managesStation(r.viewer)) return error(403, "only the workspace's owners and admins retire a station");
      const b = body(r);
      if (typeof b?.to !== "string") return error(400, "to is needed: the station the chats go to");
      try {
        await retire.retire(r.viewer.workspace, b.to, r.viewer.email);
      } catch (e) {
        return error(e instanceof Refused ? 409 : 500, (e as Error).message);
      }
      return json(202, JSON.stringify({ retiring: true }));
    },
  },
  // What retiring this station from the asker's workspace would move, shown before a person retires it.
  {
    method: "GET",
    pattern: /^\/retire\/preview$/,
    handle: async (r: Request) => {
      if (!managesStation(r.viewer)) return error(403, "only the workspace's owners and admins retire a station");
      try {
        return json(200, JSON.stringify(await retire.preview(r.viewer.workspace)));
      } catch (e) {
        return error(500, (e as Error).message);
      }
    },
  },
  {
    method: "DELETE",
    pattern: /^\/retire$/,
    handle: async (r: Request) => {
      if (!managesStation(r.viewer)) return error(403, "only the workspace's owners and admins retire a station");
      try {
        await retire.cancel(r.viewer.workspace);
      } catch (e) {
        return error(e instanceof Refused ? 409 : 500, (e as Error).message);
      }
      return json(200, JSON.stringify({ ok: true }));
    },
  },
  {
    method: "POST",
    pattern: /^\/retire\/again$/,
    handle: async (r: Request) => {
      if (!managesStation(r.viewer)) return error(403, "only the workspace's owners and admins retire a station");
      try {
        await retire.again(r.viewer.workspace);
      } catch (e) {
        return error(e instanceof Refused ? 409 : 500, (e as Error).message);
      }
      return json(202, JSON.stringify({ ok: true }));
    },
  },
  {
    method: "POST",
    pattern: /^\/copies\/restore$/,
    handle: async (r: Request) => {
      if (!managesStation(r.viewer)) return error(403, "only the workspace's owners and admins restore a lost station's chats");
      const b = body(r);
      const from = b?.from;
      if (typeof b?.station !== "string" || typeof b?.gen !== "string" || typeof from?.station !== "string") return error(400, "station, gen and from: {station} are needed");
      try {
        // (it goes on as the copy is brought; how far it is, the station's settings show)
        copies.restore(r.viewer.workspace, b.station, b.gen, { station: from.station }).catch(() => {});
      } catch (e) {
        return error(409, (e as Error).message);
      }
      return json(202, JSON.stringify({ restoring: true }));
    },
  },
];
