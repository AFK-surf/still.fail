// The station's own browser (browser/service.ts, docs/remote-screens.md) as a part of the station (parts.ts): the
// agents' tool for it, each session's way to it on the agents' door (proxy.ts), and its tabs closed with their chat.
import { Effect, Layer } from "effect";
import { Parts } from "../services.ts";
import { browserTools } from "../tools/browser.ts";
import { browserDoor } from "./proxy.ts";
import { Browser } from "./service.ts";

export const BrowserLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const parts = yield* Parts;
    const browser = yield* Browser;
    parts.door(browserDoor(browser));
    parts.sessionEnded((session) => void browser.closeOf(session));
    parts.tools(browserTools(browser, () => parts.doorUrl()));
  }),
);
