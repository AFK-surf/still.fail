// What a notification says (docs/notifications.md's table), apart from push.ts so the tests can load it outside
// Workers.
import { tr, type Lang } from "./i18n.ts";

/** How long a text of a notification may be, in characters, the ellipsis included. */
const MAX_TEXT = 140;

/** One line, whitespace collapsed, at most MAX_TEXT characters (an ellipsis ending one cut short). */
export function line(text: string): string {
  const chars = Array.from(text.replace(/\s+/g, " ").trim());
  return chars.length <= MAX_TEXT ? chars.join("") : chars.slice(0, MAX_TEXT - 1).join("").trimEnd() + "…";
}

/** A notification's text, by its kind (docs/notifications.md's table), in the language of the device it goes to. */
export function noticeBody(kind: string, text: string, by?: string, lang: Lang = "zh"): string {
  if (kind === "block") return line(tr(lang, "cloud.notice.block", { text }));
  if (kind === "failed") return line(tr(lang, "cloud.notice.failed", { text }));
  return line(by ? `${by}: ${text}` : text);
}

/**
 * What a device shows of notices, as it says when it registers (docs/notifications.md `notify.set`): which kinds
 * (`wait` covers `block`; `done` is `off`, `away` or `always`), whether what was said (`preview`), and the workspaces
 * it hears nothing of (`muted`; an older app says none).
 */
export type Shows = { kinds: { wait: boolean; failed: boolean; done: "off" | "away" | "always"; message: boolean }; preview: boolean; muted: string[] };

/** What a registration says the device shows; null when it says nothing (an older app's: every kind, in full). */
export function showsOf(input: Record<string, unknown>): Shows | null {
  const k = input.kinds;
  if (!k || typeof k !== "object" || typeof input.preview !== "boolean") return null;
  const kinds = k as Record<string, unknown>;
  const flag = (name: string) => kinds[name] !== false;
  const done = kinds.done === "off" || kinds.done === "always" ? kinds.done : "away";
  const muted = Array.isArray(input.muted) ? input.muted.filter((w): w is string => typeof w === "string") : [];
  return { kinds: { wait: flag("wait"), failed: flag("failed"), done, message: flag("message") }, preview: input.preview, muted };
}

/**
 * Whether a device shows a notice of `kind` of `workspace` at all: not of a workspace it turned off; a push comes with
 * none of its pages in front, so `done` unless off.
 */
export function shown(shows: Shows | null, kind: string, workspace = ""): boolean {
  if (!shows) return true;
  if (shows.muted.includes(workspace)) return false;
  if (kind === "block" || kind === "wait") return shows.kinds.wait;
  if (kind === "failed") return shows.kinds.failed;
  if (kind === "message") return shows.kinds.message;
  return shows.kinds.done !== "off";
}

/** A notification's text for a device: what was said (noticeBody), or with its preview off only what happened. */
export function noticeBodyFor(shows: Shows | null, kind: string, text: string, by?: string, lang: Lang = "zh"): string {
  if (!shows || shows.preview) return noticeBody(kind, text, by, lang);
  const what = kind === "block" || kind === "wait" ? "wait" : kind === "failed" || kind === "message" ? kind : "done";
  return tr(lang, `cloud.notice.hidden.${what}`);
}
