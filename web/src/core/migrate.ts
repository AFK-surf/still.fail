// Before the core, the page kept the signed-in accounts (cloud/accounts.ts)
// and this browser's device key (cloud/link.ts) in localStorage, which the
// core's worker cannot read. The first page to start the core hands them over
// once; the core keeps them in IndexedDB from then on.
import type { CoreClient } from "./client.ts";

const ACCOUNTS = "ember.accounts";
const DEVICE = "ember.device";
const DONE = "ember.core.migrated";

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
    console.error("ember core: migrating localStorage failed", error);
  }
}
