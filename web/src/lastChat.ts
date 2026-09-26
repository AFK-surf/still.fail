// The chat last open, per place (a workspace, or this station), so leaving
// for settings and coming back returns to it.
import { useEffect } from "react";
import { useLocation } from "react-router";

const KEY = "ember.lastChat";

function all(): Record<string, string> {
  try {
    return JSON.parse(localStorage.getItem(KEY) ?? "{}") as Record<string, string>;
  } catch {
    return {};
  }
}

/** Remembers the current path while it is a chat (or a new chat). */
export function useRememberChat(scope: string, isChat: (path: string) => boolean): void {
  const path = useLocation().pathname;
  useEffect(() => {
    if (isChat(path)) localStorage.setItem(KEY, JSON.stringify({ ...all(), [scope]: path }));
  }, [scope, path]);
}

/** Where "back to chats" goes: the chat last open, else `fallback`. */
export function lastChat(scope: string, fallback: string): string {
  return all()[scope] ?? fallback;
}
