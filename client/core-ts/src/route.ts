// What the still.fail core gives its traces (trace.ts): their names, and a request path of its APIs (a station's, the
// cloud's) as a span shows it: no query, and ids as `:id` (`routeBy`), by what their paths list things under.
import { routeBy, type TraceNames } from "./trace.ts";

/// What the core's spans are said to be made by; what its own attributes' names begin with, those the base sets for
/// it too (`stillfail.station`, `stillfail.cause`, `stillfail.cancelled`); and what its host is called where no
/// entry said (hosts/node.ts, bridge.ts and web.ts each say theirs: a core made without one is a native app's on a
/// Mac, as it always was).
export const TRACES: TraceNames = { scope: "stillfail-core", own: "stillfail.", service: { name: "stillfail-native", os: "macos" } };

export const route = routeBy(["sessions", "threads", "connects", "profiles", "logins", "workspaces", "stations", "members", "enrollments", "accounts"]);
