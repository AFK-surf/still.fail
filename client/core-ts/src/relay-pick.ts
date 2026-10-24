// Where a chat is relayed (docs/relay.md): what the picker shows of the places `chat.relayPlaces` read (web/src/Relay.tsx,
// the mbui app's sfdesk/relay.mbt and its phone's sheet). The bot to go on through (the one picked, else the chat's
// own, else the first), the bots offered when there are several, a Slack message's link typed in place of a search,
// and the places of that bot: those whose name has what was typed (those starting with it first), relayed to before
// (the latest first), then by name; nothing typed, of more than FEW places with some relayed to before, only the first
// RECENT of those unless all were asked for. Asked of the core as `chat.relayView`; self-contained: the web imports it,
// typechecked as the web is.

/// A place a connect's bot is in: a channel (a new thread there), a topic group (a new topic) or a group (its
/// conversation taken over); `used`, when it was last relayed to (ms).
export type RelayPlace = { id: string; name: string; kind: "channel" | "topics" | "group"; private?: boolean; used?: number };
/// A connect a chat can be relayed through, with its places (none, and why, when they could not be read).
export type RelayConnect = {
  id: string;
  kind: "slack" | "feishu" | "lark";
  name: string;
  team: string | null;
  botImage?: string | null;
  preferred?: boolean;
  places: RelayPlace[];
  error?: string;
};

/// A place offered: its connect's id and kind, the place, its name as people know it (`#name`, 🔒 before a private
/// channel's), what relaying there does (`note`: a new thread, a new topic, the group's conversation taken over) and
/// what its row says of it at its end in the list (`aside`: none for a channel's new thread).
export type RelayRow = { connect: string; kind: RelayConnect["kind"]; place: RelayPlace; name: string; note: string; aside: string | null };

/// What the picker shows: the Slack message's link typed (its thread offered instead), the bot gone on through, the
/// bots to pick from (several only), the places offered, whether they are only those relayed to before (`recent`, of
/// `total`), why none are (`empty`: nothing at all, or nothing matches), and the connects whose places were not read.
export type RelayView = {
  link: string | null;
  bot: string | null;
  bots: { id: string; label: string }[];
  rows: RelayRow[];
  recent: boolean;
  total: number;
  empty: "noPlaces" | "noMatch" | null;
  unread: string[];
};

type Words = (key: string, args?: Record<string, string | number>) => string;

/** How many places relayed to before are offered first, before 「显示全部」; with no more than FEW in all, all are. */
export const RECENT = 5;
export const FEW = 8;

/** What was typed, as a link to a Slack message (the station finds its workspace among its connects'); else null. */
export function slackLink(typed: string): string | null {
  const s = typed.trim();
  return /^https?:\/\/[^/\s]+\/archives\/[A-Z0-9]+\/p\d{16}/.test(s) ? s : null;
}

/** A place as people know it: a channel's `#name` (🔒 before a private one's), else its name. */
export const placeName = (p: RelayPlace): string => (p.kind === "channel" ? `${p.private ? "🔒 " : ""}#${p.name}` : p.name);

/** What relaying to a place does: a new thread, a new topic, or the group's conversation taken over. */
export const kindNote = (p: RelayPlace, t: Words): string =>
  t(p.kind === "channel" ? "web-main.relay.kind.channel" : p.kind === "topics" ? "web-main.relay.kind.topics" : "web-main.relay.kind.group");

/** The bot it goes on through: the one picked (`chosen`), else the chat's own (the station's preferred), else the first. */
export function relayBot(connects: readonly RelayConnect[], chosen: string | null): RelayConnect | null {
  return connects.find((c) => c.id === chosen) ?? connects.find((c) => c.preferred === true) ?? connects[0] ?? null;
}

/** A bot as people know it: its name, with its workspace (Slack) or tenant (Feishu) when `connects` are in several. */
export const botLabel = (c: RelayConnect, connects: readonly RelayConnect[]): string =>
  c.team !== null && new Set(connects.map((o) => o.team)).size > 1 ? `${c.name} · ${c.team}` : c.name;

const byName = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);

/**
 * The places offered of `connects`: those whose name has what was typed (those starting with it first), else all of
 * them; then those relayed to before (the latest first), then by name. Nothing typed, more than FEW and some relayed to
 * before, only the first RECENT of those (`recent`) unless all were asked for.
 */
export function arrange(connects: readonly RelayConnect[], query: string, all: boolean): { rows: { connect: RelayConnect; place: RelayPlace }[]; recent: boolean; total: number } {
  const q = query.trim().toLowerCase();
  const rows = connects.flatMap((connect) => connect.places.map((place) => ({ connect, place })));
  const total = rows.length;
  const shown = q === "" ? rows : rows.filter((r) => r.place.name.toLowerCase().includes(q));
  const first = (r: { place: RelayPlace }) => (q !== "" && r.place.name.toLowerCase().startsWith(q) ? 0 : 1);
  shown.sort((a, b) => first(a) - first(b) || (b.place.used ?? -1) - (a.place.used ?? -1) || byName(a.place.name.toLowerCase(), b.place.name.toLowerCase()));
  const used = shown.filter((r) => r.place.used !== undefined);
  if (q === "" && !all && total > FEW && used.length > 0) return { rows: used.slice(0, RECENT), recent: true, total };
  return { rows: shown, recent: false, total };
}

/** What the picker shows of `connects` for what was typed, all asked for or not, and the bot picked (null: none yet). */
export function relayView(connects: readonly RelayConnect[], query: string, all: boolean, chosen: string | null, t: Words): RelayView {
  const bot = relayBot(connects, chosen);
  const looked = bot === null ? [] : [bot];
  const { rows, recent, total } = arrange(looked, query, all);
  return {
    link: slackLink(query),
    bot: bot?.id ?? null,
    bots: connects.length > 1 ? connects.map((c) => ({ id: c.id, label: botLabel(c, connects) })) : [],
    rows: rows.map((r) => {
      const note = kindNote(r.place, t);
      return { connect: r.connect.id, kind: r.connect.kind, place: r.place, name: placeName(r.place), note, aside: r.place.kind === "channel" ? null : note };
    }),
    recent,
    total,
    empty: rows.length > 0 || bot === null ? null : query.trim() === "" ? "noPlaces" : "noMatch",
    unread: looked.flatMap((c) => (c.error !== undefined ? [c.error] : [])),
  };
}

const isObj = (v: unknown): v is Record<string, unknown> => typeof v === "object" && v !== null && !Array.isArray(v);
const str = (v: unknown): string => (typeof v === "string" ? v : "");

/** The connects as `chat.relayPlaces` answered them, given back by a client: what is not as it says left out. */
export function readConnects(v: unknown): RelayConnect[] {
  if (!Array.isArray(v)) return [];
  return v.filter(isObj).map((c) => {
    const kind = c.kind === "feishu" || c.kind === "lark" ? c.kind : "slack";
    const places = (Array.isArray(c.places) ? c.places : []).filter(isObj).map((p) => {
      const place: RelayPlace = { id: str(p.id), name: str(p.name), kind: p.kind === "topics" || p.kind === "group" ? p.kind : "channel" };
      if (p.private === true) place.private = true;
      if (typeof p.used === "number" && Number.isFinite(p.used)) place.used = p.used;
      return place;
    });
    const connect: RelayConnect = { id: str(c.id), kind, name: str(c.name), team: typeof c.team === "string" ? c.team : null, places };
    if (typeof c.botImage === "string") connect.botImage = c.botImage;
    if (c.preferred === true) connect.preferred = true;
    if (typeof c.error === "string") connect.error = c.error;
    return connect;
  });
}
