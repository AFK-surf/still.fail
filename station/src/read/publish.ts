// A chat as a published snapshot would show it (docs/public-share.md): its messages up to one, people by name and
// never by address, what looks like a secret hidden, its attachments numbered. Read here, off the main thread; the
// route (api/routes/publish.ts) shows it as a preview, or writes it out with the attachments ticked.
import { redact } from "../publish/redact.ts";
import type { Draft, DraftFile } from "../publish/snapshot.ts";
import type { Lang } from "../ops/i18n.ts";
import * as store from "./store.ts";
import type { AuthorKind, MessageRow, Store } from "./store.ts";
import { makerOf, modelName } from "../ops/model-name.ts";
import { setLang, tr } from "./spoken.ts";
import { HttpError, apiOf, authorNames, chatTitle, useNames } from "./views.ts";
import { mime } from "./sessions.ts";
import { dirname, join } from "node:path";
import { clean, samePath } from "../ops/paths.ts";

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

/// Who said a message, as the snapshot names them: a person of a still.fail chat as `personName`, one of a Slack thread
/// by their Slack name; an agent by the model it ran on, as the chat shows it (else its connect's name); never by a
/// session's key or an address (one with no model of its own: by its runtime).
function authorOf(s: Store, m: MessageRow, names: Record<string, string>, known: Map<string, string>, said: (kind: AuthorKind, author: string) => string | null): string {
  if (m.authorKind === "person") return m.author.includes("@") ? personName(m.author, names, known) : (said("person", m.author) ?? m.author);
  if (m.authorKind === "agent") {
    const model = typeof m.agentIdentity?.model === "string" && m.agentIdentity.model !== "" ? m.agentIdentity.model : null;
    if (model !== null) return modelName(model);
    const name = said("agent", m.author);
    if (name !== null && name !== m.author) return name;
    return store.getSession(s, m.author)?.runtime === "codex" ? "Codex" : "Claude Code";
  }
  return said(m.authorKind, m.author) ?? "still.fail";
}

/// What draws who said a message as the chat does: an agent's model's maker and its runtime (its mark; its model too, for
/// the members' preview), a person's address (the members' preview gives their picture by it; never in the snapshot).
function whoDrawn(s: Store, m: MessageRow): { maker?: string; model?: string; runtime?: string; person?: string } {
  if (m.authorKind === "person") return m.author.includes("@") ? { person: m.author } : {};
  if (m.authorKind !== "agent") return {};
  const session = store.getSession(s, m.author);
  const model = typeof m.agentIdentity?.model === "string" && m.agentIdentity.model !== "" ? m.agentIdentity.model : (session?.model ?? null);
  const maker = model !== null ? makerOf(model) : null;
  return { ...(maker !== null ? { maker } : {}), ...(model !== null ? { model } : {}), ...(session ? { runtime: session.runtime } : {}) };
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
  // The session whose uploads keep each file (what its preview on the pages goes through): the one whose workspace it is
  // in, else the chat's first.
  const sessions = store.threadSessions(s, a.thread).map((m) => store.getSession(s, m.session)).filter((x) => x !== null);
  const ownerOf = (path: string) => (sessions.find((x) => samePath(clean(join(x.workspace, "uploads")), dirname(clean(path)))) ?? sessions[0])?.key ?? null;
  const entries = messages.map((m) => {
    const hidden = redact(m.text, mark);
    if (hidden.count > 0) redacted.push({ n: m.n, count: hidden.count });
    const author = authorOf(s, m, a.names, s.names, names);
    const own = m.attachments.map((f) => {
      const k = `f${files.length}`;
      const file: DraftFile = { k, name: f.name, size: f.size, type: mime(f.name), n: m.n, path: f.path, owner: ownerOf(f.path) };
      if (f.width !== undefined) file.width = f.width;
      if (f.height !== undefined) file.height = f.height;
      if (f.thumbhash !== undefined) file.thumbhash = f.thumbhash;
      files.push(file);
      return k;
    });
    return { n: m.n, at: m.createdAt, authorKind: m.authorKind, author, text: hidden.text, files: own, ...whoDrawn(s, m) };
  });
  // Its name is the first thing said in it when nobody gave it one: hidden alike.
  return { title: redact(chatTitle(found, null), mark).text, upto: messages.at(-1)!.n, entries, redacted, files };
}
