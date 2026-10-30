// The workspace's profiles in one list (the `profiles` view, docs/station-share.md), grouped by the kind of account
// (Claude's subscriptions, ChatGPT's, SuperGrok's, Cursor's, Devin's, keys), one row an account: the same
// subscription (by its runtime and the address signed in) or the same key (by its provider and key), whether shared
// between stations or signed in on several of them each, is one row; its stations are its members, each with what it
// is there (the one that has it and lends it, one borrowing it, one signed in on its own). Made from what the stations'
// overviews say as they come in: a station not read yet adds its own later.
import { t } from "../i18n.ts";
import { waitNote } from "../looks.ts";

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

/// The kinds of account the list is grouped by, in their order: a vendor's subscription (Claude's, ChatGPT's, SuperGrok's,
/// Kimi Code's, OpenCode Go's, Cursor's, Devin's), then keys and the rest. A profile signed in to an account rather than
/// given a key (`access.login`: Kimi Code's, OpenCode Go's) is its vendor's subscription.
export const GROUPS = ["claude", "chatgpt", "grok", "kimi", "opencode", "cursor", "devin", "key"] as const;

export function group(p: J): (typeof GROUPS)[number] {
  if (p.access?.login === true) return p.access?.provider === "kimi-code" ? "kimi" : "opencode";
  if (p.access?.kind !== "subscription") return "key";
  return p.runtime === "codex" ? "chatgpt" : p.runtime === "grok" ? "grok" : p.runtime === "cursor" ? "cursor" : p.runtime === "devin" ? "devin" : "claude";
}

/// A kind of account in words: Claude 订阅.
export const groupTitle = (kind: (typeof GROUPS)[number]) => t(`core-views.profiles.group.${kind}`);

/// `stations`: the `stations` view's items (each with its decorated overview).
export function workspaceProfiles(stations: J[]): J {
  const byId = new Map(stations.map((s) => [String(s.id), s]));
  const name = (id: string) => String(byId.get(id)?.name ?? id.slice(0, 8));
  const groups = new Map<string, [J, J][]>();
  const waiting: string[] = [];
  for (const s of stations) {
    const overview = s.overview;
    if (!isObject(overview)) {
      if (s.online) {
        waiting.push(name(String(s.id)));
      }
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
    // A station with two of its profiles signed in to the account: each row named by its profile too, or they read alike.
    for (const m of members) if (members.filter((x) => x.stationId === m.stationId).length > 1 && m.profileName !== "") m.title = `${m.stationName} · ${m.profileName}`;
    // What the row shows of it: the copy that has the login (a host, one signed in on its own) on a station that is up,
    // one that works before one in trouble (which the row then names by its station).
    const owns = (m: J) => m.role !== "user";
    const troubled = (i: number) => isObject(list[i]![1].trouble);
    const first = (ok: (m: J, i: number) => boolean) => members.findIndex(ok);
    const at = [first((m, i) => owns(m) && m.online && !troubled(i)), first((m) => owns(m) && m.online), first(owns), 0].find((i) => i >= 0)!;
    const [s, p] = list[at]!;
    const subscription = p.access?.kind === "subscription";
    const share = list.map(([, x]) => x.share).find((x) => isObject(x)) ?? null;
    // Each station once: two of its profiles signed in to the same account are one place it is signed in.
    const stationsOf = (ms: J[]): string[] => [...new Map(ms.map((m) => [m.stationId, m.stationName])).values()];
    const signedIn = stationsOf(members.filter(owns));
    const allow: string[] | null = share && Array.isArray(share.allow) ? share.allow : null;
    const host = share ? String(share.host) : String(s.id);
    // Where the account can be used, said of the account (the row) and not of one copy's share: where it is signed in,
    // then the stations that use it only by borrowing (who may borrow is the profile page's).
    const joined = (names: string[]) => names.join(t("core-views.list_separator"));
    const parts: string[] = [];
    if (members.length === 1 && !share) parts.push(t("core-views.profiles.only", { station: String(s.name) }));
    else if (subscription) {
      parts.push(t("core-views.profiles.signedIn", { station: joined(signedIn) }));
      const borrowers = stationsOf(members.filter((m) => !owns(m))).filter((x) => !signedIn.includes(x));
      if (borrowers.length > 0) parts.push(signedIn.length > 1 ? t("core-views.profiles.lentBy", { station: name(host), stations: joined(borrowers) }) : t("core-views.profiles.lent", { stations: joined(borrowers) }));
    } else parts.push(t("core-views.profiles.on", { stations: joined(stationsOf(members)) }));
    const kind = group(p);
    const usable = members.some((m) => m.usable);
    items.push({
      key,
      group: kind,
      groupTitle: groupTitle(kind),
      station: String(s.station),
      stationId: String(s.id),
      stationName: String(s.name),
      profile: p,
      shared: share !== null,
      host,
      hostName: name(host),
      hostOnline: byId.get(host)?.online === true,
      // Usable where any of its copies is.
      usable,
      ...stateOf(usable, name(host), p, signedIn.length > 1 ? troubleOn(list, members) : null),
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
  // By kind of account; in each, what needs a look first, then by name.
  // Not localeCompare: Hermes on Android asks Java for it, which the app does not carry (it aborts the app).
  const byName = (a: J, b: J) => (String(a.profile.name) < String(b.profile.name) ? -1 : String(a.profile.name) > String(b.profile.name) ? 1 : 0);
  items.sort((a, b) => GROUPS.indexOf(a.group) - GROUPS.indexOf(b.group) || Number(b.look) - Number(a.look) || byName(a, b));
  return { items, attention: items.filter((e) => e.look).length, wait: waitNote(waiting, [], items.length === 0) };
}

/// How an account is, where that is not simply fine, as its row says it (`state`: its words and their tone), and whether
/// it needs a look (`look`: counted where its list is entered, first in its kind, in colour): nobody can use it now (its
/// host away, red); else its trouble (present.ts profileTrouble: stopped by its provider, its check failed or wants a
/// sign-in, its allowance not read), in its check's words where the check did not pass, else the trouble's; else a check
/// not made (未检查, neutral), which needs none.
/// `on`: of an account signed in on several stations, the trouble of those of its copies that have one, said with
/// where (the row's own copy may be one that works).
function stateOf(usable: boolean, hostName: string, p: J, on: { stations: string[]; p: J } | null): { state: J; look: boolean } {
  if (!usable) return { state: { text: t("core-views.profiles.away", { station: hostName }), tone: "red" }, look: true };
  if (on !== null) {
    const { state, look } = stateOf(true, hostName, on.p, null);
    return { state: state === null ? null : { ...state, text: t("core-views.profiles.troubleOn", { station: on.stations.join(t("core-views.list_separator")), trouble: state.text }) }, look };
  }
  const green = p.checkTone === "green";
  if (isObject(p.trouble)) return { state: green ? { text: String(p.trouble.title ?? ""), tone: "amber" } : { text: String(p.checkText ?? ""), tone: String(p.checkTone) }, look: true };
  return { state: green || !p.checkText ? null : { text: String(p.checkText), tone: String(p.checkTone ?? "neutral") }, look: false };
}

/// Of an account's copies, those signed in on a station that is up and in trouble: their stations, and the first's profile
/// (null: none).
function troubleOn(list: [J, J][], members: J[]): { stations: string[]; p: J } | null {
  const found = members.flatMap((m, i) => (m.role !== "user" && m.online && isObject(list[i]![1].trouble) ? [i] : []));
  if (found.length === 0) return null;
  return { stations: [...new Set(found.map((i) => String(members[i]!.stationName)))], p: list[found[0]!]![1] };
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
  else if (role === "host") about = users.length > 0 ? t(subscription ? "core-views.profiles.lends" : "core-views.profiles.sharedWith", { stations: users.join(t("core-views.list_separator")) }) : t("core-views.profiles.sharedNone");
  else about = t(subscription ? "core-views.profiles.ownLogin" : "core-views.profiles.ownKey");
  return {
    station: String(s.station),
    stationId: String(s.id),
    stationName: String(s.name),
    title: String(s.name),
    online,
    profileId: String(p.id),
    profileName: String(p.name ?? ""),
    role,
    about,
    usable,
    checkText: String(p.checkText ?? ""),
    checkTone: String(p.checkTone ?? "neutral"),
    usedBy: Array.isArray(p.usedBy) ? p.usedBy.length : 0,
  };
}
