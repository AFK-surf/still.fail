// Chats made public (docs/public-share.md) as a part of the station (parts.ts): the routes that make, keep and revoke
// a snapshot, and the snapshots' visitors on their own protocol of the mesh endpoint (publish/guest.ts: no credential,
// nothing but the snapshots).
import { Effect, Layer } from "effect";
import { routes } from "../api/routes/publish.ts";
import { Parts, Store } from "../services.ts";
import { GUEST_ALPN, Guests } from "./guest.ts";

export const PublishLive = Layer.effectDiscard(
  Effect.gen(function* () {
    const parts = yield* Parts;
    parts.routes((tools) => routes(tools));
    const guests = new Guests(yield* Store);
    parts.alpn(GUEST_ALPN, (conn) => guests.serve(conn));
  }),
);
