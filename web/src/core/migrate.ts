// Before the core, the page kept the signed-in accounts (cloud/accounts.ts)
// and this browser's device key (cloud/link.ts) in localStorage, which the
// core's worker cannot read. The first page to start the core hands them over
// once; the core keeps them in IndexedDB from then on.
import type { CoreClient } from "./client.ts";
import type { KeptTabs, PrefsView } from "./shapes.ts";

const ACCOUNTS = "stillfail.accounts";
const DEVICE = "stillfail.device";
const DONE = "stillfail.core.migrated";

export async function migrateLegacy(client: Pick<CoreClient, "call">, storage: Storage = localStorage): Promise<void> {
  if (storage.getItem(DONE)) return;
  const stored = storage.getItem(ACCOUNTS);
  const device = storage.getItem(DEVICE);
  if (stored === null && device === null) return;
  let accounts: unknown = [];
  try {
    accounts = JSON.parse(stored ?? "[]");
  } catch { /* unreadable: nothing to carry over */ }
  try {
    // `device` is the base64 of the 32-byte secret key, as link.ts stored it.
    await client.call("migrate", device === null ? { accounts } : { accounts, device });
    storage.setItem(DONE, String(Date.now()));
  } catch (error) {
    // Tried again on the next start; the old values stay where they are.
    console.error("still.fail core: migrating localStorage failed", error);
  }
}

/** The links of the chats referred to in drafts (chatRefs.ts kept them here before the core did), handed over once. */
const CHAT_REFS = "stillfail.chatRefs";

export async function migrateChatRefs(client: Pick<CoreClient, "call">, storage: Storage = localStorage): Promise<void> {
  const stored = storage.getItem(CHAT_REFS);
  if (stored === null) return;
  let links: [string, string][] = [];
  try {
    links = Object.entries(JSON.parse(stored) as Record<string, unknown>).flatMap(([title, link]) => (typeof link === "string" ? [[title, link] as [string, string]] : []));
  } catch { /* unreadable: nothing to carry over */ }
  try {
    await client.call("chat.refs", { links });
    storage.removeItem(CHAT_REFS);
  } catch {
    // A core from before it: kept here until one takes them.
  }
}

const NEW_CHAT = "stillfail.newChat";

/**
 * What a new chat ran on, per station (its id), and the station per scope, as pages kept them in localStorage before
 * the core kept them (`newChat.migrate`): handed over once, then gone from here.
 */
export async function migrateNewChat(client: Pick<CoreClient, "call">, storage: Storage = localStorage): Promise<void> {
  const stored = storage.getItem(NEW_CHAT);
  if (stored === null) return;
  let kept: Record<string, unknown> = {};
  try {
    kept = JSON.parse(stored) as Record<string, unknown>;
  } catch { /* unreadable: nothing to carry over */ }
  const { last, lastIn, ...choices } = kept;
  try {
    await client.call("newChat.migrate", { choices, ...(typeof last === "string" ? { last } : {}), ...(lastIn && typeof lastIn === "object" ? { lastIn } : {}) });
    storage.removeItem(NEW_CHAT);
  } catch (error) {
    // A core from before it: kept here, handed over by the next page.
    console.error("still.fail core: migrating the new chat's choices failed", error);
  }
}

const PREFS_DONE = "stillfail.prefs.migrated";

/**
 * The prefs the page kept itself before the core did (the lists' filter, the appearance, keys changed, the chat last
 * open, tabs…), into the core once: only what it has not been told on this device yet. The old
 * keys stay (a tab of an older build may still read them).
 */
export async function migratePrefs(client: Pick<CoreClient, "call">, storage: Storage = localStorage): Promise<void> {
  try {
    if (storage.getItem(PREFS_DONE)) return;
    const kept = legacyPrefs(storage);
    if (Object.keys(kept).length) await client.call("prefs.set", { ...kept, fill: true });
    storage.setItem(PREFS_DONE, String(Date.now()));
  } catch (error) {
    // Tried again on the next start (a core from before prefs refuses it); the old values stay where they are.
    console.error("still.fail core: moving prefs in failed", error);
  }
}

/** What the page kept itself before the core did (../prefs.ts), as the core keeps it. */
export function legacyPrefs(from: Storage): Partial<PrefsView> {
  const json = <T>(key: string): T | undefined => {
    try { const raw = from.getItem(key); return raw === null ? undefined : JSON.parse(raw) as T; } catch { return undefined; }
  };
  const out: Partial<PrefsView> = {};
  const onlyMine = from.getItem("stillfail.onlyMine");
  if (onlyMine !== null) out.onlyMine = onlyMine === "1";
  const appearance = from.getItem("stillfail.appearance");
  if (appearance === "light" || appearance === "dark") out.appearance = appearance;
  const picture = from.getItem("stillfail.rowPicture");
  if (picture === "agents" || picture === "people" || picture === "auto") out.rowPicture = picture;
  const absolute = from.getItem("stillfail.absoluteTime");
  if (absolute !== null) out.absoluteTime = absolute === "1";
  // Only entries of the shape the core keeps: one it would refuse would keep the rest out too.
  const entries = <V>(key: string, fits: (v: unknown) => v is V): Record<string, V> | undefined => {
    const all = json<Record<string, unknown>>(key);
    if (!all || typeof all !== "object" || Array.isArray(all)) return undefined;
    return Object.fromEntries(Object.entries(all).filter((e): e is [string, V] => fits(e[1])));
  };
  const strings = (v: unknown): v is string[] => Array.isArray(v) && v.every((s) => typeof s === "string");
  const keys = entries("stillfail.keys", strings);
  if (keys) out.keys = keys;
  const lastChat = entries("stillfail.lastChat", (v): v is string => typeof v === "string");
  if (lastChat) out.lastChat = lastChat;
  const tabs = entries("stillfail.chatTabs", (v): v is KeptTabs => {
    const t = v as { tabs?: unknown; active?: unknown } | null;
    return !!t && strings(t.tabs) && (t.active == null || typeof t.active === "string");
  });
  if (tabs) out.chatTabs = Object.fromEntries(Object.entries(tabs).map(([k, t]) => [k, t.active == null ? { tabs: t.tabs } : t]));
  return out;
}
