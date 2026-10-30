// The app's keyboard shortcuts (the prefs' `keymap`; `keys.set`): each action, where it works, the keys of its own and
// those changed on this device (the prefs' `keys`, the desktop app's only), as a key cap shows them on this device.
// A client only turns a key press into a binding (its key events are its own) and looks it up here. Of the core it
// reads only its words: the web's demo makes its keymap with it (web/src/demo/mount.tsx).
import { t } from "./i18n.ts";

const isObject = (v: unknown): v is Record<string, unknown> => v !== null && typeof v === "object" && !Array.isArray(v);

type Spec = {
  /// Where it works: anywhere in the app, in a chat, or in a folder of the files.
  group: "global" | "chat" | "files";
  keys: string[];
  /// Only in the desktop app, where the browser takes no keys for itself.
  desktop?: string[];
  /// Whether it works with the cursor in a text field: always (a binding with ⌘ or ⌥ does nothing there), never (it is
  /// a key the field types), or when the field is empty (the key moves the cursor in text).
  typing: "yes" | "no" | "empty";
};

/// The actions, in the order the list of shortcuts has them, with their own keys.
export const ACTIONS: Record<string, Spec> = {
  "chat.switch": { group: "global", keys: ["Mod+K"], typing: "yes" },
  "chat.new": { group: "global", keys: ["Mod+Alt+N"], desktop: ["Mod+N"], typing: "yes" },
  "chat.prev": { group: "global", keys: ["Alt+Up"], typing: "yes" },
  "chat.next": { group: "global", keys: ["Alt+Down"], typing: "yes" },
  "sidebar.toggle": { group: "global", keys: ["Mod+\\"], typing: "yes" },
  "nav.back": { group: "global", keys: [], desktop: ["Mod+["], typing: "yes" },
  "nav.forward": { group: "global", keys: [], desktop: ["Mod+]"], typing: "yes" },
  "settings": { group: "global", keys: [], desktop: ["Mod+,"], typing: "yes" },
  "shortcuts": { group: "global", keys: ["Mod+/"], typing: "yes" },
  "composer.focus": { group: "chat", keys: ["Space"], typing: "no" },
  "composer.file": { group: "chat", keys: ["Mod+U"], typing: "yes" },
  "chat.stop": { group: "chat", keys: ["Mod+."], typing: "yes" },
  "chat.history": { group: "chat", keys: ["Mod+Shift+H"], typing: "yes" },
  "chat.jobs": { group: "chat", keys: ["Mod+Shift+J"], typing: "yes" },
  // the station the chat runs on: its own display (else its first screen), beside it
  "chat.screen": { group: "chat", keys: ["Mod+Shift+D"], typing: "yes" },
  "chat.latest": { group: "chat", keys: ["Mod+Down"], typing: "empty" },
  "chat.find": { group: "chat", keys: ["Mod+F"], typing: "yes" },
  "chat.archive": { group: "chat", keys: ["Mod+Shift+E"], typing: "yes" },
  "panel.close": { group: "chat", keys: ["Escape"], typing: "yes" },
  // the preview beside a folder's list, shown or not (as Finder's preview pane)
  "files.preview": { group: "files", keys: ["Mod+Shift+P"], typing: "yes" },
};

const GROUPS = ["global", "chat", "files"] as const;

/// The modifiers in the order a binding has them. Mod is ⌘ on a Mac and Ctrl elsewhere; Ctrl is a key of its own only
/// on a Mac.
const MODS = ["Ctrl", "Alt", "Shift", "Mod"];
/// The keys with a name, beside a letter, a digit and F1…F99: where they are on the keyboard, so that ⌥ or ⇧ changing
/// the character typed does not change which binding it is.
const NAMED = ["Up", "Down", "Left", "Right", "Space", "Escape", "Enter", "\\", "[", "]", ".", ",", "/", ";"];
const SHOWN: Record<string, string> = { Up: "↑", Down: "↓", Left: "←", Right: "→", Escape: "Esc", Enter: "↩" };
const MARKS: Record<string, string> = { Ctrl: "⌃", Alt: "⌥", Shift: "⇧", Mod: "⌘" };

/// A binding as said ("Mod+Shift+H", the modifiers in any order) the way the core has it: each modifier once, in
/// MODS's order, then the key; null for what is none (a modifier twice or unknown, no key, a key with no name here).
export function binding(said: unknown): string | null {
  if (typeof said !== "string") return null;
  const parts = said.split("+");
  // "Mod++" would be a plus: none is bound, so the last part is always the key.
  const key = parts.pop()!;
  if (!(NAMED.includes(key) || /^[A-Z0-9]$/.test(key) || /^F\d{1,2}$/.test(key))) return null;
  if (parts.some((m, i) => !MODS.includes(m) || parts.indexOf(m) !== i)) return null;
  return [...MODS.filter((m) => parts.includes(m)), key].join("+");
}

/// A binding as a key cap shows it: ⌘⇧H on a Mac, Ctrl+Shift+H elsewhere.
export function label(b: string, mac: boolean): string {
  const parts = b.split("+");
  const key = parts.pop()!;
  const shown = key === "Space" ? t("web-main.keymap.space") : SHOWN[key] ?? key;
  if (mac) return MODS.filter((m) => parts.includes(m)).map((m) => MARKS[m]).join("") + shown;
  return [...["Mod", "Ctrl", "Alt", "Shift"].filter((m) => parts.includes(m)).map((m) => (m === "Mod" ? "Ctrl" : m)), shown].join("+");
}

/// What the keymap goes by of the prefs: whether this is the desktop app, keys said as on a Mac, the keys changed.
function facts(prefs: unknown): { desktop: boolean; mac: boolean; changed: Record<string, unknown> } {
  const device: Record<string, unknown> = isObject(prefs) && isObject(prefs.device) ? prefs.device : {};
  const desktop = device.app === "desktop";
  return { desktop, mac: device.mac === true, changed: desktop && isObject(prefs) && isObject(prefs.keys) ? prefs.keys : {} };
}

/// The keys that do an action here: changed on this device (the desktop app's), or its own (with the desktop app's).
function keysOf(action: string, f: ReturnType<typeof facts>): string[] {
  const changed = f.changed[action];
  if (Array.isArray(changed)) return [...new Set(changed.map(binding).filter((b): b is string => b !== null))];
  const spec = ACTIONS[action]!;
  return (f.desktop && spec.desktop ? [...spec.desktop, ...spec.keys] : spec.keys).map((b) => binding(b)!);
}

/// The keymap as the prefs say it (`keymap`, of the `prefs` topic).
export function view(prefs: unknown): unknown {
  const f = facts(prefs);
  const actions = Object.entries(ACTIONS).map(([action, spec]) => {
    const keys = keysOf(action, f);
    const labels = keys.map((b) => label(b, f.mac));
    return {
      action,
      group: spec.group,
      name: t(`web-main.keymap.${action}`),
      typing: spec.typing,
      keys,
      labels,
      text: labels.length ? labels.join(" / ") : t("web-main.shortcuts.unset"),
      changed: Array.isArray(f.changed[action]),
      listed: f.desktop || spec.keys.length > 0,
    };
  });
  return {
    changeable: f.desktop,
    mac: f.mac,
    groups: GROUPS.map((group) => ({ group, name: t(`web-main.keymap.group.${group}`) })),
    actions,
    // ⌃1…⌃9 on a Mac, Alt+1…9 elsewhere (Ctrl+digit is the browser's own tabs): not changeable.
    workspace: [1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => label(f.mac ? `Ctrl+${n}` : `Alt+${n}`, f.mac)),
  };
}

/// What `keys.set` puts in the prefs' `keys`: the action's keys (null: its own again), and each of them taken from any
/// other action that had it, said so. No action: every action's own again.
export function change(prefs: unknown, action: string | null, keys: string[] | null): { patch: Record<string, string[] | null> | null; moved: string[]; said: string | null } {
  if (action === null) return { patch: null, moved: [], said: null };
  const f = facts(prefs);
  const patch: Record<string, string[] | null> = { [action]: keys };
  const moved: string[] = [];
  let said: string | null = null;
  for (const b of keys ?? []) {
    for (const other of Object.keys(ACTIONS)) {
      if (other === action) continue;
      const had = patch[other] ?? keysOf(other, f);
      if (!had.includes(b)) continue;
      patch[other] = had.filter((k) => k !== b);
      if (!moved.includes(other)) moved.push(other);
      said ??= t("web-main.shortcuts.moved", { keys: label(b, f.mac), action: t(`web-main.keymap.${other}`) });
    }
  }
  return { patch, moved, said };
}
