// The app's keyboard shortcuts, all in one place: what each does, and the keys that do it. A component that can do an
// action says so with useShortcut (the one mounted last answers); one listener on the window finds the action a key
// press is bound to. The keys can be changed in the desktop app (kept on this device by the core, prefs.ts): what shows a shortcut
// (a tooltip, the list of them) reads it from here too.
import { useEffect, useRef, useSyncExternalStore } from "react";
import { onPrefs, prefs, setPrefs } from "./prefs.ts";

export type Action =
  | "chat.switch" | "chat.new" | "chat.prev" | "chat.next" | "sidebar.toggle" | "nav.back" | "nav.forward" | "settings"
  | "composer.focus" | "composer.file" | "chat.stop" | "chat.history" | "chat.jobs" | "chat.latest" | "chat.archive" | "chat.rename"
  | "panel.close" | "shortcuts";

/**
 * A binding: modifiers, then a key, joined by "+" ("Mod+Shift+H"). Mod is ⌘ on a Mac and Ctrl elsewhere. The key is
 * where it is on the keyboard (a letter, a digit, Up/Down/Left/Right, Space, Escape, or one of \ [ ] . , / ;), so ⌥
 * or ⇧ changing the character typed does not change which binding it is.
 */
export type Binding = string;

interface Spec {
  label: string;
  group: "全局" | "对话";
  keys: Binding[];
  /** Only in the desktop app, where the browser takes no keys for itself. */
  desktop?: Binding[];
  /**
   * Whether it works with the cursor in a text field: always (a binding with ⌘ or ⌥ does nothing there), never (it is
   * a key the field types), or when the field is empty (the key moves the cursor in text).
   */
  typing: "yes" | "no" | "empty";
}

export const ACTIONS: Record<Action, Spec> = {
  "chat.switch": { label: "快速切换对话", group: "全局", keys: ["Mod+K"], typing: "yes" },
  "chat.new": { label: "新建对话", group: "全局", keys: ["Mod+Alt+N"], desktop: ["Mod+N"], typing: "yes" },
  "chat.prev": { label: "上一个对话", group: "全局", keys: ["Alt+Up"], typing: "yes" },
  "chat.next": { label: "下一个对话", group: "全局", keys: ["Alt+Down"], typing: "yes" },
  "sidebar.toggle": { label: "收起/展开侧边栏", group: "全局", keys: ["Mod+\\"], typing: "yes" },
  "nav.back": { label: "后退", group: "全局", keys: [], desktop: ["Mod+["], typing: "yes" },
  "nav.forward": { label: "前进", group: "全局", keys: [], desktop: ["Mod+]"], typing: "yes" },
  "settings": { label: "设置", group: "全局", keys: [], desktop: ["Mod+,"], typing: "yes" },
  "shortcuts": { label: "快捷键一览", group: "全局", keys: ["Mod+/"], typing: "yes" },
  "composer.focus": { label: "回到输入框", group: "对话", keys: ["Space"], typing: "no" },
  "composer.file": { label: "发送文件", group: "对话", keys: ["Mod+U"], typing: "yes" },
  "chat.stop": { label: "停止当前任务", group: "对话", keys: ["Mod+."], typing: "yes" },
  "chat.history": { label: "执行历史", group: "对话", keys: ["Mod+Shift+H"], typing: "yes" },
  "chat.jobs": { label: "服务和后台任务", group: "对话", keys: ["Mod+Shift+J"], typing: "yes" },
  "chat.latest": { label: "跳到最新", group: "对话", keys: ["Mod+Down"], typing: "empty" },
  "chat.archive": { label: "归档对话", group: "对话", keys: ["Mod+Shift+E"], typing: "yes" },
  "chat.rename": { label: "重命名对话", group: "对话", keys: ["F2"], typing: "yes" },
  "panel.close": { label: "收起侧栏", group: "对话", keys: ["Escape"], typing: "yes" },
};

const MAC = /Mac|iPhone|iPad/.test(navigator.platform);

/** Keys are changed only in the desktop app; the web pages keep the app's own. */
export const CHANGEABLE = !!window.stillfailDesktop;

function overrides(): Partial<Record<Action, Binding[]>> {
  return CHANGEABLE ? prefs().keys as Partial<Record<Action, Binding[]>> : {};
}

/** The keys that do an action here: changed on this device, or its own (with the desktop app's). */
export function keysOf(action: Action): Binding[] {
  const changed = overrides()[action];
  if (changed) return changed;
  const spec = ACTIONS[action];
  return window.stillfailDesktop && spec.desktop ? [...spec.desktop, ...spec.keys] : spec.keys;
}

/** Changes an action's keys on this device; null goes back to its own. */
export function setKeys(action: Action, keys: Binding[] | null): void {
  setPrefs({ keys: { [action]: keys } });
}

/** Whether an action's keys were changed on this device. */
export function changed(action: Action): boolean {
  return overrides()[action] !== undefined;
}

/** The keys changed as last read: another object whenever they change. */
const changedKeys = () => (CHANGEABLE ? prefs().keys : null);

/** Redrawn when any action's keys change: what shows them reads them anew. */
export function useKeymap(): unknown {
  return useSyncExternalStore(onPrefs, changedKeys, () => null);
}

/** The action other than `except` a binding already does, if any. */
export function boundTo(binding: Binding, except: Action): Action | null {
  return (Object.keys(ACTIONS) as Action[]).find((a) => a !== except && keysOf(a).includes(binding)) ?? null;
}

const CODES: Record<string, string> = {
  Up: "ArrowUp", Down: "ArrowDown", Left: "ArrowLeft", Right: "ArrowRight", Space: "Space", Escape: "Escape", Enter: "Enter",
  "\\": "Backslash", "[": "BracketLeft", "]": "BracketRight", ".": "Period", ",": "Comma", "/": "Slash", ";": "Semicolon",
};
const KEYS = Object.fromEntries(Object.entries(CODES).map(([key, code]) => [code, key]));

/** The binding a key press makes (Mod+Shift+H), or null for a key that is none (a modifier alone, a key with no name here). */
export function bindingOf(e: KeyboardEvent): Binding | null {
  const key = KEYS[e.code] ?? (/^Key[A-Z]$/.test(e.code) ? e.code.slice(3) : /^Digit\d$/.test(e.code) ? e.code.slice(5) : /^F\d{1,2}$/.test(e.code) ? e.code : null);
  if (!key) return null;
  const mods = [MAC && e.ctrlKey && "Ctrl", e.altKey && "Alt", e.shiftKey && "Shift", (MAC ? e.metaKey : e.ctrlKey) && "Mod"].filter(Boolean);
  return [...mods, key].join("+");
}

const SHOWN: Record<string, string> = { Up: "↑", Down: "↓", Left: "←", Right: "→", Space: "空格", Escape: "Esc", Enter: "↩" };

interface Parsed { mod: boolean; shift: boolean; alt: boolean; ctrl: boolean; code: string }

function parse(binding: Binding): Parsed {
  const parts = binding.split("+");
  // "Mod++" would be a plus; none is bound, so the last part is always the key.
  const key = parts.pop()!;
  const code = CODES[key] ?? (/^[A-Z]$/.test(key) ? `Key${key}` : /^\d$/.test(key) ? `Digit${key}` : key);
  return { mod: parts.includes("Mod"), shift: parts.includes("Shift"), alt: parts.includes("Alt"), ctrl: parts.includes("Ctrl"), code };
}

function matches(binding: Binding, e: KeyboardEvent): boolean {
  const b = parse(binding);
  const mod = MAC ? e.metaKey : e.ctrlKey;
  // On a Mac, Ctrl is a key of its own; elsewhere it is Mod, and ⌘ (the Windows key) is never part of a binding.
  const ctrl = MAC ? e.ctrlKey : false;
  const meta = MAC ? false : e.metaKey;
  return e.code === b.code && mod === b.mod && e.shiftKey === b.shift && e.altKey === b.alt && ctrl === b.ctrl && !meta;
}

/** A binding as a key cap shows it: ⌘⇧H on a Mac, Ctrl+Shift+H elsewhere. */
export function keyLabel(binding: Binding): string {
  const parts = binding.split("+");
  const key = parts.pop()!;
  const shown = SHOWN[key] ?? key;
  if (MAC) {
    const marks = { Ctrl: "⌃", Alt: "⌥", Shift: "⇧", Mod: "⌘" } as const;
    return (["Ctrl", "Alt", "Shift", "Mod"] as const).filter((m) => parts.includes(m)).map((m) => marks[m]).join("") + shown;
  }
  return [...parts.map((m) => (m === "Mod" ? "Ctrl" : m)), shown].join("+");
}

/** An action's first key as shown, or null when it has none here. */
export function shortcutOf(action: Action): string | null {
  const first = keysOf(action)[0];
  return first ? keyLabel(first) : null;
}

type Handler = (e: KeyboardEvent) => unknown;
const handlers = new Map<Action, Handler[]>();

const TYPED = "input:not([type=checkbox]):not([type=radio]):not([type=button]):not([type=submit]), textarea, select, [contenteditable]:not([contenteditable='false'])";
const PRESSED = "button, a[href], summary, input, [role='button'], [role='link'], [role='menuitem'], [role='tab'], [role='option'], [role='checkbox'], [role='radio'], [role='switch'], [role='slider']";
/** Open over the page, taking the keys: a dialog (a file's preview), a menu, a popover. */
/** Whether a focused element keeps keys with no modifier (Space) for itself: a text field, a button… */
export function takesKeys(el: Element | null): boolean {
  return !!el?.closest(`${TYPED}, ${PRESSED}`);
}
const OVER = "[role='dialog'], [role='alertdialog'], [role='menu'], [role='listbox']";

function onKey(e: KeyboardEvent) {
  if (e.defaultPrevented || e.isComposing) return;
  const at = e.target instanceof Element ? e.target : null;
  const field = at?.closest<HTMLInputElement | HTMLTextAreaElement>(TYPED) ?? null;
  for (const [action, stack] of handlers) {
    const handler = stack.at(-1);
    if (!handler || !keysOf(action).some((k) => matches(k, e))) continue;
    const spec = ACTIONS[action];
    if (field && (spec.typing === "no" || spec.typing === "empty" && "value" in field && field.value !== "")) continue;
    // A key that types something, bound on its own (changed to one here), is never taken from a text field.
    if (field && !e.metaKey && !e.ctrlKey && !e.altKey && (e.key.length === 1)) continue;
    // A key with no modifier is the focused control's own (Space presses a button).
    if (!e.metaKey && !e.ctrlKey && !e.altKey && at?.closest(PRESSED) && !field) continue;
    if (document.querySelector(OVER)) continue;
    if (handler(e) === false) continue;
    e.preventDefault();
    return;
  }
}

let listening = false;

/**
 * What an action does while this component is mounted (the latest mounted wins over one before it); null while it
 * cannot. The handler returns false to leave the key to the page, as if it were not bound.
 */
export function useShortcut(action: Action, handler: Handler | null): void {
  const latest = useRef(handler);
  latest.current = handler;
  const on = handler !== null;
  useEffect(() => {
    if (!on) return;
    if (!listening) { window.addEventListener("keydown", onKey); listening = true; }
    const entry: Handler = (e) => latest.current?.(e);
    const stack = handlers.get(action) ?? [];
    handlers.set(action, [...stack, entry]);
    return () => { handlers.set(action, (handlers.get(action) ?? []).filter((h) => h !== entry)); };
  }, [action, on]);
}
