// The workspace's profiles in one list (the `profiles` view, docs/station-share.md): a profile shared between stations
// once (the copy on its host when that one is read, else one of the others'), each other one with the station it is
// on. Made from what the stations' overviews say as they come in: a station not read yet adds its own later.
import { t } from "../i18n.ts";

type J = any;

const isObject = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);

/// A station of the workspace as the entries name it.
export type ShareStation = { id: string; station: string; name: string; online: boolean; allowed: boolean };

/// `stations`: the `stations` view's items (each with its decorated overview).
export function workspaceProfiles(stations: J[]): J {
  const byId = new Map(stations.map((s) => [String(s.id), s]));
  const name = (id: string) => String(byId.get(id)?.name ?? id.slice(0, 8));
  const shared = new Map<string, { host?: [J, J]; copies: [J, J][] }>();
  const items: J[] = [];
  let loading = false;
  for (const s of stations) {
    const overview = s.overview;
    if (!isObject(overview)) {
      if (s.online) loading = true;
      continue;
    }
    for (const p of Array.isArray(overview.profiles) ? overview.profiles : []) {
      const share = isObject(p.share) ? p.share : null;
      if (share === null) {
        items.push({ ...entry(s, p, overview.sharing === true), where: t("core-views.profiles.only", { station: String(s.name) }) });
        continue;
      }
      const at = shared.get(share.id) ?? { copies: [] };
      if (share.role === "host") at.host = [s, p];
      else at.copies.push([s, p]);
      shared.set(share.id, at);
    }
  }
  for (const [, at] of shared) {
    const [s, p] = at.host ?? at.copies[0]!;
    const share = p.share;
    const host = byId.get(String(share.host));
    // Away: so still.fail cloud says, or (its word coming later) a station borrowing it found it not answering.
    const hostOnline = host?.online === true && !at.copies.some(([, c]) => c.share?.reachable === false);
    const subscription = p.access?.kind === "subscription";
    const allow: string[] | null = Array.isArray(share.allow) ? share.allow : null;
    const parts: string[] = [];
    if (subscription) parts.push(t("core-views.profiles.signedIn", { station: name(String(share.host)) }));
    if (allow !== null) parts.push(t("core-views.profiles.allowed", { stations: allow.map(name).join("、") }));
    const e = entry(s, p, true);
    e.key = String(share.id);
    e.shared = true;
    e.host = String(share.host);
    e.hostName = name(String(share.host));
    e.hostOnline = hostOnline;
    // A subscription is lent by its host: none can use it while that one is away.
    e.usable = !subscription || hostOnline;
    e.where = parts.join(" · ");
    e.allow = allow;
    e.stations = stations.map(
      (x): ShareStation => ({ id: String(x.id), station: String(x.station), name: String(x.name), online: x.online === true, allowed: allow === null || allow.includes(String(x.id)) || String(x.id) === String(share.host) }),
    );
    // Its page: on its host (where it is changed), while that one is read.
    e.editable = at.host !== undefined;
    items.push(e);
  }
  // What needs a look first (one nobody can use now, one whose check failed), then by name.
  const look = (e: J) => !e.usable || e.profile.checkTone === "red";
  items.sort((a, b) => Number(look(b)) - Number(look(a)) || String(a.profile.name).localeCompare(String(b.profile.name)));
  return { items, loading };
}

function entry(s: J, p: J, canShare: boolean): J {
  return {
    key: `${s.station}/${p.id}`,
    station: String(s.station),
    stationId: String(s.id),
    stationName: String(s.name),
    profile: p,
    shared: false,
    host: String(s.id),
    hostName: String(s.name),
    hostOnline: s.online === true,
    usable: true,
    where: "",
    allow: null,
    stations: [],
    editable: true,
    canShare,
  };
}
