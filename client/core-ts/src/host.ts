// The still.fail core's host: the base's (host-of.ts: what differs per platform, as Effects), its UIs sent the core's
// messages (protocol.ts).
import type { HostOf } from "./host-of.ts";
import type { CoreMessage } from "./protocol.ts";

export * from "./host-of.ts";

export type Host = HostOf<CoreMessage>;
