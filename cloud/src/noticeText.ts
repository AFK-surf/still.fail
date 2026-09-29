// What a notification says (docs/notifications.md's table), apart from push.ts so the tests can load it outside
// Workers.

/** How long a text of a notification may be, in characters, the ellipsis included. */
const MAX_TEXT = 140;

/** One line, whitespace collapsed, at most MAX_TEXT characters (an ellipsis ending one cut short). */
export function line(text: string): string {
  const chars = Array.from(text.replace(/\s+/g, " ").trim());
  return chars.length <= MAX_TEXT ? chars.join("") : chars.slice(0, MAX_TEXT - 1).join("").trimEnd() + "…";
}

/** A notification's text, by its kind (docs/notifications.md's table). */
export function noticeBody(kind: string, text: string, by?: string): string {
  if (kind === "block") return line(`需要处理 · ${text}`);
  if (kind === "failed") return line(`出错了 · ${text}`);
  return line(by ? `${by}: ${text}` : text);
}
