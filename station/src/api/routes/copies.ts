// The copies of this station's chats (replica/copies.ts), as its settings ask of them: on a station with no chat of its
// own, one of the lost stations' copies the overview's `copies.restorable` offers taken back (POST /copies/restore
// `{station, gen, from: {station}}`). The workspace's owners and admins.
import { type Request, error, json } from "../request.ts";
import type { Route } from "../admin.ts";
import { managesStation } from "../../mesh/credential.ts";
import type { Copies } from "../../replica/copies.ts";

const body = (r: Request): any => {
  try {
    return JSON.parse(r.body.toString("utf8") || "{}") ?? {};
  } catch {
    return null;
  }
};

export const routes = ({ copies }: { copies: Copies }): Route[] => [
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
