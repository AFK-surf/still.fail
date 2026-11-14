// A session's page in the app (still.fail cloud's pages): the link a new Slack thread is given first ("在 still.fail
// 中查看此会话", hub.ts), a job's service link and a Comma Task's (read/outflow.ts) are all made here.

/// Where this station's session pages are: its control plane's origin, its home workspace and its id there.
export type PageBase = { origin: string; workspace: string; station: string };

/// server.rs `encode` (encodeURIComponent).
const encode = encodeURIComponent;

/// The app's origin for links a station on `channel` gives people: the test channel's (youdid.wtf / monoid.zone) when
/// the station is on `beta`, else `origin`.
export const pageOrigin = (origin: string, channel: "stable" | "beta"): string =>
  channel === "beta"
    ? origin === "https://app.still.fail"
      ? "https://app.youdid.wtf"
      : origin === "https://app.monoid.build"
        ? "https://app.monoid.zone"
        : origin
    : origin;

/// `<origin>/o/<workspace>/<station>/<session key>`.
export const sessionPage = (at: PageBase, workspace: string, key: string): string =>
  `${at.origin}/o/${workspace}/${at.station}/${encode(key)}`;
