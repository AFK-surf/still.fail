// The still.fail core's host: the base's (host-of.ts: what differs per platform, as Effects), its UIs sent the core's
// messages (protocol.ts); and the header a request of the core's says to be asked twice by, which the host it runs on
// is given (wake.ts `WakingHost`).
import type { HostOf } from "./host-of.ts";
// (still.fail's words over the base's own, which host-of.ts's errors say, before anything given this host asks for
// one: scripts/base.ts holds every file that loads a base file which says a word to loading i18n.ts)
import "./i18n.ts";
import type { CoreMessage } from "./protocol.ts";

export * from "./host-of.ts";

export type Host = HostOf<CoreMessage>;

/// What a request says to be one that may be asked twice though it is not a read. Taken off before it goes.
export const HEDGE = "x-stillfail-hedge";
