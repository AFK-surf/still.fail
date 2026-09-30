// Before the core, the page kept the signed-in accounts (cloud/accounts.ts)
// and this browser's device key (cloud/link.ts) in localStorage, which the
// core's worker cannot read. The first page to start the core hands them over
// once; the core keeps them in IndexedDB from then on.
import type { CoreClient } from "./client.ts";

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
