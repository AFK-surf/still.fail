// How a workspace's members' devices reach its stations (the `workspaceWays` view, the workspace page's 连接方式): still.fail's
// relays as `/v1/me` names them, the workspace's own, the ways straight to a station that are no relay; each on unless the
// workspace's `ways_off` says it is turned off (cloud directory.ts setWay, mesh.ts `Mesh.link` `off`). All of it is in
// `/v1/me`, kept on the device: shown at once, no read of the workspace waited for (2026-10-29 the user, the panel empty
// until the workspace was read again: 莫名其妙等半天).
import { t } from "../i18n.ts";

/// One way: a relay (`id` its URL; `name` what still.fail calls it, or its host; `own` the workspace's), or a kind of
/// way that is no relay (`id` and `kind` lan, tailnet, direct).
export type WayRow = { id: string; kind: "relay" | "lan" | "tailnet" | "direct"; name: string; own: boolean; on: boolean };
export type WaysView = { ways: WayRow[]; off: number; offLabel: string };

/// The kinds of way that are no relay, in the order they are listed.
const KINDS = ["lan", "tailnet", "direct"] as const;

const same = (a: string, b: string): boolean => {
  const norm = (u: string) => (URL.canParse(u) ? new URL(u).href : u).replace(/\/+$/, "");
  return norm(a) === norm(b);
};

const host = (url: string): string => (URL.canParse(url) ? new URL(url).host || url : url);

/// The view from still.fail's relays (`relays`, what each is called: `names`, by URL), the workspace's own and what it
/// turned off.
export function waysView(relays: string[], names: Record<string, unknown>, own: string[], off: string[]): WaysView {
  const isOff = (id: string) => off.some((o) => same(o, id));
  const named = (url: string) => {
    const n = Object.entries(names).find(([u]) => same(u, url))?.[1];
    return typeof n === "string" && n !== "" ? n : host(url);
  };
  const ours = relays.filter((r, i) => relays.findIndex((o) => same(o, r)) === i);
  const ways: WayRow[] = [
    ...ours.map((url): WayRow => ({ id: url, kind: "relay", name: named(url), own: false, on: !isOff(url) })),
    ...own.filter((u) => !ours.some((o) => same(o, u))).map((url): WayRow => ({ id: url, kind: "relay", name: host(url), own: true, on: !isOff(url) })),
    ...KINDS.map((kind): WayRow => ({ id: kind, kind, name: "", own: false, on: !off.includes(kind) })),
  ];
  const n = ways.filter((w) => !w.on).length;
  return { ways, off: n, offLabel: n === 0 ? t("core-views.ways.all_on") : t("core-views.ways.some_off", { n }) };
}
