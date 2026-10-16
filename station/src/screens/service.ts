// The station's screens (source.ts) as a service: the registry its parts add their sources to (the browser per tab,
// the desktop) and the remote control lists and opens them from (docs/remote-screens.md).
import { Context, Effect, Layer } from "effect";
import { type Screens, makeScreens } from "./source.ts";

export class ScreenRegistry extends Context.Service<ScreenRegistry, Screens & { changed(): void }>()("stillfail/Screens") {
  static readonly layer = Layer.effect(ScreenRegistry, Effect.sync(makeScreens));
}
