import type { Layout } from "./core/shapes.ts";
import { setPrefs, usePrefs } from "./prefs.ts";

/**
 * How a computer's page is laid out: 侧边栏, the chats beside the chat; or 搜索列表, no sidebar, the chats a page of
 * their own (ChatsHome.tsx) with the search on top, each chat's bar leading back to it. Kept on this device (prefs.ts).
 */
export function useLayout(): [Layout, (value: Layout) => void] {
  return [usePrefs().layout ?? "sidebar", (layout) => setPrefs({ layout })];
}
