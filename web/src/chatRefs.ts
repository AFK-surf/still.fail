// References to other chats in what is written (ChatRef.tsx): in the composer a short mark, `@[its title]`, drawn as a
// chip; sent, a link, `[its title](its page)`, which the agent reads the chat by and a message draws as the same chip.
// The core makes the mark of a chat picked and keeps its link until it is sent (`chat.ref`, client/core-ts/src/refs.ts);
// what a link names, and the link a chat is given away by, are its too (client/core-ts/src/refLinks.ts). Here: this
// page's origins, and the clipboard.
import * as refLinks from "../../client/core-ts/src/refLinks.ts";

export { adbOfLink, chatOfLink, isChatLink, REF_LINK, REF_MARK, screenOfLink, splitBy, stationOfLink } from "../../client/core-ts/src/refLinks.ts";

/**
 * The link a chat is given away by (copied from its row's menu; refLinks.ts shareLink): still.fail's, under still.fail
 * cloud's origin (the desktop app's, else this page's), or, a station of no workspace, its page here (`root`, where
 * this page's routes start); `history`: an agent's execution history there, opened at `entry`.
 */
export function shareLink(item: { station: string; session: string; id: string }, root: string, history?: { key: string; entry?: number | undefined }): string {
  const here = /^https?:$/.test(location.protocol) ? location.origin : null;
  const cloud = window.stillfailDesktop?.cloudOrigin || here;
  return refLinks.shareLink(item, { cloud, here, root }, history);
}

/**
 * Puts a link to a chat on the clipboard: as a reference is sent, `[its title](link)`, for plain text (a composer,
 * where it becomes a reference again, or a terminal), and as a link for what takes HTML (Slack, documents).
 */
export function copyChatLink(title: string, link: string): Promise<void> {
  const { shown, plain } = refLinks.copiedRef(title, link);
  if (typeof ClipboardItem === "undefined" || !navigator.clipboard.write) return navigator.clipboard.writeText(plain);
  const escape = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
  const html = `<a href="${escape(link)}">${escape(shown)}</a>`;
  return navigator.clipboard.write([new ClipboardItem({ "text/plain": new Blob([plain], { type: "text/plain" }), "text/html": new Blob([html], { type: "text/html" }) })]);
}
