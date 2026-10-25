// What another app shares into still.fail (docs/share-in.md): a link from a browser or a video app, some text. The page's
// /share (the installed page's share target, and what the browser extension opens: cloud/CloudApp.tsx ShareLanding)
// takes what it was given and goes to the workspace's page, where the sheet (phone: mobile/ShareIn.tsx) or the panel
// (wide: ShareIn.tsx) lists where it can go: the core's `shareIn` view. A tap has the core put it in that chat's
// composer (`shareIn.open`) and opens the chat, where the person adds to it and sends it: the sheet has no field of its
// own (one composer, not two). Here is only what is shared while the sheet is up, and the call.
import { useRef, useSyncExternalStore } from "react";
import { core, useTopic } from "./core/react.ts";
import type { ShareInView } from "./core/shapes.ts";
import { stationBase } from "./station.tsx";

/**
 * What is being shared: `source` what the core is given as shared (the link, or the text, or the text with the link
 * after it when they are apart), `title` what the app gave as its subject. `popup`: in a window of its own that the
 * extension opened, which closes once a chat is picked; `ext`, that extension's id, to ask it to open the chat in the
 * browser's still.fail tab.
 */
export interface Shared { source: string; title: string | null; popup: boolean; ext?: string | undefined }

/** What /share was given (`?url=&title=&text=&popup=1&ext=`): null when nothing. */
export function sharedOf(search: string): Shared | null {
  const q = new URLSearchParams(search);
  const field = (name: string) => q.get(name)?.trim() || null;
  const url = field("url"), text = field("text"), title = field("title");
  // A selection, or what an app says with its link (Android's text often has the link in it already): the link after it.
  const source = url ? (text && !text.includes(url) ? `${text}\n${url}` : text ?? url) : text;
  if (!source) return null;
  const ext = field("ext");
  return { source, title: title && title !== source ? title : null, popup: q.get("popup") === "1", ...(ext ? { ext } : {}) };
}

let shared: Shared | null = null;
const heard = new Set<() => void>();

/** What is shared now waits for a chat to go to: the workspace's page shows the sheet. Null: nothing waits. */
export function offerShare(next: Shared | null): void {
  shared = next;
  for (const h of heard) h();
}

/** What waits for a chat to go to, as it changes. */
export function useShared(): Shared | null {
  return useSyncExternalStore((h) => { heard.add(h); return () => { heard.delete(h); }; }, () => shared, () => null);
}

/** Let go of without opening a chat: a window the extension opened goes with it. */
export function dismissShare(s: Shared): void {
  if (shared === s) offerShare(null);
  if (s.popup) window.close();
}

/**
 * Where it can go, the core's (`shareIn`): the chats `query` finds when one is typed. While the view for what was just
 * typed is on its way, the one before stays (the list does not blank between letters).
 */
export function useShareIn(scope: string, s: Shared, query = ""): ShareInView | undefined {
  const q = query.trim();
  const value = useTopic<ShareInView>({ topic: "shareIn", scope, source: s.source, ...(q ? { query: q } : {}) }).value;
  const last = useRef(value);
  if (value !== undefined) last.current = value;
  return value ?? last.current;
}

/** From how many chats the sheet offers to search them (as the Android app's does). */
export const SEARCH_FROM = 6;

/** The chat it is put in, as the core answers: by the session its page goes by; none, a new chat on `station`. */
interface Opened { station: string; key: string; session?: string; thread?: number; title?: string }

/**
 * Puts it in the composer of the chat by its row's `id`, or with no `id` of a new chat on `station` (`shareIn.open`):
 * answers the page to open, the chat's at the session its composer is kept by, or the workspace's new chat. `newKey`:
 * the key the new chat's composer is kept by on the page that opens it, when not the core's `new:<workspace>` (the
 * phone's, before its chat is made: draft.ts NO_KEY).
 */
export async function openShare(scope: string, s: Shared, station: string, id?: string, newKey?: string): Promise<string> {
  const opened = await core().call("shareIn.open", { scope, source: s.source, station, ...(id ? { id } : {}), ...(s.title ? { title: s.title } : {}), ...(!id && newKey ? { key: newKey } : {}) }) as Opened;
  return opened.session ? `${stationBase(opened.station)}/chats/${encodeURIComponent(opened.session)}` : `/w/${scope}/new`;
}

/** How long a window the extension opened stays after the chat's tab is asked for, what it put in the chat kept on the device by then. */
const POPUP_STAYS_MS = 1500;

type ExtensionRuntime = { sendMessage(id: string, message: unknown, answer: (reply: unknown) => void): void; lastError?: unknown };

/**
 * From a window the extension opened: the chat in the browser's still.fail tab, which the extension finds (or opens)
 * and goes to, closing this window (apps/extension/background.js). With no extension to ask (or one that cannot), in a
 * new tab, this window closing after.
 */
export function openFromPopup(s: Shared, path: string): void {
  const url = new URL(path, location.origin).href;
  const alone = () => { window.open(url, "_blank"); setTimeout(() => window.close(), POPUP_STAYS_MS); };
  const runtime = (globalThis as { chrome?: { runtime?: ExtensionRuntime } }).chrome?.runtime;
  if (!s.ext || !runtime?.sendMessage) return alone();
  try {
    runtime.sendMessage(s.ext, { open: url }, (reply) => {
      if (runtime.lastError || (reply as { ok?: boolean } | undefined)?.ok !== true) alone();
    });
  } catch {
    alone();
  }
}
