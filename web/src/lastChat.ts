// The chat last open, per place (a workspace, or this station), so leaving for settings and coming back returns to it.
// Kept on this device (prefs.ts).
import { useEffect } from "react";
import { useLocation } from "react-router";
import { prefs, setPrefs } from "./prefs.ts";

/** How the keys the core gives chats made here, before their station has made them, begin (views.rs, PENDING_PREFIX). */
export const PENDING = "new:";

/** Remembers the current path while it is a chat (or a new chat). */
export function useRememberChat(scope: string, isChat: (path: string) => boolean): void {
  const path = useLocation().pathname;
  useEffect(() => {
    // A chat made here is remembered once its station has made it, under its station's key (ChatPage.tsx).
    if (isChat(path) && !path.includes(`/chats/${encodeURIComponent(PENDING)}`) && prefs().lastChat[scope] !== path) setPrefs({ lastChat: { [scope]: path } });
  }, [scope, path]);
}

/** Where "back to chats" goes: the chat last open, else `fallback`. */
export function lastChat(scope: string, fallback: string): string {
  return prefs().lastChat[scope] ?? fallback;
}
