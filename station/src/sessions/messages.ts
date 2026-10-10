// session_send (the Rust station's hub/messages.rs): one session's agent writes to another's, on this station or on another
// station of the workspace (through the station transport, as station_task goes). The message is posted in the other
// chat for people to see, headed with a link back to the sender's chat, and handed to the sessions there like any
// message; they answer the same way. Nothing limits how long two agents talk: that is theirs to judge.
import { threadAddress } from "../agents/instructions.ts";
import { tr, stationLang } from "../ops/i18n.ts";
import { type Attachment, STILLFAIL_SURFACE, type SessionThread } from "../store/store.ts";
import { type Args, jsString, slackWithFiles } from "./args.ts";
import { attach } from "./conversations.ts";
import type { Hub } from "./hub.ts";
import { Refused } from "./neighbours.ts";
import { fromBefore, linkedSession, linkedStation, named, sessionThreadOf } from "./others.ts";
import { claim, sendable, sendAlong } from "./peer-files.ts";
import { dir as thumbsDir, keep } from "./thumbs.ts";

export { linkedStation };

type Json = any;

/// The method another station's message comes as (Remote hands it to `fromPeer`).
export const METHOD = "session.message";

/// At most this much text in one message (a peer request is bounded at 1 MiB).
const MAX_TEXT = 200_000;

const chars = (s: string) => Array.from(s).length;

/// A chat by its title, linked when it has a link, as written on `surface` (Markdown in still.fail chats, Slack's
/// mrkdwn elsewhere).
export function chatNamed(surface: string, title: string, link: string | null): string {
  if (link !== null && surface === STILLFAIL_SURFACE) return `[${title.replace(/[[\]]/g, "")}](${link})`;
  if (link !== null) return `<${link}|${title.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;").replaceAll("|", "/")}>`;
  return title;
}

/// Who a message comes from, as its header shows it: the sender's chat by its title, linked when it has a link. The
/// first message of a chat an agent opened (chat_create) says it opened it.
function header(surface: string, title: string, link: string | null, opened = false): string {
  return tr(stationLang(), opened ? "station.session.openedBy" : "station.session.from", { from: chatNamed(surface, title, link) });
}

/// The sender's chat as a message from it is headed: its title, and its link once the station is in a workspace.
export function sender(hub: Hub, key: string): [string, string | null] {
  const row = hub.store.getSession(key);
  if (!row) throw new Error("unknown session");
  let thread = null;
  try {
    thread = sessionThreadOf(hub, key).thread;
  } catch {}
  const title = [thread?.title ?? thread?.autoTitle ?? null, row.title].find((t) => t !== null && t !== undefined);
  const shown = title !== undefined && title !== null && title.trim() !== "" ? title : key;
  return [shown, hub.link(key) ?? null];
}

/// session_send from session `key`.
export async function sessionSend(hub: Hub, key: string, args: Args): Promise<string> {
  const to = (args.to === undefined ? "" : jsString(args.to)).trim();
  const text = (args.text === undefined ? "" : jsString(args.text)).trim();
  if (to === "") throw new Error("to is required: the other chat's link, its session key or a thread address; chat_list lists this station's");
  if (text === "") throw new Error("text is empty");
  if (chars(text) > MAX_TEXT) throw new Error(`text is too long (at most ${MAX_TEXT} characters): put the rest in a file and name its path`);
  const paths: string[] = Array.isArray(args.files) ? args.files.map(jsString) : [];
  const [title, link] = sender(hub, key);
  const here = link !== null ? linkedStation(link) : null;
  const there = linkedStation(to);
  if (there !== null && there !== here) {
    const target = linkedSession(to)?.[0];
    if (target === undefined) throw new Error(`${to} names no chat`);
    const call = hub.peers();
    if (!call) throw new Error("other stations cannot be reached from this one yet");
    const files = sendable(hub, key, paths);
    const request: Json = { method: METHOD, session: key, to: target, text, from: { title, link } };
    let answer: Json;
    try {
      // The files first, the message naming them after (peer-files.ts).
      if (files.length > 0) request.files = await sendAlong(call, there, key, target, files);
      answer = await call(there, request);
    } catch (error) {
      // What a station from before session.message answers it with (it took it for a task).
      const old = (error as Error).message;
      if (error instanceof Refused && fromBefore(old)) {
        throw new Error(`not sent to ${to}: that station is not updated yet and takes no ${files.length > 0 ? "files" : "messages"}`);
      }
      throw new Error(`not sent to ${to}: ${old}. If it timed out, it may have arrived: ask before sending it again`);
    }
    const place = typeof answer?.thread === "string" ? answer.thread : "its chat";
    return `Sent to ${target} on station ${there} (${place}). Its agent answers with session_send to your chat.`;
  }
  const what = named(hub, to);
  let thread: SessionThread;
  let targets: string[];
  if (what.type === "session") {
    if (what.key === key) throw new Error("that is this session: use chat_post for your own conversations");
    // Said in its chat: every agent there hears it, as they would a person.
    thread = sessionThreadOf(hub, what.key);
    targets = hub.store.threadSessions(thread.thread.id).map((m) => m.session);
    if (targets.includes(key)) throw new Error(`${threadAddress(thread.thread.channel, thread.thread.threadTs)} is one of your conversations: use chat_post there`);
  } else {
    const members = hub.store.threadSessions(what.thread.id);
    if (members.some((m) => m.session === key)) throw new Error(`${to} is one of your conversations: use chat_post there`);
    const connect = members[0]?.connect;
    if (connect === undefined) throw new Error(`no agent takes part in ${to}`);
    thread = { thread: what.thread, connect };
    targets = members.map((m) => m.session);
  }
  // Kept in the uploads of the session the chat's files are read from (its first agent's).
  const files = paths.length > 0 ? attach(hub, key, paths, targets[0] ?? key) : [];
  const place = await postFrom(hub, thread, key, title, link, text, targets, files);
  return `Sent to ${place} (agents there: ${targets.join(", ")}). They answer with session_send to your chat.`;
}

/// A message another station's session sent here (session_send there), from station `peer`.
export async function fromPeer(hub: Hub, peer: string, request: Json): Promise<Json> {
  const text = typeof request?.text === "string" ? request.text.trim() : "";
  const target = typeof request?.to === "string" ? request.to : "";
  const from = typeof request?.session === "string" ? request.session : "";
  if (text === "" || target === "" || from === "" || chars(text) > MAX_TEXT) throw new Error(`a message needs to, session and text (at most ${MAX_TEXT} characters)`);
  if (hub.store.getSession(target) === null) throw new Error(`no session ${target} on this station (it may have been deleted)`);
  const thread = sessionThreadOf(hub, target);
  const targets = hub.store.threadSessions(thread.thread.id).map((m) => m.session);
  // Files sent ahead of it (session.put), into the uploads of the session the chat's files are read from.
  const files = claim(hub, peer, from, targets[0] ?? target, request?.files);
  const title = typeof request?.from?.title === "string" && request.from.title.trim() !== "" ? request.from.title : from;
  const link = typeof request?.from?.link === "string" && request.from.link !== "" ? request.from.link : null;
  // The first message of a chat that session opened here (chat_create there): headed as its opening.
  const opener = hub.store.openerOf(target);
  const opened = request?.opened === true && opener !== null && opener.parentStation === peer && opener.parent === from;
  // Not a session of this station: by its station and key, so it is never taken for one.
  const place = await postFrom(hub, thread, `${peer}/${from}`, title, link, text, targets, files, opened);
  return { thread: place };
}

/// Posts `text` from `author` in `thread`, headed with where it comes from (as its opening when `opened`), with `given`
/// files, and hands it to `targets`. Its address.
export async function postFrom(hub: Hub, thread: SessionThread, author: string, title: string, link: string | null, text: string, targets: string[], given: Attachment[] = [], opened = false): Promise<string> {
  const row = thread.thread;
  let said = `${header(row.surface, title, link, opened)}\n\n${text}`;
  const files = await keep(given, thumbsDir(hub.config().dataDir));
  const here = { channel: row.channel, threadTs: row.threadTs };
  const chat = hub.chat(thread.connect);
  let ts: string;
  try {
    ts = await chat.post(here, said, files);
  } catch (error) {
    // A Slack app that cannot upload: a link to the files in still.fail instead (as chat_post does).
    const page = targets.length > 0 ? hub.link(targets[0]!) : undefined;
    if (files.length === 0 || page === undefined || !String((error as Error).message).includes("missing_scope")) throw error;
    const [sent, kept] = slackWithFiles(said, files, page);
    ts = await chat.post(here, sent, []);
    said = kept;
  }
  const [n] = hub.store.insertMessage({ thread: row.id, ts, authorKind: "agent", author, text: said, attachments: files });
  hub.deliver(row.id, n, targets.filter((t) => t !== author), said);
  return threadAddress(row.channel, row.threadTs);
}
