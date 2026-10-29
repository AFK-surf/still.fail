// Running as the machine's administrator, a part of a Windows station (parts.ts; elevation.ts says how): the overview's
// `elevation` to any member, PUT /elevation `{on}` for the workspace's owners and admins. Not on other systems.
import { Effect, Layer } from "effect";
import type { Route } from "../api/admin.ts";
import { type Answer, type Request, error, json } from "../api/request.ts";
import { managesStation } from "../mesh/credential.ts";
import { tr } from "../ops/i18n.ts";
import { wall } from "../ops/fibers.ts";
import { log } from "../ops/log.ts";
import { platform } from "../platform/index.ts";
import { Events, Parts, Paths } from "../services.ts";
import { ChangeRefused, Elevation } from "./elevation.ts";

export function elevationRoutes(elevation: Elevation): Route[] {
  return [
    {
      method: "PUT",
      pattern: /^\/elevation$/,
      handle: async (r: Request): Promise<Answer> => {
        if (!managesStation(r.viewer)) return error(403, tr(r.lang, "station.elevation.managersOnly"));
        let on: unknown;
        try {
          on = JSON.parse(r.body.toString("utf8") || "{}")?.on;
        } catch {
          return error(400, "invalid JSON");
        }
        if (typeof on !== "boolean") return error(400, "on is true or false");
        try {
          elevation.change(on);
        } catch (e) {
          if (e instanceof ChangeRefused) return error(409, tr(r.lang, `station.elevation.${e.key}`));
          throw e;
        }
        log.info("elevation", "running as administrator asked", { on, by: r.viewer.email });
        return json(200, JSON.stringify(elevation.view(true)));
      },
    },
  ];
}

export const ElevationLive = Layer.effectDiscard(
  Effect.gen(function* () {
    if (platform.os !== "windows") return;
    const { data, app } = yield* Paths;
    const events = yield* Events;
    const parts = yield* Parts;
    const elevation = new Elevation({ data, app, now: wall.now, after: wall.after, changed: () => events.overviewChanged() });
    yield* Effect.acquireRelease(
      Effect.sync(() => void elevation.start().catch((e) => log.warn("elevation", "how it runs not looked at", { error: (e as Error).message }))),
      () => Effect.sync(() => elevation.stop()),
    );
    parts.routes(elevationRoutes(elevation));
    parts.overview("elevation", (viewer) => elevation.view(managesStation(viewer)));
  }),
);
