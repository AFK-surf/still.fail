// The chat last open, per workspace, so leaving for settings or another workspace and coming back returns to it; and
// what each workspace has waiting. Both the core's (client/core-ts/src/views/marks.ts): it keeps the chat from what the
// chat pages tell it (`client.focus`), so a settings page, showing none, leaves it as it was. A core from before it (an
// older desktop app's) has no `workspaceMarks`: the page keeps the path in the prefs then, as it did.
import { useEffect } from "react";
import { useLocation } from "react-router";
import { useTopic } from "./core/react.ts";
import type { OpenChat, WorkspaceMarksView } from "./core/shapes.ts";
import { prefs, setPrefs } from "./prefs.ts";
import { stationBase } from "./station.tsx";

/** How the keys the core gives chats made here, before their station has made them, begin (views/views.ts, PENDING_PREFIX). */
export const PENDING = "new:";

function useMarks(workspace: string) {
  return useTopic<WorkspaceMarksView>({ topic: "workspaceMarks", workspace });
}

/** Each workspace's marks and chat last open; `workspace`, the one in view (its `others` are the rest's). */
export function useWorkspaceMarks(workspace: string): WorkspaceMarksView | undefined {
  return useMarks(workspace).value;
}

function chatPath(chat: OpenChat): string {
  return `${stationBase(chat.station)}/chats/${encodeURIComponent(chat.key)}`;
}

/** Where "back to chats" goes in `scope`: the chat last open, else `fallback`; undefined until the core has said. */
export function useLastChat(scope: string, fallback: string): string | undefined {
  const marks = useMarks(scope);
  if (marks.error) return prefs().lastChat[scope] ?? fallback;
  if (!marks.value) return undefined;
  const chat = marks.value.workspaces[scope]?.chat;
  return chat ? chatPath(chat) : fallback;
}

/** With a core from before `workspaceMarks` only: remembers the current path while it is a chat (or a new chat). */
export function useRememberChat(scope: string, isChat: (path: string) => boolean): void {
  const path = useLocation().pathname;
  const old = !!useMarks(scope).error;
  useEffect(() => {
    // A chat made here is remembered once its station has made it, under its station's key (ChatPage.tsx).
    if (old && isChat(path) && !path.includes(`/chats/${encodeURIComponent(PENDING)}`) && prefs().lastChat[scope] !== path) setPrefs({ lastChat: { [scope]: path } });
  }, [old, scope, path]);
}
