// The keys that do what a control does, said in its tip after its words (parts.tsx Tip's `shortcut`). The page names its
// actions (declaring them in `Shortcuts`) and says their keys (setShortcuts); with none, a tip names no keys.
export interface Shortcuts {}

export type Shortcut = keyof Shortcuts;

let keysOf: (action: Shortcut) => string | null = () => null;
let follow: () => unknown = () => undefined;

/** `keys`: an action's keys as said (null: none); `use`: a hook that redraws when they change. Once, as the page starts. */
export function setShortcuts(given: { keys(action: Shortcut): string | null; use(): unknown }): void {
  keysOf = given.keys;
  follow = given.use;
}

export function shortcutKeys(action: Shortcut): string | null {
  return keysOf(action);
}

/** Redraws when the keys change. */
export function useShortcuts(): unknown {
  return follow();
}
