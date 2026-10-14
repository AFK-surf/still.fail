// A chat as a published snapshot would show it (docs/public-share.md): its messages up to one, people by name and
// never by address, what looks like a secret hidden, its attachments numbered. Read here, off the main thread; the
// route (api/routes/publish.ts) shows it as a preview, or writes it out with the attachments ticked.
import { redact } from "../publish/redact.ts";
import type { Draft, DraftFile } from "../publish/snapshot.ts";
import type { Lang } from "../ops/i18n.ts";
import * as store from "./store.ts";
import type { Store } from "./store.ts";
import { setLang, tr } from "./spoken.ts";
import { HttpError, apiOf, authorNames, chatTitle, useNames } from "./views.ts";
import { mime } from "./sessions.ts";

/// Messages read for a snapshot at most: a chat with more is published from its latest ones.
const MOST = 5000;

/// A person as the snapshot names them: by `names` (the workspace's, as the client has them), as their credential
/// told this station, or by their address's first part; never by the address.
function personName(email: string, names: Record<string, string>, known: Map<string, string>): string {
  const given = names[email] ?? known.get(email);
  if (given !== undefined && given.trim() !== "" && given !== email) return given;
  const at = email.indexOf("@");
  return at > 0 ? email.slice(0, at) : email;
}

/// The chat `thread` as published up to message n = `upto` (its latest without it), read by `viewer`.
export function publishDraft(s: Store, a: { thread: number; upto: number | null; names: Record<string, string>; viewer: string }, lang: Lang): Draft {
  setLang(lang);
  useNames(s);
  const found = store.listThreads(s, a.viewer, null, a.thread)[0];
  if (found === undefined) throw new HttpError(404, tr("station.publish.noChat"));
  const messages = store.messagesBefore(s, a.thread, a.upto === null ? null : a.upto + 1, MOST);
  if (messages.length === 0) throw new HttpError(400, tr("station.publish.empty"));
  const names = authorNames(apiOf(s), a.thread);
  const mark = tr("station.publish.hidden");
  const redacted: Draft["redacted"] = [];
  const files: DraftFile[] = [];
  const entries = messages.map((m) => {
    const hidden = redact(m.text, mark);
    if (hidden.count > 0) redacted.push({ n: m.n, count: hidden.count });
    // A person of a Slack thread goes by their Slack name (their id when none is known), as the chat shows them.
    const author = m.authorKind === "person" && m.author.includes("@") ? personName(m.author, a.names, s.names) : (names(m.authorKind, m.author) ?? m.author);
    const own = m.attachments.map((f) => {
      const k = `f${files.length}`;
      const file: DraftFile = { k, name: f.name, size: f.size, type: mime(f.name), n: m.n, path: f.path };
      if (f.width !== undefined) file.width = f.width;
      if (f.height !== undefined) file.height = f.height;
      if (f.thumbhash !== undefined) file.thumbhash = f.thumbhash;
      files.push(file);
      return k;
    });
    return { n: m.n, at: m.createdAt, authorKind: m.authorKind, author, text: hidden.text, files: own };
  });
  // Its name is the first thing said in it when nobody gave it one: hidden alike.
  return { title: redact(chatTitle(found, null), mark).text, upto: messages.at(-1)!.n, entries, redacted, files };
}
