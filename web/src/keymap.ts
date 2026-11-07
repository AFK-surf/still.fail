// Shortcut labels for the remaining web pages, from the core's keymap.
import type { KeyAction, KeyActionName, KeymapView } from "./core/shapes.ts";
import { prefs, usePrefs } from "./prefs.ts";

export type Action = KeyActionName;

// The actions a tip of @stillfail/ui names the keys of (its Tip's `shortcut`): these (ui.tsx says their keys).
declare module "@stillfail/ui/shortcuts.ts" {
  interface Shortcuts extends Record<Action, true> {}
}

/** None until the core has said it (the first start, before it answers). */
const NONE: KeymapView = { changeable: false, mac: false, groups: [], actions: [], workspace: [] };

let made: [KeymapView, Map<Action, KeyAction>] | null = null;

/** The keymap now, its actions by name. */
function keymap(): [KeymapView, Map<Action, KeyAction>] {
  const view = prefs().keymap ?? NONE;
  if (made?.[0] !== view) made = [view, new Map(view.actions.map((a) => [a.action, a]))];
  return made;
}

/** An action as the core says it, or undefined before it has. */
function actionOf(action: Action): KeyAction | undefined {
  return keymap()[1].get(action);
}

/** Redrawn when the keymap changes: what shows the keys reads them anew. */
export function useKeymap(): unknown {
  return usePrefs((p) => p.keymap);
}

/** An action's first key as shown, or null when it has none here. */
export function shortcutOf(action: Action): string | null {
  return actionOf(action)?.labels[0] ?? null;
}
