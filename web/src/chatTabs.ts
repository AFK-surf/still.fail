// Which history tabs each chat has open, and which one is in front: each chat keeps its own (the core keeps the latest
// 200 chats'), by `station:session` (or `station:thread`), as its page names it. Kept on this device (prefs.ts).
import type { KeptTabs } from "./core/shapes.ts";
import { prefs, setPrefs } from "./prefs.ts";

export type Kept = { tabs: string[]; active: string | null };

export function keptTabs(chat: string): Kept | undefined {
  const kept: KeptTabs | undefined = prefs().chatTabs[chat];
  return kept && { tabs: kept.tabs, active: kept.active ?? null };
}

export function keepTabs(chat: string, kept: Kept): void {
  setPrefs({ chatTabs: { [chat]: { tabs: kept.tabs, ...(kept.active ? { active: kept.active } : {}) } } });
}
