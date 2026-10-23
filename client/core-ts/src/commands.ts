
// What ⌘K's list offers besides what a search finds (`commands.find`, docs/client-core.md): of what a client can do
// now (a key's action some page answers, updating, a settings page), those whose name, id or other words have what was
// typed, by part, in the parts' order. The core names what every client offers alike (the keys' actions, updating,
// relaying a chat) and which are worth a key alone; a client says which it can do now and names what is its own (its
// settings pages), and does what is picked. Nothing here reads more than it is given (the words too: `say`) and the
// keymap's actions, so the web's demo answers with it as the core does.
import { ACTIONS } from "./keymap.ts";

/// Its own isObject (the web's demo takes this file alone, and the web checks it more strictly than util.ts is written for).
const isObject = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);

/// The words of a key in the person's language (i18n.ts `t`).
export type Say = (key: string, args?: Record<string, string>) => string;

/// The parts of what can be done, in the list's order: this chat's, updates, the app's, settings' pages.
export const GROUPS = ["chat", "update", "global", "settings"] as const;
export type Group = (typeof GROUPS)[number];

/// What a client can do now, as it offers it: by id; one the core does not name with its words (`label`, `group`,
/// `words`, `typed`); one whose name takes something, with it (`version` an update goes to, `station` updated).
export type Offer = { id: string; label?: string | undefined; group?: string | undefined; words?: string | undefined; typed?: boolean; version?: string | undefined; station?: string | undefined };

/// One the core names: its part, its name, its other words (its name in English, as an id is), and whether it is only
/// found by typing (one of many alike, or rarely wanted).
type Named = { group: Group; label: (o: Offer, t: Say) => string; words?: string; typed?: true };

/// The keys' actions never listed, however they are offered: ⌘K itself, Esc (which closes the list), and the moves
/// only worth a key (back, forward, the chat above or below, the composer, the latest message).
export const UNLISTED = new Set(["chat.switch", "panel.close", "nav.back", "nav.forward", "chat.prev", "chat.next", "composer.focus", "chat.latest"]);

/// The keys' actions (keymap.ts), each in its part and named as the list of shortcuts names it, but those never listed.
const actions = Object.fromEntries(Object.entries(ACTIONS).filter(([id]) => !UNLISTED.has(id)).map(([id, spec]): [string, Named] => [id, { group: spec.group, label: (_o, t) => t(`web-main.keymap.${id}`) }]));

const NAMED: Record<string, Named> = {
  ...actions,
  "chat.relay": { group: "chat", words: "relay slack feishu lark channel thread 接力 jieli 频道", label: (_o, t) => t("web-main.relay.action") },
  // The page to a newer build of it, the desktop app to its newer build, looking for one now (its version page).
  "update.page": { group: "update", words: "update refresh", label: (_o, t) => t("web-main.webUpdate.foundRefresh") },
  "update.app": { group: "update", words: "update", label: (o, t) => t("web-pages.version.updateTo", { version: o.version ?? "" }) },
  "update.check": { group: "update", words: "check update", typed: true, label: (_o, t) => t("web-pages.version.check") },
  "update.station": {
    group: "update", words: "update station",
    label: (o, t) => (o.station ? `${t("web-main.stationUpdate.updateAction")} · ${o.station}` : t("web-main.stationUpdate.updateAction")),
  },
};

/// A command as the list shows it.
export type Found = { id: string; label: string };
export type FoundGroup = { group: Group; title: string; commands: Found[] };

const isGroup = (g: unknown): g is Group => typeof g === "string" && (GROUPS as readonly string[]).includes(g);
const text = (v: unknown): string | undefined => (typeof v === "string" ? v : undefined);

/// An offer as given, or null when it is none (no id).
function offerOf(raw: unknown): Offer | null {
  if (!isObject(raw) || typeof raw.id !== "string" || raw.id === "") return null;
  return {
    id: raw.id, label: text(raw.label), group: text(raw.group), words: text(raw.words), typed: raw.typed === true,
    version: text(raw.version), station: text(raw.station),
  };
}

/// What of `offered` the list shows for `query`: those whose name (or id, "chat.archive", or other words) has it, with
/// nothing typed all but those only found by typing; by part (GROUPS), each in the order offered, each once.
export function find(query: string, offered: readonly unknown[], t: Say): { groups: FoundGroup[] } {
  const q = query.trim().toLowerCase();
  const seen = new Set<string>();
  const all: { group: Group; id: string; label: string; words: string; typed: boolean }[] = [];
  for (const raw of offered) {
    const o = offerOf(raw);
    if (o === null || UNLISTED.has(o.id) || seen.has(o.id)) continue;
    const named = NAMED[o.id];
    const group = named?.group ?? o.group;
    const label = named ? named.label(o, t) : o.label;
    if (!isGroup(group) || label === undefined || label === "") continue;
    seen.add(o.id);
    all.push({ group, id: o.id, label, words: (named ? named.words : o.words) ?? "", typed: named ? named.typed === true : o.typed === true });
  }
  const found = q ? all.filter((c) => [c.label, c.id, c.words].some((w) => w.toLowerCase().includes(q))) : all.filter((c) => !c.typed);
  const groups: FoundGroup[] = [];
  for (const group of GROUPS) {
    const commands = found.filter((c) => c.group === group).map((c) => ({ id: c.id, label: c.label }));
    if (commands.length > 0) groups.push({ group, title: t(`web-main.switcher.group.${group}`), commands });
  }
  return { groups };
}
