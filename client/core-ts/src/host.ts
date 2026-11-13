// The still.fail core's host: the base's (host-of.ts: what differs per platform, as Effects), its UIs sent the core's
// messages (protocol.ts); and the header a request of the core's says to be asked twice by, which the host it runs on
// is given (wake.ts `WakingHost`).
import type { HostOf } from "./host-of.ts";
import type { CoreMessage } from "./protocol.ts";

export * from "./host-of.ts";

export type Host = HostOf<CoreMessage>;

/// What a request says to be one that may be asked twice though it is not a read. Taken off before it goes.
export const HEDGE = "x-stillfail-hedge";
