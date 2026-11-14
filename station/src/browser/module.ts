// The station's browsers (browser/service.ts) as a part of the station (parts.ts): the agents'
// tool for their chat's, each session's way to it on the agents' door (proxy.ts), and a chat's going with its chat.
// Where config.json names Farview (farview.ts), the tool gives each chat's Farview instead of its Chrome context.
import { join } from "node:path";
import { Effect, Layer } from "effect";
import { Parts, Paths, ScreenRegistry, StationConfig } from "../services.ts";
import { browserTools } from "./tool.ts";
import { browserDoor } from "./proxy.ts";
import { Browser } from "./service.ts";
import { FarviewTabs, farviewConfig } from "./farview.ts";

export const BrowserLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const parts = yield* Parts;
    const browser = yield* Browser;
    const config = yield* StationConfig;
    const { data } = yield* Paths;
    const screens = yield* ScreenRegistry;
    const farview = yield* Effect.acquireRelease(
      Effect.sync(() => new FarviewTabs({ dir: join(data, "browser", "farview"), config: () => farviewConfig(config.raw()), screens })),
      (f) => Effect.sync(() => f.close()),
    );
    parts.door(browserDoor(browser));
    parts.sessionEnded((session) => {
      void browser.closeOf(session);
      void farview.closeOf(session);
    });
    parts.tools(browserTools(browser, () => parts.doorUrl(), farview));
  }),
);
