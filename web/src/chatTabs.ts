// Which side-panel tabs each chat has open, and which one is in front: the core's (client/core-ts/src/chat-tabs.ts).
// Each chat keeps its own on this device (prefs `chatTabs`, the latest 200 chats'), by `station:session` (or
// `station:thread`) as its page names it, `new:<workspace>` a workspace's new chat's; a chat's view says which of them
// are open and in front (`tabs`). These ask the core to change them.
import { core } from "./core/react.ts";

/**
 * Changes `chat`'s tabs: `tab` opened (in front), closed (the one in front, if it was, the last left) or brought to the
 * front, or all closed (`clear`). `auto: false` where the panel would lie over the chat: it goes from none of those the
 * chat opens by itself (its view's `tabs.auto`), as it shows none of them.
 */
export function changeTabs(chat: string, action: "open" | "close" | "front" | "clear", tab?: string, auto = true): void {
  core().call(`chat.tabs.${action}`, { chat, ...(tab !== undefined ? { tab } : {}), ...(auto ? {} : { auto: false }) }).catch(() => undefined);
}
