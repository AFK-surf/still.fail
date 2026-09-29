// Which history tabs each chat has open, and which one is in front: each chat keeps its own (the latest 200 chats),
// by `station:session` (or `station:thread`), as its page names it.

const TABS = "stillfail.chatTabs";
export type Kept = { tabs: string[]; active: string | null };

export function keptTabs(chat: string): Kept | undefined {
  try {
    return (JSON.parse(localStorage.getItem(TABS) ?? "{}") as Record<string, Kept>)[chat];
  } catch {
    return undefined;
  }
}

export function keepTabs(chat: string, kept: Kept): void {
  let all: Record<string, Kept> = {};
  try {
    all = JSON.parse(localStorage.getItem(TABS) ?? "{}") as Record<string, Kept>;
  } catch {
    // start over
  }
  delete all[chat];
  all[chat] = kept;
  const keys = Object.keys(all);
  for (const key of keys.slice(0, Math.max(0, keys.length - 200))) delete all[key];
  localStorage.setItem(TABS, JSON.stringify(all));
}
