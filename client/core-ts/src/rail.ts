// The wide screen's rail as clients draw it (prefs `railView`; web/src/Rail.tsx, the mbui app's wide.mbt): which places,
// in what order, as each workspace keeps them, what is left out by kind, their words. Self-contained (only i18n.ts):
// the web's demo builds its prefs with it, typechecked as the web is.
import { current, tr, type Lang } from "./i18n.ts";

/// Every place the rail can show, in the order its settings list them: the chats' lists (each the sidebar's list it
/// shows, `listFilter`'s word), 待处理 (a panel), the pages.
export const RAIL_PLACES = ["chats", "mine", "watching", "archive", "attention", "files", "stations", "profiles", "connects", "usage"];
/// What it shows when none was chosen.
export const RAIL_DEFAULT = ["attention", "chats", "files", "stations", "profiles", "connects", "usage"];
const RAIL_LISTS: Record<string, string> = { chats: "all", mine: "mine", watching: "watching", archive: "archive" };
/// Each place's words, as the rail's tip and its settings say them (the web's own keys; Station and Profile are names).
const RAIL_WORDS: Record<string, string> = {
  chats: "web-main.rail.chats", mine: "web-main.filter.chats.mine", watching: "web-main.filter.watching", archive: "web-main.filter.archived",
  attention: "web-main.attention.entry", files: "web-pages.drive.title",
  connects: "web-pages.settings.nav.connects", usage: "web-pages.settings.nav.usage",
};
const RAIL_NAMES: Record<string, string> = { stations: "Station", profiles: "Profile" };
/// What can be put in it, by kind, as the panel that adds them groups them: pages of their own, the chats' lists, 待处理.
const RAIL_KINDS: [string, string[]][] = [
  ["places", ["files", "stations", "profiles", "connects", "usage"]],
  ["lists", ["chats", "mine", "watching", "archive"]],
  ["attention", ["attention"]],
];

export type RailOf = { items: string[]; hidden: string[]; changed: boolean };
export type RailPlace = { id: string; label: string; kind: string; list?: string };
export type RailView = { places: RailPlace[]; groups: { kind: string; label: string; places: string[] }[]; default: string[]; all: RailOf; by: Record<string, RailOf> };

/// A rail as kept (`rail`, or a workspace's in `rails`): the places this build knows, each once, in their order; none
/// kept, the default. With it the places left out (in the settings' order) and whether it is other than the default.
export function railOf(kept: unknown): RailOf {
  const items = Array.isArray(kept) ? [...new Set(kept.filter((k): k is string => typeof k === "string" && RAIL_PLACES.includes(k)))] : [...RAIL_DEFAULT];
  return { items, hidden: RAIL_PLACES.filter((p) => !items.includes(p)), changed: items.join() !== RAIL_DEFAULT.join() };
}

function place(id: string, lang: Lang): RailPlace {
  const kind = RAIL_KINDS.find(([, ids]) => ids.includes(id))?.[0] ?? "places";
  const words = RAIL_WORDS[id];
  const label = RAIL_NAMES[id] ?? (words !== undefined ? tr(lang, words) : id);
  const list = RAIL_LISTS[id];
  return list !== undefined ? { id, label, kind, list } : { id, label, kind };
}

/// The rail as a client draws it, from the prefs kept (`rail`, `rails`): every place, its words and kind; the kinds the
/// panel groups them by; the default; the rail of a workspace with none of its own and each one's own. Said in `lang`
/// (the core's own language unless told).
export function railView(prefs: { rail?: unknown; rails?: unknown }, lang: Lang = current()): RailView {
  const rails = prefs.rails;
  const by: Record<string, RailOf> = {};
  if (rails !== null && typeof rails === "object" && !Array.isArray(rails)) for (const [ws, r] of Object.entries(rails)) by[ws] = railOf(r);
  return {
    places: RAIL_PLACES.map((id) => place(id, lang)),
    groups: RAIL_KINDS.map(([kind, places]) => ({ kind, label: tr(lang, `web-main.rail.kind.${kind}`), places: [...places] })),
    default: [...RAIL_DEFAULT],
    all: railOf(prefs.rail),
    by,
  };
}
