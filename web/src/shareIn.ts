// What another app shares into still.fail (docs/share-in.md): a link from a browser or a video app, some text. The page's
// /share (the installed page's share target, and what the browser extension opens: cloud/CloudApp.tsx ShareLanding)
// takes what it was given and goes to the workspace's page, where the sheet (phone: mobile/ShareIn.tsx) or the panel
// (wide: ShareIn.tsx) shows where it goes: the core's `shareIn` view, picked with `shareIn.pick`, sent with `shareIn.send`.
// Here is only what is being shared while it waits to be sent, and the calls; where it goes is the core's.
import { useRef, useSyncExternalStore } from "react";
import { core, useTopic } from "./core/react.ts";
import type { ShareInPick, ShareInView } from "./core/shapes.ts";
import { stationBase } from "./station.tsx";

/**
 * What is being shared: `source` what the core is given as shared (the link, or the text, or the text with the link
 * after it when they are apart), `title` what the app gave as its subject. `popup`: in a window of its own that the
 * extension opened, which closes once it is sent. `note`: what was added to it before (a send that failed comes back).
 */
export interface Shared { source: string; title: string | null; popup: boolean; note?: string }

/** What /share was given (`?url=&title=&text=&popup=1`): null when nothing. */
export function sharedOf(search: string): Shared | null {
  const q = new URLSearchParams(search);
  const field = (name: string) => q.get(name)?.trim() || null;
  const url = field("url"), text = field("text"), title = field("title");
  // A selection, or what an app says with its link (Android's text often has the link in it already): the link after it.
  const source = url ? (text && !text.includes(url) ? `${text}\n${url}` : text ?? url) : text;
  if (!source) return null;
  return { source, title: title && title !== source ? title : null, popup: q.get("popup") === "1" };
}

let shared: Shared | null = null;
const heard = new Set<() => void>();

/** What is shared now waits to be sent: the workspace's page shows where it goes. Null: nothing waits (it was sent, or let go). */
export function offerShare(next: Shared | null): void {
  shared = next;
  for (const h of heard) h();
}

/** What waits to be sent, as it changes. */
export function useShared(): Shared | null {
  return useSyncExternalStore((h) => { heard.add(h); return () => { heard.delete(h); }; }, () => shared, () => null);
}

/** Let go of without sending: a window the extension opened goes with it. */
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

/** Whether `picked` is the row (`id` on `station`), or with no `id` a new chat on `station`. */
export function isPicked(picked: ShareInPick | undefined, station: string, id?: string): boolean {
  return !!picked && picked.station === station && picked.id === id;
}

/** Picks where it goes: a chat by its row's `id`, or a new chat on `station`. */
export function pickShare(scope: string, s: Shared, station: string, id?: string): Promise<unknown> {
  return core().call("shareIn.pick", { scope, source: s.source, station, ...(id ? { id } : {}) });
}

/** Where it went, as the core answers once it is in that chat's outbox. */
export interface ShareSent { station: string; session: string; thread?: number; title: string }

/** Sends it, with what was added (`note`), to where it was picked to go. */
export function sendShare(scope: string, s: Shared, note: string): Promise<ShareSent> {
  const text = note.trim();
  return core().call("shareIn.send", { scope, source: s.source, ...(s.title ? { title: s.title } : {}), ...(text ? { text } : {}) }) as Promise<ShareSent>;
}

/** The chat it went to: by the row picked (its `id`), or the new chat by the key it was made under. */
export function sentPath(sent: ShareSent, picked: ShareInPick | undefined): string {
  const id = picked?.station === sent.station && picked.id ? picked.id : sent.session;
  return `${stationBase(sent.station)}/chats/${encodeURIComponent(id)}`;
}

/** How long a window the extension opened stays once sent, its note seen (and 打开 there to tap) before it closes. */
export const POPUP_STAYS_MS = 1800;

/** The chat it went to, from a window the extension opened: in a tab of the browser, the window closing. */
export function openFromPopup(path: string): void {
  window.open(new URL(path, location.origin).href, "_blank");
  window.close();
}
