// The app's keyboard shortcuts: what each does and the keys that do it are the core's (the prefs' `keymap`;
// client/core-ts/src/keymap.ts). A component that can do an action says so with useShortcut (the one mounted last
// answers); one listener on the window turns a key press into a binding and finds the action it is bound to. What shows a shortcut (a tooltip, the list of them) reads it from here.
import { useEffect, useRef, useSyncExternalStore } from "react";
import type { KeyAction, KeyActionName, KeymapView } from "./core/shapes.ts";
import { prefs, usePrefs } from "./prefs.ts";

export type Action = KeyActionName;

// The actions a tip of @stillfail/ui names the keys of (its Tip's `shortcut`): these (ui.tsx says their keys).
declare module "@stillfail/ui/shortcuts.ts" {
  interface Shortcuts extends Record<Action, true> {}
}

/** A binding as the core has it (keymap.ts): modifiers Ctrl, Alt, Shift, Mod in that order, then the key ("Shift+Mod+H"). */
export type Binding = string;

/** None until the core has said it (the first start, before it answers). */
const NONE: KeymapView = { changeable: false, mac: false, groups: [], actions: [], workspace: [] };

let made: [KeymapView, Map<Action, KeyAction>] | null = null;

/** The keymap now, its actions by name. */
function keymap(): [KeymapView, Map<Action, KeyAction>] {
  const view = prefs().keymap ?? NONE;
  if (made?.[0] !== view) made = [view, new Map(view.actions.map((a) => [a.action, a]))];
  return made;
}

/** The actions, in the order the list of shortcuts has them. */
export function actions(): KeyAction[] {
  return keymap()[0].actions;
}

/** The groups the actions are in, with their names, in order. */
export function groups(): KeymapView["groups"] {
  return keymap()[0].groups;
}

/** An action as the core says it, or undefined before it has. */
export function actionOf(action: Action): KeyAction | undefined {
  return keymap()[1].get(action);
}

/** What an action does, in words. */
export function labelOf(action: Action): string {
  return actionOf(action)?.name ?? "";
}

const MAC = /Mac|iPhone|iPad/.test(navigator.platform);

/** The keys that do an action here. */
export function keysOf(action: Action): Binding[] {
  return actionOf(action)?.keys ?? [];
}

/** Redrawn when the keymap changes: what shows the keys reads them anew. */
export function useKeymap(): unknown {
  return usePrefs((p) => p.keymap);
}

const CODES: Record<string, string> = {
  Up: "ArrowUp", Down: "ArrowDown", Left: "ArrowLeft", Right: "ArrowRight", Space: "Space", Escape: "Escape", Enter: "Enter",
  "\\": "Backslash", "[": "BracketLeft", "]": "BracketRight", ".": "Period", ",": "Comma", "/": "Slash", ";": "Semicolon",
};
const KEYS = Object.fromEntries(Object.entries(CODES).map(([key, code]) => [code, key]));

/**
 * The binding a key press makes (Shift+Mod+H), or null for a key that is none (a modifier alone, a key with no name
 * here). The key is where it is on the keyboard, so ⌥ or ⇧ changing the character typed does not change which it is.
 */
export function bindingOf(e: KeyboardEvent): Binding | null {
  const key = KEYS[e.code] ?? (/^Key[A-Z]$/.test(e.code) ? e.code.slice(3) : /^Digit\d$/.test(e.code) ? e.code.slice(5) : /^F\d{1,2}$/.test(e.code) ? e.code : null);
  if (!key) return null;
  const mods = [MAC && e.ctrlKey && "Ctrl", e.altKey && "Alt", e.shiftKey && "Shift", (MAC ? e.metaKey : e.ctrlKey) && "Mod"].filter(Boolean);
  return [...mods, key].join("+");
}

/** The binding a key press is bound by: elsewhere than on a Mac, ⌘ (the Windows key) is never part of one. */
function pressed(e: KeyboardEvent): Binding | null {
  return !MAC && e.metaKey ? null : bindingOf(e);
}

/**
 * Switching workspace by its place in the sidebar's menu: ⌃1…⌃9 on a Mac, Alt+1…9 elsewhere (Ctrl+digit is the
 * browser's own tabs). Not changeable: nine actions would be nine rows of one thing.
 */
export function workspaceIndexOf(e: KeyboardEvent): number | null {
  if (e.isComposing || e.shiftKey || e.metaKey || (MAC ? !e.ctrlKey || e.altKey : !e.altKey || e.ctrlKey)) return null;
  const digit = /^Digit([1-9])$/.exec(e.code);
  return digit ? Number(digit[1]) - 1 : null;
}

/** The key that switches to the workspace at this place (from 0) in the menu. */
export function workspaceKeyLabel(index: number): string {
  return keymap()[0].workspace[index] ?? "";
}

/** An action's first key as shown, or null when it has none here. */
export function shortcutOf(action: Action): string | null {
  return actionOf(action)?.labels[0] ?? null;
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

function hasShortcutOverlay(): boolean {
  return !!document.querySelector(OVER);
}

function pageKeysAvailable(): boolean {
  return !takesKeys(document.activeElement) && !hasShortcutOverlay();
}

function watchPageKeys(changed: () => void): () => void {
  document.addEventListener("focusin", changed);
  document.addEventListener("focusout", changed);
  // Portalled menus can open/close without a focus change. Ignore ordinary message mutations.
  const hasOverlay = (node: Node) => node instanceof Element && (node.matches(OVER) || !!node.querySelector(OVER));
  const observer = new MutationObserver((records) => {
    if (records.some((r) => r.type === "attributes" || [...r.addedNodes, ...r.removedNodes].some(hasOverlay))) changed();
  });
  observer.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["role"] });
  return () => {
    document.removeEventListener("focusin", changed);
    document.removeEventListener("focusout", changed);
    observer.disconnect();
  };
}

/** Whether an unmodified page shortcut can take focus, including portalled overlays. */
export function usePageKeysAvailable(): boolean {
  return useSyncExternalStore(watchPageKeys, pageKeysAvailable, () => false);
}


function onKey(e: KeyboardEvent) {
  if (e.defaultPrevented || e.isComposing) return;
  const at = e.target instanceof Element ? e.target : null;
  const field = at?.closest<HTMLInputElement | HTMLTextAreaElement>(TYPED) ?? null;
  const binding = pressed(e);
  if (!binding) return;
  for (const [action, stack] of handlers) {
    const handler = stack.at(-1);
    const spec = actionOf(action);
    if (!handler || !spec?.keys.includes(binding)) continue;
    if (field && (spec.typing === "no" || spec.typing === "empty" && "value" in field && field.value !== "")) continue;
    // A key that types something, bound on its own (changed to one here), is never taken from a text field.
    if (field && !e.metaKey && !e.ctrlKey && !e.altKey && (e.key.length === 1)) continue;
    // A key with no modifier is the focused control's own (Space presses a button).
    if (!e.metaKey && !e.ctrlKey && !e.altKey && at?.closest(PRESSED) && !field) continue;
    if (hasShortcutOverlay()) continue;
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
    return () => {
      handlers.set(action, (handlers.get(action) ?? []).filter((h) => h !== entry));
    };
  }, [action, on]);
}

/** The actions that can be done now (some mounted component does each), in the order the core lists them. */
export function availableActions(): Action[] {
  return actions().map((a) => a.action).filter((a) => handlers.get(a)?.length);
}

/** Does an action as its key would (⌘K's list). */
export function runAction(action: Action): void {
  void handlers.get(action)?.at(-1)?.(new KeyboardEvent("keydown"));
}
