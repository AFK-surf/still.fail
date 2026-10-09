// Chats an agent opens for another (chat_create): a new session in a still.fail chat of its own, on this station or on
// another of the workspace (`session.create` there, its files and first message after it as session_send sends them).
// The chat begins with the opener's message, headed as its opening; its starter is the person who started the opener's
// chat, so what it asks goes to them. Each time a turn of it ends all_done or need_human (or fails, or is stopped), the
// opener is told (`settled`, `session.notice` from another station). Nothing is sent again by itself: a call whose answer
// was uncertain is the agent's to repeat with the same key, which gives the chat made then rather than another.
import { log } from "../ops/log.ts";
import { tr, stationLang } from "../ops/i18n.ts";
import { threadAddress } from "../agents/instructions.ts";
import type { SessionThread } from "../store/store.ts";
import { type Args, jsString } from "./args.ts";
import { attach } from "./conversations.ts";
import type { Hub } from "./hub.ts";
import { INTERNAL_CONNECT } from "./internal.ts";
import { newSession } from "./lifecycle.ts";
import { chatNamed, postFrom, sender } from "./messages.ts";
import { Refused } from "./neighbours.ts";
import { fromBefore, linkedStation, sessionThreadOf } from "./others.ts";
import { sendable, sendAlong } from "./peer-files.ts";

type Json = any;

/// The method another station's agent opens a chat here by.
export const CREATE = "session.create";
/// The method a station tells the opener of a chat how one of its turns ended.
export const NOTICE = "session.notice";

/// At most this many chats an agent opened are open at once (not ended all_done): more is for a person to ask for.
export const MAX_OPEN = 8;
/// At most this much text in the first message (as session_send's).
const MAX_TEXT = 200_000;

const chars = (s: string) => Array.from(s).length;
const RUNTIMES = ["claude", "codex"] as const;
type RuntimeName = (typeof RUNTIMES)[number];

/// How a turn of an opened chat ended, as its opener is told.
export type Settled = "all_done" | "need_human" | "failed" | "stopped";

type Made = { session: string; link: string | null; thread: string };

/// A string argument, trimmed; null when left out or empty.
function given(args: Json, name: string): string | null {
  const v = args?.[name];
  if (v === undefined || v === null) return null;
  const t = jsString(v).trim();
  return t === "" ? null : t;
}

/// The key a chat is opened with: the caller's, checked.
function keyOf(args: Json): string {
  const key = given(args, "key");
  if (key === null) throw new Error("key is required: a name of your choosing for this chat (e.g. build-android); calling again with it gives the chat made then rather than another");
  if (chars(key) > 120) throw new Error("key is too long (at most 120 characters)");
  return key;
}

/// The person who started session `key`'s chat (whom a chat it opens goes to).
function starterOf(hub: Hub, key: string): string {
  let thread = null;
  try {
    thread = sessionThreadOf(hub, key).thread;
  } catch {}
  return thread?.createdBy ?? hub.store.getSession(key)?.createdBy ?? "local";
}

/// A new session in a chat of its own for an opener: its runtime, model and effort as asked; the model and effort it
/// takes after its opener's (`inherited`) are dropped where no profile here runs them.
function makeChat(hub: Hub, o: { runtime: RuntimeName; model: string | null; effort: string | null; inherited: boolean; title: string | null; createdBy: string }) {
  const options = { runtime: o.runtime, model: o.model, effort: o.effort, title: o.title, createdBy: o.createdBy };
  try {
    return newSession(hub, options);
  } catch (error) {
    if (!o.inherited || (o.model === null && o.effort === null)) throw error;
    return newSession(hub, { ...options, model: null, effort: null });
  }
}

/// Where a session's chat is, as an agent names it.
const addressOf = (thread: SessionThread) => threadAddress(thread.thread.channel, thread.thread.threadTs);

/// The station a chat is to be opened on, by its id or name in the workspace's roster; null for this one.
async function stationNamed(hub: Hub, key: string, named: string | null): Promise<string | null> {
  if (named === null) return null;
  const link = hub.link(key);
  const here = link !== undefined ? linkedStation(link) : null;
  if (named === here) return null;
  const call = hub.peers();
  if (!call) throw new Error("other stations cannot be reached from this one yet: leave station out to open the chat here");
  const roster: Json = await call("", { method: "peers" });
  const stations: Json[] = Array.isArray(roster?.stations) ? roster.stations : [];
  const lower = named.toLowerCase();
  const found = stations.find((s) => s?.id === named) ?? stations.find((s) => typeof s?.name === "string" && s.name.toLowerCase() === lower);
  if (!found || typeof found.id !== "string") {
    const names = stations.map((s) => (typeof s?.name === "string" && s.name !== "" ? s.name : s?.id)).filter((n) => typeof n === "string");
    throw new Error(`no station ${named} in this workspace${names.length > 0 ? `; its stations: ${names.join(", ")}` : ""}`);
  }
  return found.id === here ? null : found.id;
}

/// What the agent is told of a chat it opened.
function opened(made: Made, station: string | null, again: boolean): string {
  const where = station === null ? "this station" : `station ${station}`;
  const first = again ? `This key already opened ${made.link ?? made.session} (${made.thread} on ${where}); nothing new was opened or sent.` : `Opened ${made.link ?? made.session} (${made.thread} on ${where}); its agent is ${made.session}.`;
  return `${first} Each time a turn there ends all_done or need_human (or fails), you are told here: wait for it by ending your turn waiting. Write to its agent with session_send to its link; read it with chat_read.`;
}

/// Says in the opener's chat, for people, that it opened a chat (the station's words, like its notices).
async function sayOpened(hub: Hub, key: string, title: string, link: string | null) {
  const latest = hub.store.latestThread(key);
  if (!latest) return;
  const text = tr(stationLang(), "station.session.opened", { chat: chatNamed(latest.thread.surface, title, link) });
  try {
    const ts = await hub.chat(latest.connect).post({ channel: latest.thread.channel, threadTs: latest.thread.threadTs }, text, []);
    hub.store.insertMessage({ thread: latest.thread.id, ts, authorKind: "ember", author: "ember", text, attachments: [] });
  } catch (error) {
    log.warn("hub", "an opened chat was not said in its opener's", { session: key, error: (error as Error).message });
  }
}

/// chat_create from session `key`.
export async function chatCreate(hub: Hub, key: string, args: Args): Promise<string> {
  const row = hub.store.getSession(key);
  if (!row) throw new Error("unknown session");
  if (hub.store.openerOf(key) !== null) throw new Error("this chat was opened by another agent, and opens none itself: ask its opener (session_send) or a person to open more");
  const k = keyOf(args);
  const text = given(args, "text");
  if (text === null) throw new Error("text is required: the first message, what the new chat's agent is to do, standing on its own");
  if (chars(text) > MAX_TEXT) throw new Error(`text is too long (at most ${MAX_TEXT} characters): put the rest in a file and attach it`);
  const runtime = given(args, "runtime") ?? row.runtime;
  if (!RUNTIMES.includes(runtime as RuntimeName)) throw new Error(`runtime must be one of ${RUNTIMES.join(", ")}`);
  const model = given(args, "model");
  const effort = given(args, "effort");
  // Without a model of its own it runs as its opener does, where it can.
  const inherited = model === null && runtime === row.runtime;
  const choice = { runtime: runtime as RuntimeName, model: inherited ? row.model : model, effort: inherited ? (effort ?? row.effort) : effort, inherited };
  const title = given(args, "title");
  if (title !== null && chars(title) > 120) throw new Error("title is too long (at most 120 characters)");
  const paths: string[] = Array.isArray(args.files) ? args.files.map(jsString) : [];
  const files = sendable(hub, key, paths);
  const there = await stationNamed(hub, key, given(args, "station"));

  const createdBy = starterOf(hub, key);
  const [from, fromLink] = sender(hub, key);
  // Its first message here, with its files, unless it has come already.
  const sendHere = async (child: string, thread: SessionThread) => {
    if (hub.store.messagesBefore(thread.thread.id, null, 200).some((m) => m.authorKind === "agent" && m.author === key)) return;
    const kept = files.length > 0 ? attach(hub, key, files.map((f) => f.path), child) : [];
    await postFrom(hub, thread, key, from, fromLink, text, [child], kept, true);
  };

  const before = hub.store.openedWith("", key, k, there ?? "");
  if (before !== null) {
    let thread = before.child;
    if (there === null && hub.store.getSession(before.child) !== null) {
      const chat = sessionThreadOf(hub, before.child);
      await sendHere(before.child, chat);
      thread = addressOf(chat);
    }
    return opened({ session: before.child, link: before.link, thread }, there, true);
  }
  // Those still going: not ended all_done, and (here) not archived or deleted.
  const open = hub.store.openedBy(key).filter((o) => {
    if (o.state === "all_done") return false;
    if (o.childStation !== "") return true;
    const row = hub.store.getSession(o.child);
    return row !== null && row.archivedAt === null;
  });
  if (open.length >= MAX_OPEN) {
    throw new Error(`${open.length} chats you opened have not ended all_done (${open.map((o) => o.link ?? o.child).join(", ")}): finish with them, or ask a person, before opening more`);
  }

  if (there === null) {
    const [child, chat] = makeChat(hub, { ...choice, title, createdBy });
    const link = hub.link(child) ?? null;
    hub.store.insertOpened({ childStation: "", child, parentStation: "", parent: key, key: k, title, link });
    const thread: SessionThread = { thread: chat, connect: INTERNAL_CONNECT };
    await sendHere(child, thread);
    await sayOpened(hub, key, title ?? text.split("\n")[0]!.slice(0, 60), link);
    return opened({ session: child, link, thread: addressOf(thread) }, null, false);
  }

  const call = hub.peers()!;
  const request: Json = { method: CREATE, session: key, key: k, title, ...choice, createdBy, from: { title: from, link: fromLink } };
  let made: Json;
  try {
    made = await call(there, request);
  } catch (error) {
    const why = (error as Error).message;
    if (error instanceof Refused && fromBefore(why)) throw new Error(`station ${there} is not updated yet: chats cannot be opened there`);
    throw new Error(`not opened on station ${there}: ${why}. If it timed out it may have been opened: call chat_create again with the same key, which gives that chat rather than another`);
  }
  const child = typeof made?.session === "string" ? made.session : "";
  if (child === "") throw new Error(`station ${there} answered without the chat it opened`);
  const link = typeof made?.link === "string" ? made.link : null;
  const result: Made = { session: child, link, thread: typeof made?.thread === "string" ? made.thread : child };
  // Its first message, unless it already came (an earlier call with this key opened the chat and sent it).
  if (made?.said !== true) {
    try {
      const message: Json = { method: "session.message", session: key, to: child, text, from: { title: from, link: fromLink }, opened: true };
      if (files.length > 0) message.files = await sendAlong(call, there, key, child, files);
      await call(there, message);
    } catch (error) {
      throw new Error(`opened ${link ?? child} on station ${there}, but its first message was not sent: ${(error as Error).message}. Call chat_create again with the same key: it sends it once, if it has not arrived`);
    }
  }
  hub.store.insertOpened({ childStation: there, child, parentStation: "", parent: key, key: k, title, link });
  await sayOpened(hub, key, title ?? text.split("\n")[0]!.slice(0, 60), link);
  return opened(result, there, false);
}

/// A chat another station's session opens here (chat_create there, from station `peer`): made once per its key; the
/// answer says whether its first message has come yet.
export function createForPeer(hub: Hub, peer: string, request: Json): Json {
  const parent = typeof request?.session === "string" ? request.session : "";
  if (parent === "") throw new Error("session is required");
  const k = keyOf(request);
  const before = hub.store.openedWith(peer, parent, k, "");
  const answer = (child: string): Json => {
    const thread = sessionThreadOf(hub, child);
    const said = hub.store.messagesBefore(thread.thread.id, null, 200).some((m) => m.author === `${peer}/${parent}`);
    return { session: child, link: hub.link(child) ?? null, thread: addressOf(thread), said };
  };
  if (before !== null && hub.store.getSession(before.child) !== null) return answer(before.child);
  if (before !== null) throw new Error(`the chat key ${k} opened here is gone (deleted): use another key`);
  const runtime = typeof request?.runtime === "string" ? request.runtime : "";
  if (!RUNTIMES.includes(runtime as RuntimeName)) throw new Error(`runtime must be one of ${RUNTIMES.join(", ")}`);
  const title = given(request, "title");
  const createdBy = given(request, "createdBy") ?? `${peer}/${parent}`;
  const [child] = makeChat(hub, { runtime: runtime as RuntimeName, model: given(request, "model"), effort: given(request, "effort"), inherited: request?.inherited === true, title, createdBy });
  hub.store.insertOpened({ childStation: "", child, parentStation: peer, parent, key: k, title, link: hub.link(child) ?? null });
  log.info("hub", "chat opened for another station's session", { session: child, station: peer, opener: parent });
  return answer(child);
}

/// What an opener is told of a turn of a chat it opened.
function notice(title: string, link: string | null, state: Settled, words: string | null): string {
  const chat = link !== null ? `"${title}" (${link})` : `"${title}"`;
  const said = words !== null && words !== "" ? `: ${words}` : "";
  const ended =
    state === "need_human" ? `needs a person${said}. They are asked there; help if you can, or wait`
    : state === "failed" ? `stopped with an error${said}`
    : state === "stopped" ? "was stopped by a person"
    : `ended its turn all_done${said}`;
  return `The chat you opened, ${chat}, ${ended}. Read it with chat_read; write to its agent with session_send to its link.`;
}

/// A turn of session `key` ended: its opener, if an agent opened its chat, is told how (on this station or its own).
export function settled(hub: Hub, key: string, state: Settled, words: string | null) {
  const opener = hub.store.openerOf(key);
  if (opener === null) return;
  const [title, link] = sender(hub, key);
  if (opener.parentStation === "") {
    hub.store.setOpenedState("", key, state);
    try {
      hub.notify(opener.parent, notice(title, link, state, words));
    } catch (error) {
      log.warn("hub", "the opener of a chat was not told", { session: key, opener: opener.parent, error: (error as Error).message });
    }
    return;
  }
  const call = hub.peers();
  const tell = async () => {
    if (!call) throw new Error("other stations cannot be reached from this one yet");
    await call(opener.parentStation, { method: NOTICE, session: key, to: opener.parent, state, words, title });
  };
  // Not sent again: said in the chat instead, where its people (and the opener, reading it) see it.
  tell().catch(async (error) => {
    log.warn("hub", "the opener of a chat on another station was not told", { session: key, station: opener.parentStation, error: (error as Error).message });
    const latest = hub.store.latestThread(key);
    if (!latest) return;
    const text = tr(stationLang(), "station.session.openerNotTold", { error: (error as Error).message });
    try {
      const ts = await hub.chat(latest.connect).post({ channel: latest.thread.channel, threadTs: latest.thread.threadTs }, text, []);
      hub.store.insertMessage({ thread: latest.thread.id, ts, authorKind: "ember", author: "ember", text, attachments: [] });
    } catch {}
  });
}

/// How a turn of a chat this station's session opened on station `peer` ended (`settled` there).
export function noticeForPeer(hub: Hub, peer: string, request: Json): Json {
  const child = typeof request?.session === "string" ? request.session : "";
  const parent = typeof request?.to === "string" ? request.to : "";
  const state = request?.state;
  if (!["all_done", "need_human", "failed", "stopped"].includes(state)) throw new Error("state must be all_done, need_human, failed or stopped");
  const record = hub.store.openedBy(parent).find((o) => o.childStation === peer && o.child === child);
  if (!record) throw new Error(`${parent} opened no chat ${child} on that station`);
  hub.store.setOpenedState(peer, child, state);
  const title = given(request, "title") ?? record.title ?? child;
  hub.notify(parent, notice(title, record.link, state, given(request, "words")));
  return { told: true };
}
