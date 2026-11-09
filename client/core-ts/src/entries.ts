// A thread's entries merged into its messages: the one place edits are applied. A message shows its
// latest edit's text, attachments and quotes, marked edited.
import { get, isObject, sharedValue } from "./util.ts";
import { t } from "./i18n.ts";

/// The message each entry makes (an entry held is the same object while it does not change: data.ts): made once, so the
/// messages of what did not change are the objects they were, which what is made of them keeps (views.ts).
const made = new WeakMap<object, Record<string, unknown>>();
/// The messages an edit was put on here: copies, the one an entry made left as it was.
const edited = new WeakSet<object>();

/// An entry's number in its thread.
export function nOf(entry: unknown): number | null {
  const n = get(entry, "n");
  return typeof n === "number" && Number.isInteger(n) && n >= 0 ? n : null;
}

/// The messages of a run of entries, in thread order (`seq` is the message's n). `source`, when supplied, hears each
/// message and each edit changing its words; the last entry it hears for a message supplied its current words.
export function merge(entries: unknown[], source?: (seq: number, entry: object) => void): Record<string, unknown>[] {
  const messages = new Map<number, Record<string, unknown>>();
  for (const entry of entries) {
    const n = nOf(entry);
    if (n === null || !isObject(entry)) continue;
    const field = (name: string) => (entry[name] === undefined ? null : entry[name]);
    const kind = entry.kind;
    if (kind === "message") {
      const once = made.get(entry);
      if (once !== undefined) {
        messages.set(n, once);
        source?.(n, entry);
        continue;
      }
      const message: Record<string, unknown> = {
        seq: n,
        thread: field("thread"),
        ts: field("ts"),
        authorKind: field("authorKind"),
        author: field("author"),
        agentIdentity: field("agentIdentity"),
        authorName: authorNameOf(field("authorKind"), field("author"), field("authorName")),
        text: entry.text === undefined ? "" : entry.text,
        attachments: entry.attachments === undefined ? [] : entry.attachments,
        quotes: entry.quotes === undefined ? [] : entry.quotes,
        declared: field("declared"),
        createdAt: field("at"),
        editedAt: null,
      };
      if (typeof entry.authorPicture === "string") message.authorPicture = entry.authorPicture;
      if (typeof entry.authorModel === "string") message.authorModel = entry.authorModel;
      if (typeof entry.authorRuntime === "string") message.authorRuntime = entry.authorRuntime;
      if (typeof entry.ending === "string") message.ending = entry.ending;
      if (typeof entry.profile === "string") message.profile = entry.profile;
      if (typeof entry.runtime === "string") message.runtime = entry.runtime;
      if (Array.isArray(entry.options) && entry.options.length > 0) message.options = entry.options;
      if (isObject(entry.card)) message.card = entry.card;
      // What two chats' agents wrote each other (views.ts isLetter): which way, and the other chat.
      if (isObject(entry.letter)) message.letter = entry.letter;
      // The station's notice that a chat's run changed: how it ran and runs (run-change.ts).
      if (isObject(entry.change)) message.change = entry.change;
      made.set(entry, sharedValue(message));
      messages.set(n, message);
      source?.(n, entry);
    } else if (kind === "edit") {
      const target = entry.target;
      if (typeof target !== "number") continue;
      const held = messages.get(target);
      if (!held) continue;
      // (edited on a copy of its own: the message its entry made stays as it was for the next merge)
      let message = held;
      if (!edited.has(held)) {
        message = { ...held };
        edited.add(message);
        messages.set(target, message);
      }
      // Its card restated by its author (a vault request's outcome): the card alone when the words are the same.
      if (isObject(entry.card)) {
        message.card = entry.card;
        if ((entry.text ?? "") === message.text) continue;
      }
      const text = entry.text === undefined ? "" : entry.text;
      if (text !== message.text) source?.(target, entry);
      message.text = text;
      message.attachments = entry.attachments === undefined ? [] : entry.attachments;
      message.quotes = entry.quotes === undefined ? [] : entry.quotes;
      message.editedAt = field("at");
    }
  }
  return [...messages.keys()].sort((a, b) => a - b).map((k) => messages.get(k)!);
}

/// What a message's author is called: as its station names them, the local page's admin (whom a station names no more:
/// station/src/read/views.ts `authorNames`) in this device's words.
export function authorNameOf(kind: unknown, author: unknown, named: unknown): unknown {
  return (named === null || named === undefined) && kind === "person" && author === "local" ? t("station.author.admin") : named;
}
