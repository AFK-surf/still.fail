// The workspace's profiles in one list (the `profiles` view, docs/station-share.md), grouped by the kind of account
// (Claude's subscriptions, ChatGPT's, keys), one row an account: the same
// subscription (by its runtime and the address signed in) or the same key (by its provider and key), whether shared
// between stations or signed in on several of them each, is one row; its stations are its members, each with what it
// is there (the one that has it and lends it, one borrowing it, one signed in on its own). Made from what the stations'
// overviews say as they come in: a station not read yet adds its own later.
import { t } from "../i18n.ts";

type J = any;

const isObject = (v: unknown): v is Record<string, any> => v !== null && typeof v === "object" && !Array.isArray(v);
const KEYED = new Set(["opencode-go", "anthropic-api", "api-provider"]);

/// A station of the workspace as the entries name it.
export type ShareStation = { id: string; station: string; name: string; online: boolean; allowed: boolean };

/// Which account a profile is: the same one on several stations has the same identity (null: none to tell by).
function account(p: J): string | null {
  const a = isObject(p.access) ? p.access : {};
  if (a.kind === "subscription") {
    const email = typeof p.email === "string" && p.email !== "" ? p.email.toLowerCase() : null;
    return email === null ? null : `sub:${p.runtime}:${email}`;
  }
  // The key as the station shows it (its first five and last four characters): enough to tell two apart.
  if ((KEYED.has(a.kind) || (a.kind === "env" && a.provider)) && typeof a.key === "string" && a.key !== "") return `key:${a.provider ?? a.kind}:${a.endpoint ?? ""}:${a.key}`;
  return null;
}

/// The kinds of account the list is grouped by, in their order: a vendor's subscription (Claude's, ChatGPT's), then
/// keys and the rest.
const GROUPS = ["claude", "chatgpt", "key"] as const;

function group(p: J): (typeof GROUPS)[number] {
  if (p.access?.kind !== "subscription") return "key";
  return p.runtime === "codex" ? "chatgpt" : "claude";
}

/// `stations`: the `stations` view's items (each with its decorated overview).
export function workspaceProfiles(stations: J[]): J {
  const byId = new Map(stations.map((s) => [String(s.id), s]));
  const name = (id: string) => String(byId.get(id)?.name ?? id.slice(0, 8));
  const groups = new Map<string, [J, J][]>();
  let loading = false;
  for (const s of stations) {
    const overview = s.overview;
    if (!isObject(overview)) {
      if (s.online) loading = true;
      continue;
    }
    for (const p of Array.isArray(overview.profiles) ? overview.profiles : []) {
      const share = isObject(p.share) ? p.share : null;
      const key = account(p) ?? (share ? `share:${share.id}` : `${s.station}/${p.id}`);
      const list = groups.get(key) ?? [];
      list.push([s, p]);
      groups.set(key, list);
    }
  }
  const items: J[] = [];
  for (const [key, list] of groups) {
    const members = list.map(([s, p]) => member(s, p, name, byId));
    // What the row shows of it: the copy that has the login (a host, one signed in on its own) on a station that is up.
    const owns = (m: J) => m.role !== "user";
    const at = members.findIndex((m) => owns(m) && m.online) >= 0 ? members.findIndex((m) => owns(m) && m.online) : members.findIndex(owns) >= 0 ? members.findIndex(owns) : 0;
    const [s, p] = list[at]!;
    const subscription = p.access?.kind === "subscription";
    const share = list.map(([, x]) => x.share).find((x) => isObject(x)) ?? null;
    const signedIn = members.filter(owns).map((m) => m.stationName);
    const allow: string[] | null = share && Array.isArray(share.allow) ? share.allow : null;
    const parts: string[] = [];
    if (members.length === 1 && !share) parts.push(t("core-views.profiles.only", { station: String(s.name) }));
    else if (subscription) parts.push(t("core-views.profiles.signedIn", { station: signedIn.join("、") }));
    else if (!share) parts.push(t("core-views.profiles.on", { stations: members.map((m) => m.stationName).join("、") }));
    if (allow !== null) parts.push(t("core-views.profiles.allowed", { stations: allow.map(name).join("、") }));
    const host = share ? String(share.host) : String(s.id);
    const kind = group(p);
    items.push({
      key,
      group: kind,
      groupTitle: t(`core-views.profiles.group.${kind}`),
      station: String(s.station),
      stationId: String(s.id),
      stationName: String(s.name),
      profile: p,
      shared: share !== null,
      host,
      hostName: name(host),
      hostOnline: byId.get(host)?.online === true,
      // Usable where any of its copies is.
      usable: members.some((m) => m.usable),
      where: parts.join(" · "),
      allow,
      stations: stations.map(
        (x): ShareStation => ({ id: String(x.id), station: String(x.station), name: String(x.name), online: x.online === true, allowed: allow === null || allow.includes(String(x.id)) || String(x.id) === host }),
      ),
      editable: owns(members[at]),
      canShare: s.overview?.sharing === true,
      members,
    });
  }
  // By kind of account; in each, what needs a look first (one nobody can use now, one whose check failed), then by name.
  const look = (e: J) => !e.usable || e.profile.checkTone === "red";
  // Not localeCompare: Hermes on Android asks Java for it, which the app does not carry (it aborts the app).
  const byName = (a: J, b: J) => (String(a.profile.name) < String(b.profile.name) ? -1 : String(a.profile.name) > String(b.profile.name) ? 1 : 0);
  items.sort((a, b) => GROUPS.indexOf(a.group) - GROUPS.indexOf(b.group) || Number(look(b)) - Number(look(a)) || byName(a, b));
  return { items, loading };
}

/// One station's copy of an account: what it is there and how it is doing.
function member(s: J, p: J, name: (id: string) => string, byId: Map<string, J>): J {
  const share = isObject(p.share) ? p.share : null;
  const role = share?.role === "user" ? "user" : share ? "host" : "own";
  const subscription = p.access?.kind === "subscription";
  // A borrowed subscription: as good as its host is reachable (the cloud's word, and the borrower's).
  const hostUp = role !== "user" || (byId.get(String(share.host))?.online === true && share.reachable !== false);
  const online = s.online === true;
  const usable = online && (role !== "user" || !subscription || hostUp);
  const users: string[] = role === "host" && Array.isArray(share.users) ? share.users.map((u: string) => name(u)) : [];
  let about: string;
  if (role === "user") about = t(subscription ? "core-views.profiles.borrows" : "core-views.profiles.copyOf", { station: name(String(share.host)) });
  else if (role === "host") about = users.length > 0 ? t(subscription ? "core-views.profiles.lends" : "core-views.profiles.sharedWith", { stations: users.join("、") }) : t("core-views.profiles.sharedNone");
  else about = t(subscription ? "core-views.profiles.ownLogin" : "core-views.profiles.ownKey");
  return {
    station: String(s.station),
    stationId: String(s.id),
    stationName: String(s.name),
    online,
    profileId: String(p.id),
    role,
    about,
    usable,
    checkText: String(p.checkText ?? ""),
    checkTone: String(p.checkTone ?? "neutral"),
    usedBy: Array.isArray(p.usedBy) ? p.usedBy.length : 0,
  };
}
