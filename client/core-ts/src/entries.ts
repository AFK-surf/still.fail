// A thread's entries merged into its messages (entries.rs): the one place edits are applied. A message shows its
// latest edit's text, attachments and quotes, marked edited.
import { get, isObject } from "./util.ts";

/// An entry's number in its thread.
export function nOf(entry: unknown): number | null {
  const n = get(entry, "n");
  return typeof n === "number" && Number.isInteger(n) && n >= 0 ? n : null;
}

/// The messages of a run of entries, in thread order (`seq` is the message's n).
export function merge(entries: unknown[]): Record<string, unknown>[] {
  const messages = new Map<number, Record<string, unknown>>();
  for (const entry of entries) {
    const n = nOf(entry);
    if (n === null || !isObject(entry)) continue;
    const field = (name: string) => (entry[name] === undefined ? null : entry[name]);
    const kind = entry.kind;
    if (kind === "message") {
      const message: Record<string, unknown> = {
        seq: n,
        thread: field("thread"),
        ts: field("ts"),
        authorKind: field("authorKind"),
        author: field("author"),
        agentIdentity: field("agentIdentity"),
        authorName: field("authorName"),
        text: entry.text === undefined ? "" : entry.text,
        attachments: entry.attachments === undefined ? [] : entry.attachments,
        quotes: entry.quotes === undefined ? [] : entry.quotes,
        declared: field("declared"),
        createdAt: field("at"),
        editedAt: null,
      };
      if (typeof entry.ending === "string") message.ending = entry.ending;
      if (typeof entry.profile === "string") message.profile = entry.profile;
      if (Array.isArray(entry.options) && entry.options.length > 0) message.options = entry.options;
      if (isObject(entry.card)) message.card = entry.card;
      messages.set(n, message);
    } else if (kind === "edit") {
      const target = entry.target;
      const message = typeof target === "number" ? messages.get(target) : undefined;
      if (!message) continue;
      message.text = entry.text === undefined ? "" : entry.text;
      message.attachments = entry.attachments === undefined ? [] : entry.attachments;
      message.quotes = entry.quotes === undefined ? [] : entry.quotes;
      message.editedAt = field("at");
    }
  }
  return [...messages.keys()].sort((a, b) => a - b).map((k) => messages.get(k)!);
}
