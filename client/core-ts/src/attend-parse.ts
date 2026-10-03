// The attention calls by name (attend.rs `parse`): `client.focus`, `notify.set`, `notice.claim`, `notice.pushed`.
import { read } from "./core/params.ts";
import { CoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { isObject } from "./util.ts";

/// A chat as a UI names it: its thread, or its key before it has one (or both).
export type ChatOf = { station: string; thread: number | null; session: string | null; end: boolean };

/// What a UI said: each field given changes, the rest stays. `chat` undefined: not said; null: shows none.
export type FocusCall = { visible: boolean | null; focused: boolean | null; chat: ChatOf | null | undefined; left: ChatOf | null; workspace: string | null };

export type AttendCall =
  | { kind: "focus"; focus: FocusCall }
  | { kind: "set"; on: boolean | null; asked: boolean | null }
  | { kind: "claim"; id: string }
  | { kind: "pushed"; workspace: string | null };

function chatOf(v: unknown): ChatOf {
  const p = read(v, [
    ["station", "string", "req"],
    ["thread", "u64", "opt"],
    ["session", "string", "opt"],
    ["end", "bool", "default"],
  ]);
  return p as unknown as ChatOf;
}

export function parseAttend(name: string, params: unknown): AttendCall | null {
  const p = params === null || params === undefined ? {} : params;
  switch (name) {
    case "client.focus": {
      const f = read(p, [
        ["visible", "bool", "opt"],
        ["focused", "bool", "opt"],
        ["chat", "value", "opt"],
        ["left", "value", "opt"],
        ["workspace", "string", "opt"],
      ]);
      const given = isObject(p) && "chat" in p;
      const chat = !given ? undefined : f.chat === null ? null : chatOf(f.chat);
      const left = f.left === null ? null : chatOf(f.left);
      return { kind: "focus", focus: { visible: f.visible as boolean | null, focused: f.focused as boolean | null, chat, left, workspace: f.workspace as string | null } };
    }
    case "notify.set": {
      const f = read(p, [
        ["on", "bool", "opt"],
        ["asked", "bool", "opt"],
      ]);
      return { kind: "set", on: f.on as boolean | null, asked: f.asked as boolean | null };
    }
    case "notice.claim":
      return { kind: "claim", id: read(p, [["id", "string", "req"]]).id as string };
    case "notice.pushed":
      return { kind: "pushed", workspace: read(p, [["workspace", "string", "opt"]]).workspace as string | null };
    default:
      return null;
  }
}

/// The chat a focus now shows, to come back to: not one the core is still making (`new:`), nor none.
export function opened(focus: FocusCall): [string, string] | null {
  const chat = focus.chat;
  if (!chat) return null;
  const key = chat.session;
  if (key === null || key === "" || key.startsWith("new:")) return null;
  return [chat.station, key];
}

export { CoreError, t };
