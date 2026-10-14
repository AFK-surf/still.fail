// A thread's entries merged into its messages (entries.rs): the one place edits are applied. A message shows its
// latest edit's text, attachments and quotes, marked edited; and how its card came out (`settled`: the text of a settle
// entry, the station's, which quotes it), the message itself as it was. The station's log only grows: what changes is
// read here.
import { get, isObject } from "./util.ts";

/// An entry's number in its thread.
export function nOf(entry: unknown): number | null {
  const n = get(entry, "n");
  return typeof n === "number" && Number.isInteger(n) && n >= 0 ? n : null;
}

/// The messages of a run of entries, in thread order (`seq` is the message's n).
export function merge(entries: unknown[]): Record<string, unknown>[] {
  const messages = new Map<number, Record<string, unknown>>();
  const byTs = new Map<string, number>();
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
      if (typeof entry.ts === "string") byTs.set(entry.ts, n);
    } else if (kind === "edit") {
      const target = entry.target;
      const message = typeof target === "number" ? messages.get(target) : undefined;
      if (!message) continue;
      message.text = entry.text === undefined ? "" : entry.text;
      message.attachments = entry.attachments === undefined ? [] : entry.attachments;
      message.quotes = entry.quotes === undefined ? [] : entry.quotes;
      message.editedAt = field("at");
    } else if (kind === "settle") {
      const quoted = get((Array.isArray(entry.quotes) ? entry.quotes : [])[0], "ts");
      const seq = typeof quoted === "string" ? byTs.get(quoted) : undefined;
      const message = seq === undefined ? undefined : messages.get(seq);
      if (message && typeof entry.text === "string" && entry.text !== "") message.settled = entry.text;
    }
  }
  return [...messages.keys()].sort((a, b) => a - b).map((k) => messages.get(k)!);
}
