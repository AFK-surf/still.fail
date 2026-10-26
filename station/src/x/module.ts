// The X connects as a part of the agents' side (docs/x.md; connects/part.ts says what every platform's connects are
// there): an X connect as the overview shows it and the pages edit it, the X routes, and x_api for the agents.
import { Effect, Layer } from "effect";
import { xEntry, xRoutes } from "../api/routes/x.ts";
import { connectsPart } from "../connects/part.ts";
import { Agents } from "../sessions/agents.ts";
import { Parts, Paths, StationConfig } from "../services.ts";
import { makeX } from "./index.ts";
import { xTools } from "./tool.ts";

export const XLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const { data } = yield* Paths;
    const config = yield* StationConfig;
    const parts = yield* Parts;
    const agents = yield* Agents;
    const x = yield* connectsPart(makeX, { kind: "x", shown: (x, c) => x.shown(c), entry: xEntry });
    // A station with X's connects says so (the pages offer one only then).
    parts.overview("xConnects", () => true);
    parts.routes(
      xRoutes({
        config, data,
        hub: () => agents.hub,
        overview: (viewer, lang) => agents.overview(viewer, lang),
        place: () => agents.place(),
      }),
    );
    const isX = (connect: string) => x.connects().some((c) => c.id === connect);
    parts.tools(xTools(() => agents.hub, isX));
  }),
);
