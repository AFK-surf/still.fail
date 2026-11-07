// The accounts signed in on this browser (signed in on the sign-in page, login/). The core keeps them, with their
// still.fail cloud sessions: the page sees who is signed in and signs out; tokens never reach it.
import { useCallback } from "preact/compat";
import { core, useTopic } from "../core/react.ts";
import { doingMatches, failed, useDoingList } from "../doing.ts";
import { failure, useToast } from "@stillfail/ui/toast.tsx";
import { t } from "../i18n.ts";

/** A signed-in account, as the `accounts` topic lists it. */
export interface Account {
  sub: string;
  email: string;
  name: string;
  picture: string;
}

/** The signed-in accounts; undefined until the core has answered. */
export function useAccounts(): Account[] | undefined {
  return useTopic<Account[]>({ topic: "accounts" }).value;
}

export async function signOut(sub: string): Promise<void> {
  await core().call("auth.signOut", { account: sub });
}

/** Signing out from a button: `busy(sub)` while that account is signed out (`auth.signOut`), what went wrong said in a toast. */
export function useSignOut(): { signOut(sub: string): Promise<boolean>; busy(sub?: string): boolean } {
  const toast = useToast();
  const doing = useDoingList();
  const go = useCallback((sub: string) => signOut(sub)
    .then(() => true, (e: unknown) => { toast(t("web-pages.accounts.signOutFailed", { error: failure(e) })); return false; }), [toast]);
  return { signOut: go, busy: (sub) => doing.some((item) => !failed(item) && doingMatches(item, "auth.signOut", { account: sub })) };
}
