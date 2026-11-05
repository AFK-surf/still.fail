// A thread's summary as its viewer has it (GET /threads/:id: how far it goes, its latest message, what the viewer has not
// read, who wrote in it), brought on by what its station's stream says was said in it, here: the station tells what it
// writes as it writes it, and leaves what a thread's summary makes of that to the device (docs/core-ts.md, sync).
// Made by the station, the summary was read again for every viewer after every message (a phone's few languages and
// workspaces each), from the disk while its machine was short of memory: seconds for each on a station (2026-11-02).
import { get, isObject } from "../util.ts";
import { isOwnSurface } from "../titles.ts";

type J = Record<string, any>;


const n = (v: unknown): number | null => (typeof v === "number" && Number.isInteger(v) && v >= 0 ? v : null);

/// The message as a thread's summary says its latest (read/views.ts `messageView`), from an entry as the stream told it.
function messageOf(e: J): J {
  const m: J = {
    agentIdentity: e.agentIdentity ?? null, seq: e.n, thread: e.thread, ts: e.ts ?? null, authorKind: e.authorKind, author: e.author,
    authorName: e.authorName ?? null, text: e.text ?? null, attachments: e.attachments ?? [], quotes: e.quotes ?? [], declared: e.declared ?? null,
    createdAt: e.at, editedAt: null,
  };
  if (e.authorPicture !== undefined) m.authorPicture = e.authorPicture;
  if (e.authorModel !== undefined) m.authorModel = e.authorModel;
  if (e.authorRuntime !== undefined) m.authorRuntime = e.authorRuntime;
  if (e.ending !== undefined) m.ending = e.ending;
  return m;
}

/// `held` (a thread's summary for the viewer whose email is `me`) after `entries` (as its station's stream told them,
/// GET /threads/:id/entries' shape) were said in it: as the station would say it now. Null where this cannot say it, to
/// be read: none held, nothing said (a thread gone is told so), entries that do not go on from where it stands, a
/// thread not of the station's own chats (whose people's other selves only the station knows), a person not known by
/// their email (the station's own page's).
export function threadAfter(held: unknown, entries: readonly unknown[], me: string): J | null {
  if (!isObject(held) || !isOwnSurface(get(held, "surface"))) return null;
  const said = entries.filter(isObject) as J[];
  if (said.length === 0) return null;
  let last = n(get(held, "last"));
  const read = n(get(held, "read"));
  if (last === null || read === null) return null;
  const ns = said.map((e) => n(e.n));
  if (ns.some((x) => x === null)) return null;
  const sorted = said.map((e, i) => [ns[i]!, e] as const).sort((a, b) => a[0] - b[0]);
  let unread = n(get(held, "unread")) ?? 0;
  let lastMessage = (get(held, "lastMessage") ?? null) as J | null;
  const people = [...((get(held, "people") as J[] | undefined) ?? [])];
  let firstText = (get(held, "firstText") ?? null) as string | null;
  const mine = me.toLowerCase();
  for (const [at, e] of sorted) {
    if (at <= last) continue;
    // What it covers goes on into what was said, none left out between.
    if (at !== last + 1) return null;
    if (e.kind === "message") {
      // A letter (another chat's agent's, marked as one before letters had a log of their own) is none of these.
      if (e.letter === undefined) {
        if (e.authorKind === "person" && (typeof e.author !== "string" || e.author === "local" || !e.author.includes("@"))) return null;
        lastMessage = messageOf(e);
        const own = e.authorKind === "person" && e.author.toLowerCase() === mine;
        if (at > read && !own) unread++;
        if (e.authorKind === "person") {
          if (!people.some((p) => get(p, "id") === e.author)) people.push({ id: e.author, name: e.authorName ?? e.author, email: e.author, via: "cloud" });
          if (firstText === null && typeof e.text === "string") firstText = [...e.text].slice(0, 300).join("");
        }
      }
    } else if (e.kind === "edit") {
      // An edit of its latest message is what that says now.
      if (lastMessage !== null && e.target === lastMessage.seq) {
        lastMessage = { ...lastMessage, text: e.text ?? null, attachments: e.attachments ?? [], quotes: e.quotes ?? [], editedAt: e.at };
      }
    } else {
      return null;
    }
    last = at;
  }
  return { ...(held as J), last, lastMessage, unread, people, firstText };
}

/// `held` after letters (as the stream told them, GET /threads/:id/letters' shape) came in its own log of them: how far
/// that goes, and how many letters it has (those from before its log among them). Null where it does not go on from
/// where it stands.
export function threadAfterLetters(held: unknown, letters: readonly unknown[]): J | null {
  if (!isObject(held)) return null;
  const ns = (letters.filter(isObject) as J[]).map((l) => n(l.n));
  if (ns.length === 0) return held as J;
  if (ns.some((x) => x === null)) return null;
  const was = n(get(held, "lettersLast")) ?? 0;
  const top = Math.max(was, ...(ns as number[]));
  const fresh = (ns as number[]).filter((x) => x > was).sort((a, b) => a - b);
  if (fresh.length > 0 && fresh[0]! > was + 1) return null;
  const before = (n(get(held, "letters")) ?? 0) - was;
  return { ...(held as J), letters: before + top, lettersLast: top };
}
