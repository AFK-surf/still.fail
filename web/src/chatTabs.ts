// Which history tabs each chat has open, and which one is in front: each chat keeps its own (the core keeps the latest
// 200 chats'), by `station:session` (or `station:thread`), as its page names it. Kept on this device (prefs.ts).
import { prefs, setPrefs } from "./prefs.ts";

export type Kept = { tabs: string[]; active: string | null };

export function keepTabs(chat: string, kept: Kept): void {
  setPrefs({ chatTabs: { [chat]: { tabs: kept.tabs, ...(kept.active ? { active: kept.active } : {}) } } });
}

/** Closes the tab `tab` of `chat`'s, while its page is not in view (the one in front, if it was, the last left). */
export function dropTab(chat: string, tab: string): void {
  const now = prefs().chatTabs[chat];
  if (!now?.tabs.includes(tab)) return;
  const tabs = now.tabs.filter((k) => k !== tab);
  keepTabs(chat, { tabs, active: now.active === tab ? tabs.at(-1) ?? null : now.active ?? null });
}
