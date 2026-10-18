// Phones lent to the station over members' links (mesh/adb.ts) as a part of the station (parts.ts): the agents' tool
// that lists them, with the station's page for them in the app.
import { Effect, Layer } from "effect";
import { Agents } from "../sessions/agents.ts";
import { AdbShares, ControlPlane, Parts } from "../services.ts";
import { adbTools } from "../tools/adb.ts";

export const AdbLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const shares = yield* AdbShares;
    const plane = yield* ControlPlane;
    const { place } = yield* Agents;
    (yield* Parts).tools(
      adbTools(() => shares.list(), () => {
        const s = place();
        return s && plane.spec().pages ? `${s.origin}/w/${s.workspace}/s/${s.station}/adb` : null;
      }),
    );
  }),
);
