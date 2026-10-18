// The station's own browser (browser/service.ts, docs/remote-screens.md) as a part of the station (parts.ts): the
// agents' tool for it.
import { Effect, Layer } from "effect";
import { Parts } from "../services.ts";
import { browserTools } from "../tools/browser.ts";
import { Browser } from "./service.ts";

export const BrowserLive = Layer.effectDiscard(
  Effect.gen(function* () {
    (yield* Parts).tools(browserTools(yield* Browser));
  }),
);
