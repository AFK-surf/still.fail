// What a web link in a message is, for its preview card (links/preview.ts), as a part of the station (parts.ts): GET
// /link-preview.
import { Effect, Layer } from "effect";
import { routes } from "../api/routes/links.ts";
import { Parts } from "../services.ts";

export const LinksLive = Layer.effectDiscard(
  Effect.gen(function* () {
    (yield* Parts).routes(routes());
  }),
);
