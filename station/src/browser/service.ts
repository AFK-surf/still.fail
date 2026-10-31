// The station's browser (browser.ts) with each chat's own context in it (browsers.ts) as a service: kept in
// <data>/browser, its tabs in the station's screens. The Chrome an earlier station process left running is taken up at
// start, with the chats' contexts in it; when this process ends, it is let go of, not closed (the next one takes it up).
import { join } from "node:path";
import { Context, Effect, Layer } from "effect";
import { Paths, ScreenRegistry } from "../services.ts";
import { Browsers } from "./browsers.ts";
import { chromeHost } from "./chrome.ts";

export class Browser extends Context.Service<Browser, Browsers>()("stillfail/Browser") {
  static readonly layer = Layer.effect(
    Browser,
    Effect.gen(function* () {
      const { data } = yield* Paths;
      const screens = yield* ScreenRegistry;
      const dir = join(data, "browser");
      return yield* Effect.acquireRelease(
        Effect.sync(() => {
          const browser = new Browsers({ dir, chrome: chromeHost({ dir }), screens });
          void browser.resume();
          return browser;
        }),
        (browser) => Effect.promise(() => browser.close()),
      );
    }),
  );
}
