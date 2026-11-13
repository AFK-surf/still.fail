// A request path of still.fail's APIs (a station's, the cloud's) as a span shows it: no query, and ids as `:id`
// (trace.ts `routeBy`), by what their paths list things under.
import { routeBy } from "./trace.ts";

export const route = routeBy(["sessions", "threads", "connects", "profiles", "logins", "workspaces", "stations", "members", "enrollments", "accounts"]);
