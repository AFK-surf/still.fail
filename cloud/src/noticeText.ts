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
