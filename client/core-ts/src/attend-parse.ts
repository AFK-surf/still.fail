// The attention calls by name (attend.rs `parse`): `client.focus`, `notify.set`, `notify.permission`, `notice.claim`,
// `notice.pushed`, `notice.bring`.
import { read } from "./core/params.ts";
import { CoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { isObject } from "./util.ts";

/// A chat as a UI names it: its thread, or its key before it has one (or both); whether its end shows, and the newest
/// message shown whole (`seen`, its seq).
export type ChatOf = { station: string; thread: number | null; session: string | null; end: boolean; seen: number | null };

/// What a UI said: each field given changes, the rest stays. `chat` undefined: not said; null: shows none. `newChat`: the
/// workspace whose new chat it shows now (what that workspace goes back to).
export type FocusCall = { visible: boolean | null; focused: boolean | null; chat: ChatOf | null | undefined; left: ChatOf | null; workspace: string | null; newChat: string | null };

export type AttendCall =
  | { kind: "focus"; focus: FocusCall }
  | { kind: "set"; on: boolean | null; asked: boolean | null; kinds: unknown; preview: boolean | null; workspaces: unknown }
  | { kind: "permission"; state: Permission }
  | { kind: "claim"; id: string }
  | { kind: "pushed"; workspace: string | null; notice: string | null; title: string | null }
  | { kind: "bring"; station: string; session: string; seq: number | null };

/// Whether the system lets this device show notifications, as its app finds: allowed, refused, not asked yet, or not
/// known (no way to tell here).
export type Permission = "granted" | "denied" | "default" | "unknown";
const PERMISSIONS: Permission[] = ["granted", "denied", "default", "unknown"];

function chatOf(v: unknown): ChatOf {
  const p = read(v, [
    ["station", "string", "req"],
    ["thread", "u64", "opt"],
    ["session", "string", "opt"],
    ["end", "bool", "default"],
    ["seen", "u64", "opt"],
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
        ["newChat", "string", "opt"],
      ]);
      const given = isObject(p) && "chat" in p;
      const chat = !given ? undefined : f.chat === null ? null : chatOf(f.chat);
      const left = f.left === null ? null : chatOf(f.left);
      return { kind: "focus", focus: { visible: f.visible as boolean | null, focused: f.focused as boolean | null, chat, left, workspace: f.workspace as string | null, newChat: f.newChat as string | null } };
    }
    case "notify.set": {
      const f = read(p, [
        ["on", "bool", "opt"],
        ["asked", "bool", "opt"],
        ["kinds", "value", "opt"],
        ["preview", "bool", "opt"],
        ["workspaces", "value", "opt"],
      ]);
      if (f.kinds !== null && !isObject(f.kinds)) throw CoreError.invalid(t("core-misc.params.not_object"));
      if (f.workspaces !== null && !isObject(f.workspaces)) throw CoreError.invalid(t("core-misc.params.not_object"));
      return { kind: "set", on: f.on as boolean | null, asked: f.asked as boolean | null, kinds: f.kinds ?? null, preview: f.preview as boolean | null, workspaces: f.workspaces ?? null };
    }
    case "notify.permission": {
      const state = read(p, [["state", "string", "req"]]).state as string;
      if (!PERMISSIONS.includes(state as Permission)) throw CoreError.invalid(t("core-misc.params.invalid", { error: "state" }));
      return { kind: "permission", state: state as Permission };
    }
    case "notice.claim":
      return { kind: "claim", id: read(p, [["id", "string", "req"]]).id as string };
    case "notice.pushed": {
      const f = read(p, [["workspace", "string", "opt"], ["kind", "string", "opt"], ["title", "string", "opt"]]);
      return { kind: "pushed", workspace: f.workspace as string | null, notice: f.kind as string | null, title: f.title as string | null };
    }
    case "notice.bring": {
      const f = read(p, [["station", "string", "req"], ["session", "string", "req"], ["seq", "u64", "opt"]]);
      return { kind: "bring", station: f.station as string, session: f.session as string, seq: f.seq as number | null };
    }
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
