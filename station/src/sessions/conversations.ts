// What agents do in their own conversations (the Rust station's hub.rs: chat_post, chat_state, chat_history, slack_api and
// what they rest on): post (with files and a card, ending the turn or not), record how the turn ends, read a thread,
// and call Slack as their bot. What a tool says of the turn reaches its session's actor, in turn with the rest.
import { fetchFiles, keyPart, sandboxed, stationPath } from "../agents/sandbox.ts";
import { mkdirSync, rmSync } from "node:fs";
import { copyFile, stat } from "node:fs/promises";
import { basename, dirname, isAbsolute, join } from "node:path";
import { PlaceRefused } from "../ops/places.ts";
import { formatHistory, parseThreadAddress, threadAddress } from "../agents/instructions.ts";
import { log } from "../ops/log.ts";
import { iso } from "../read/transcript.ts";
import { type Attachment, STILLFAIL_SURFACE, type SessionThread, type ThreadRow } from "../store/store.ts";
import type { DeclaredState } from "./actor.ts";
import {
  type Args,
  MAX_WAIT_SECONDS,
  MIN_WAIT_SECONDS,
  WRITES,
  aboutTs,
  cardArg,
  cardSaid,
  declaredStr,
  firstLine,
  isSlackMethod,
  jsNumber,
  jsString,
  needArg,
  placeFigures,
  saidAs,
  slackWithFiles,
  stateArg,
} from "./args.ts";
import { type ChatSurface, callApi } from "./chat.ts";
import type { Hub } from "./hub.ts";
import { shownFacts } from "./image-size.ts";
import { dir as thumbsDir, keep } from "../drive/thumbs.ts";
import { INTERNAL_CONNECT } from "./internal.ts";
import { namedLocalPaths, prepare } from "./local-links.ts";
import { suggestArchive } from "./review.ts";
import { nameChat } from "./titles.ts";

type Json = any;

/// What a tool says of the running turn, given to the session's actor (when it has one), recorded in turn order.
const actorOf = (hub: Hub, key: string) => hub.actors.get(key);

/// A thread of this session the agent named with to=, and how the session posts there.
export function target(hub: Hub, key: string, to: Json): SessionThread {
  if (hub.store.getSession(key) === null) throw new Error("unknown session");
  const known = () => {
    const threads = hub.store.sessionThreads(key).map((t) => threadAddress(t.thread.channel, t.thread.threadTs));
    return threads.length === 0 ? "none yet" : threads.join(", ");
  };
  if (typeof to !== "string" || to.trim() === "") throw new Error(`to is required: the thread attribute of the message you are answering. This session's threads: ${known()}`);
  const address = parseThreadAddress(to);
  if (!address) throw new Error(`to must look like CHANNEL/THREAD_TS, got ${JSON.stringify(to)}`);
  const thread = hub.store.sessionThread(key, address[0], address[1]);
  if (!thread) throw new Error(`${to} is not a conversation of this session. Its threads: ${known()}`);
  return thread;
}

/// The most a file an agent attaches is (attach, peer-files.ts MAX_SENT).
const MOST_ATTACHED = 50 * 1024 * 1024;

/// While the station runs things in sandboxes (agents/sandbox.ts): a message's files (`files`, and with `links` the
/// local links in `text`) named as the station names them (not by where the data directory's link leads in the
/// sandbox), and brought here from the session's sandbox when only it has them, before anything here looks for them.
export async function fromSandbox(hub: Hub, key: string, args: Args, links: boolean): Promise<Args> {
  const data = hub.config().dataDir;
  const row = hub.store.getSession(key);
  if (!row || !sandboxed(data)) return args;
  const full = (given: string) => stationPath(data, isAbsolute(given) ? given : join(row.workspace, given));
  let next = args;
  const wanted: string[] = [];
  if (Array.isArray(args.files)) {
    const files = args.files.map((f) => full(jsString(f)));
    wanted.push(...files);
    next = { ...next, files };
  }
  if (links && typeof args.text === "string") {
    let text = args.text;
    for (const { destination, path } of namedLocalPaths(text)) {
      const station = stationPath(data, path);
      wanted.push(station);
      if (station !== path) text = text.split(`](<${destination}>`).join(`](<${station}>`).split(`](${destination}`).join(`](${station.includes(" ") ? `<${station}>` : station}`);
    }
    next = { ...next, text };
  }
  await fetchFiles(data, keyPart(key), wanted);
  return next;
}

/// Whether `staged` may have something to copy: files named, or (with `links`) a local link into a folder macOS
/// protects, on a Mac.
export function mayStage(hub: Hub, args: Args, links: boolean): boolean {
  if (!hub.places.mac) return false;
  if (Array.isArray(args.files) && args.files.length > 0) return true;
  return links && typeof args.text === "string" && namedLocalPaths(args.text).some(({ path }) => hub.places.protects(path));
}

/// Files an agent names for a message (`files`, and with `links` the local links in `text`) that are in a folder macOS
/// protects, copied into the session's uploads first (through still.fail Helper, else off the station's thread:
/// ops/places.ts), so that what reads them next (attach, prepare, sendable) never touches such a folder on the
/// station's thread. The arguments to go on with, and what removes the copies once the message is sent. A grant the
/// helper lacks refuses it, its window put up on the Mac, telling the agent to ask with the permissions tool.
export async function staged(hub: Hub, key: string, args: Args, links: boolean): Promise<{ args: Args; done: () => void }> {
  const row = hub.store.getSession(key);
  const places = hub.places;
  const copies: string[] = [];
  const done = () => {
    for (const c of copies) rmSync(dirname(c), { recursive: true, force: true });
  };
  if (!row || (!Array.isArray(args.files) && !(links && typeof args.text === "string"))) return { args, done };
  const into = join(row.workspace, "uploads");
  const asker = { lang: "en" as const, agent: true };
  const take = async (path: string): Promise<string> => {
    const copy = await places.file(path, into, asker, MOST_ATTACHED);
    if (copy !== path) copies.push(copy);
    return copy;
  };
  try {
    let next: Args = args;
    if (Array.isArray(args.files)) {
      const files: Json[] = [];
      for (const f of args.files) {
        const given = jsString(f);
        const full = isAbsolute(given) ? given : join(row.workspace, given);
        const copy = await take(full);
        files.push(copy === full ? given : copy);
      }
      next = { ...next, files };
    }
    if (links && typeof args.text === "string") {
      let text = args.text;
      for (const { destination, path } of namedLocalPaths(text)) {
        if (!places.protects(path)) continue;
        // Codex's /path/file.rs:12 names the file without its line.
        const line = /:[0-9]+(:[0-9]+)?$/.exec(path);
        let copy: string;
        try {
          copy = await take(path);
        } catch (e) {
          if (line === null || !(e instanceof PlaceRefused) || e.code !== "gone") throw e;
          copy = await take(path.slice(0, line.index));
        }
        const as = copy.includes(" ") ? `<${copy}>` : copy;
        text = text.split(`](<${destination}>`).join(`](${as}`).split(`](${destination}`).join(`](${as}`);
      }
      next = { ...next, text };
    }
    return { args: next, done };
  } catch (e) {
    done();
    throw e;
  }
}

/// Copies files the agent attaches into the session's uploads (`into`'s, when it sends them to that session), so the
/// message keeps them even if the originals change, and measures images so pages can hold their place. Ones that are
/// only in the session's sandbox (its agent runs there, agents/sandbox.ts) are brought here first.
export async function attach(hub: Hub, key: string, paths: string[], into: string = key): Promise<Attachment[]> {
  const row = hub.store.getSession(key);
  const target = into === key ? row : hub.store.getSession(into);
  if (!row || !target) throw new Error("unknown session");
  if (paths.length > 10) throw new Error("at most 10 files per message");
  const data = hub.config().dataDir;
  if (sandboxed(data)) {
    // Named as the agent sees them there, and brought here from there when only it has them.
    paths = paths.map((given) => stationPath(data, isAbsolute(given) ? given : join(row.workspace, given)));
    await fetchFiles(data, keyPart(key), paths);
  }
  const dir = join(target.workspace, "uploads");
  mkdirSync(dir, { recursive: true });
  // Copied off the station's thread: a large file, or one read back from disk on a machine short of memory, held it
  // for up to 10 seconds a post (ccvm, 2026-10-28).
  const out: Attachment[] = [];
  for (const given of paths) {
    const path = isAbsolute(given) ? given : join(row.workspace, given);
    let meta;
    try {
      meta = await stat(path);
    } catch {
      throw new Error(sandboxed(hub.config().dataDir) ? `no such file, here or in this session's sandbox: ${given}` : `no such file: ${given}`);
    }
    if (!meta.isFile()) throw new Error(`not a file: ${given}`);
    if (meta.size > 50 * 1024 * 1024) throw new Error(`too large (over 50 MB): ${given}`);
    const name = basename(path);
    const stamp = iso(hub.now()).slice(0, 19).replace(/[:.]/g, "-");
    const safe = Array.from(name)
      .map((c) => (c === "\\" || c === "/" || c.codePointAt(0)! < 0x20 ? "_" : c))
      .join("");
    const copy = join(dir, `${stamp}-${safe}`);
    await copyFile(path, copy);
    // a picture or a film as it is shown, so pages hold its place (a film's length and frames with it)
    out.push({ name, path: copy, size: meta.size, ...shownFacts(copy) } satisfies Attachment);
  }
  return out;
}

/// chat_post: a message to one of the session's conversations, maybe with files and a card, maybe ending its turn.
export async function chatPost(hub: Hub, key: string, args: Args): Promise<string> {
  const { store } = hub;
  if (args.withdraw !== undefined) {
    if (Object.keys(args).some((k) => k !== "to" && k !== "withdraw")) throw new Error("withdraw uses only to and withdraw; post updates and record your ending separately");
    const ts = typeof args.withdraw === "string" && args.withdraw.trim() !== "" ? args.withdraw : null;
    if (ts === null) throw new Error("withdraw must be your question's message ts");
    const thread = target(hub, key, args.to);
    if (!store.withdrawCard(key, thread.thread.id, ts)) throw new Error("withdraw must name your own message with a card in this conversation");
    return "Withdrew the answer card; its message is kept. Continue your work and record the appropriate ending state.";
  }
  let text = args.text === undefined ? "" : jsString(args.text).trim();
  const paths: string[] = Array.isArray(args.files) ? args.files.map(jsString) : [];
  const given = stateArg(args.kind);
  const card = cardArg(args.card, args.options);
  // need_decision, as said before cards: a post with a card that ends the turn need_help.
  if (given?.[1] === "decision" && card === null) {
    throw new Error('need_decision carries options: a card {"type": "options", "options": [...]} people pick from (or end with kind "need_human" and say in need what they have to decide)');
  }
  const kind = given?.[0] ?? null;
  let need = given ? needArg(args, given[0], given[1]) : needArg(args, { kind: "waiting", seconds: 0 }, "now");
  // Without a need of its own, a decision asked in the words from before needs what its post asks: its first line.
  if (need === null && given && given[0].kind === "need_help" && given[1] !== "now" && card !== null) {
    const line = firstLine(text);
    if (line !== "") need = line;
  }
  if (kind === null && args.about !== undefined && args.about !== null) throw new Error("about goes with kind: the message the state this post records is about");
  if (text === "" && paths.length === 0) throw new Error("text is empty");
  const thread = target(hub, key, args.to);
  if (store.manuallyArchived(thread.thread.id)) throw new Error(`${threadAddress(thread.thread.channel, thread.thread.threadTs)} was archived by hand: it takes no messages until someone restores it`);
  const chat = hub.chat(thread.connect);
  if (card !== null && thread.thread.surface !== STILLFAIL_SURFACE && !(chat.cards === true && (card.type === "options" || card.type === "text"))) {
    throw new Error(
      chat.cards === true
        ? 'a login card is shown only in still.fail chats (EMBER/…); here post its link in the text and end with kind "need_human"'
        : 'cards (options, a text field) are not shown here; write the choices or the question in the text and end with kind "need_human"',
    );
  }
  if (card !== null && text === "") throw new Error("text is required with a card: what it asks and the facts it turns on, so it can be answered from this message alone");
  let about: [number, number, string] | null = null;
  const ts = aboutTs(args);
  if (ts !== null) {
    const m = store.messageAt(thread.thread.id, ts);
    if (!m) throw new Error(`about must be the ts of a message in ${threadAddress(thread.thread.channel, thread.thread.threadTs)} (or leave it out), got ${ts}`);
    about = [m.thread, m.n, m.ts];
  }
  // Slack gets the files in the thread below the text. An app made before it could upload (no files:write) links to
  // them in still.fail instead.
  if (thread.thread.surface === STILLFAIL_SURFACE) {
    const row = store.getSession(key);
    if (!row) throw new Error("unknown session");
    text = prepare(text, paths, row.workspace);
  }
  const slack = thread.thread.surface !== STILLFAIL_SURFACE && paths.length > 0;
  const link = () => {
    const link = hub.link(key);
    if (link === undefined) throw new Error("files cannot be shown from Slack until this station is in a still.fail workspace; mention their paths in the text instead");
    return link;
  };
  const files = await keep(paths.length === 0 ? [] : await attach(hub, key, paths), thumbsDir(hub.config().dataDir));
  const here = { channel: thread.thread.channel, threadTs: thread.thread.threadTs };
  let posted: string;
  // A chat's first post where it was relayed goes into the station's first message there (relay.ts).
  const opening = card === null && files.length === 0 ? await intoOpening(hub, key, chat, thread.thread, text) : null;
  let n: number;
  if (opening !== null) [posted, n] = opening;
  else {
    if (slack) {
      try {
        posted = await chat.post(here, text, files, card);
        text = placeFigures(text, files);
      } catch (error) {
        if (!String((error as Error).message).includes("missing_scope")) throw error;
        const [sent, kept] = slackWithFiles(text, files, link());
        posted = await chat.post(here, sent, []);
        text = kept;
      }
    } else posted = await chat.post(here, text, files, card);
    [n] = store.insertMessage({ thread: thread.thread.id, ts: posted, authorKind: "agent", author: key, text, attachments: files, declared: kind ? declaredStr(kind) : null, card });
  }
  const offered = card !== null ? cardSaid(card) : "";
  hub.shared(thread.thread.id, n, key, text);
  const actor = actorOf(hub, key);
  await actor?.postedNow();
  if (need !== null) await actor?.need(need);
  if (kind !== null) {
    // What the state is about: as said, else for need_help the card still pending in this chat (this post's, when it
    // carries one).
    if (about === null && kind.kind === "need_help") {
      const pending = store.pendingCard(thread.thread.id);
      if (pending) about = [pending[0].thread, pending[0].n, pending[0].ts];
    }
    await actor?.about(about);
    await actor?.declare(kind);
  }
  const titled = typeof args.title === "string" ? nameChat(hub, thread.thread, args.title) : "";
  const place = threadAddress(thread.thread.channel, thread.thread.threadTs) + (opening !== null ? ` (added to the station's first message there, ts ${posted})` : "");
  const crossed = unreadBefore(hub, key, thread.thread.id, n);
  return kind !== null ? `Posted to ${place}, and recorded state ${saidAs(kind)}.${crossed}${titled}${offered}` : `Posted to ${place}.${crossed}${titled}${offered}`;
}

/// Messages said in the thread before the agent's post (entry `n`) that it had not read when it wrote it, as the post's
/// result says them: they come to it next, written without seeing the post. Empty when none.
function unreadBefore(hub: Hub, key: string, thread: number, n: number): string {
  const pending = hub.store.pendingMessages(key).filter((m) => m.message.apart !== true && m.message.thread === thread && m.message.n < n);
  const unread = [...pending, ...(actorOf(hub, key)?.unreadIn(thread, n) ?? [])];
  const ts = [...new Set(unread.map((m) => m.message.ts))];
  if (ts.length === 0) return "";
  const one = ts.length === 1;
  return ` Before this post went up, ${one ? "a message" : "messages"} you had not read yet came in this thread (ts ${ts.join(", ")}): written without seeing your post, ${one ? "it comes" : "they come"} to you next.`;
}

/// The agent's first post in a conversation its chat was relayed to (hub.openings): added under the station's first
/// message there, which is what people see without opening the thread. That message's ts and number, or null where it
/// is posted as a reply: not the first post, not the relaying agent's, too long to go into one message, or not changed.
async function intoOpening(hub: Hub, key: string, chat: ChatSurface, thread: ThreadRow, text: string): Promise<[string, number] | null> {
  const pending = hub.openings.get(thread.id);
  if (pending === undefined || pending.session !== key) return null;
  hub.openings.delete(thread.id);
  const opening = hub.store.messageAt(thread.id, pending.ts);
  if (opening === null || chat.edit === undefined) return null;
  const whole = `${opening.text}\n\n${text}`;
  try {
    if (!(await chat.edit({ channel: thread.channel, threadTs: thread.threadTs }, pending.ts, whole))) return null;
  } catch (error) {
    log.warn("hub", "a relayed chat's first post did not go into the station's first message", { thread: thread.id, error: (error as Error).message });
    return null;
  }
  hub.store.editMessage(thread.surface, thread.channel, thread.threadTs, pending.ts, whole);
  return [pending.ts, opening.n];
}

/// What a state recorded with chat_state is about: the message `about` names (by its ts, in one of the session's
/// threads); else for need_help, the card still pending in its chats (the latest, if several).
function stateAbout(hub: Hub, key: string, kind: DeclaredState, args: Args): [number, number, string] | null {
  const threads = hub.store.sessionThreads(key);
  const ts = aboutTs(args);
  if (ts !== null) {
    for (const t of threads) {
      const m = hub.store.messageAt(t.thread.id, ts);
      if (!m) continue;
      if (kind.kind === "need_help" && (m.authorKind !== "agent" || m.author !== key || m.text.trim() === "")) {
        throw new Error("need_human about must point to your visible question, not a person's message or another agent's post");
      }
      return [m.thread, m.n, m.ts];
    }
    throw new Error(`about must be the ts of a message in one of your conversations (or leave it out), got ${ts}`);
  }
  if (kind.kind !== "need_help") return null;
  const pending = threads.flatMap((t) => hub.store.pendingCard(t.thread.id)?.[0] ?? []);
  // A stable sort by when, the latest last.
  pending.sort((a, b) => a.createdAt - b.createdAt);
  const last = pending.at(-1);
  return last ? [last.thread, last.n, last.ts] : null;
}

/// chat_state: how this turn ends, recorded without posting.
export async function chatState(hub: Hub, key: string, args: Args): Promise<string> {
  // Checked whole before anything is recorded: its words (what it waits for, needs, ends with) and what it is about.
  let kind: DeclaredState;
  let words: string | null;
  let watch = false;
  if (args.kind === "waiting") {
    const seconds = args.seconds === undefined ? null : jsNumber(args.seconds);
    if (seconds === null) throw new Error("seconds is required for waiting: how long until the work brings you back");
    const what = args.for === undefined ? "" : jsString(args.for).trim();
    if (what === "") throw new Error("for is required for waiting: what you wait for, in a few words people read");
    if (args.watch !== undefined && typeof args.watch !== "boolean") throw new Error("watch must be true or false");
    watch = args.watch === true;
    if (watch && !hub.store.listJobs(key).some((j) => j.watch && j.state === "running")) {
      throw new Error("watch: true is for waiting on a watch of yours that runs (job_start with watch); none does: leave it out, or start the watch first");
    }
    const whole = Number.isNaN(seconds) ? 0 : Math.trunc(Math.max(0, seconds));
    kind = { kind: "waiting", seconds: Math.min(MAX_WAIT_SECONDS, Math.max(MIN_WAIT_SECONDS, whole)) };
    words = what;
  } else {
    const given = stateArg(args.kind);
    if (given === null) throw new Error("kind is required");
    if (given[1] === "decision") throw new Error("need_decision is posted with chat_post: the question in the text, its options in a card; then the turn ends need_human");
    kind = given[0];
    words = needArg(args, given[0], given[1]);
  }
  const about = stateAbout(hub, key, kind, args);
  if (kind.kind === "need_help" && about === null && args.kind !== "block") {
    throw new Error(
      "need_human requires a visible question: post what you need with chat_post kind=need_human, or give about pointing to your question (a pending answer card is used by default). need alone is not a message to the person",
    );
  }
  const actor = actorOf(hub, key);
  if (words !== null) {
    if (kind.kind === "waiting") await actor?.waitFor(words, watch);
    else await actor?.need(words);
  }
  await actor?.about(about);
  await actor?.declare(kind);
  if (kind.kind === "all_done") suggestArchive(hub, key);
  if (kind.kind !== "waiting") return `Recorded state ${saidAs(kind)}.`;
  return watch
    ? "Recorded state waiting on your watch: its notices, its end or a message bring you back."
    : `Recorded state waiting: you are asked again in ${kind.seconds} seconds unless something brings you back first.`;
}

/// chat_history: earlier messages of one of the session's conversations.
export async function chatHistory(hub: Hub, key: string, args: Args): Promise<string> {
  const thread = target(hub, key, args.to);
  const to = args.to === undefined ? "" : jsString(args.to);
  return threadHistory(hub, key, thread.thread, thread.connect, to, args);
}

/// A thread's messages as chat_history and chat_read give them: `before` (a message ts) and `limit` from `args`,
/// people named through `connect`, `key`'s own posts as "you". `named`: the thread as the agent named it. `seen` gets the
/// attachments of the messages given.
export async function threadHistory(hub: Hub, key: string, thread: ThreadRow, connect: string, named: string, args: Args, seen?: Attachment[]): Promise<string> {
  const given = args.limit === undefined ? null : jsNumber(args.limit);
  const limit = given !== null && given !== 0 ? (Number.isNaN(given) ? 0 : Math.trunc(Math.min(200, Math.max(1, given)))) : 30;
  const before = typeof args.before === "string" && args.before !== "" ? args.before : null;
  let from: number | null = null;
  if (before !== null) {
    const m = hub.store.messageAt(thread.id, before);
    if (!m) throw new Error(`no message ${before} in ${named}`);
    from = m.n;
  }
  const messages = hub.store.messagesBefore(thread.id, from, limit);
  if (messages.length === 0) return "No earlier messages.";
  seen?.push(...messages.flatMap((m) => m.attachments));
  const chat = hub.chatOf(connect);
  const names = new Map<string, string>();
  for (const m of messages.filter((m) => m.authorKind === "person")) {
    if (names.has(m.author)) continue;
    const name = (await chat?.userName?.(m.author)) ?? null;
    if (name !== null) names.set(m.author, name);
  }
  return formatHistory(messages, thread.surface, threadAddress(thread.channel, thread.threadTs), key, names);
}

/// The Slack connect a session calls as when it names none: its own, or (a still.fail chat) the station's Slack bot in its
/// workspace, `bot` naming one by its id or bot name; with several and no name, the one bound to the session's runtime.
export function slackConnectOf(hub: Hub, key: string, bot: string | null): string {
  const session = hub.store.getSession(key);
  const own = session?.connect ?? null;
  if (bot === null && own !== null && own !== INTERNAL_CONNECT) return own;
  const home = hub.workspaces()[0] ?? null;
  const ws = hub.wsOf(session ?? key);
  const bots = hub
    .config()
    .connects.filter((c) => c.kind === "slack" && c.enabled && (c.workspace ?? home) === ws && hub.chatOf(c.id) !== undefined);
  const named = (c: (typeof bots)[number]) => (c.slack.botName ? `${c.id} (${c.slack.botName})` : c.id);
  if (bot !== null) {
    const wanted = bot.trim().toLowerCase();
    const found = bots.find((c) => c.id.toLowerCase() === wanted || c.slack.botName?.toLowerCase() === wanted);
    if (!found) throw new Error(`no Slack bot ${JSON.stringify(bot)} here; bot is one of: ${bots.map(named).join(", ") || "none"}`);
    return found.id;
  }
  if (bots.length === 1) return bots[0].id;
  const runtime = session?.runtime ?? null;
  const bound = bots.filter((c) => c.bind.runtime === runtime);
  if (bound.length === 1) return bound[0].id;
  if (bots.length === 0) throw new Error("this station has no Slack bot in this chat's workspace");
  throw new Error(`this chat has no Slack bot of its own: give bot= one of: ${bots.map(named).join(", ")}`);
}

/// slack_api: a Slack Web API call from session `key`, as the bot of `via` (else `slackConnectOf`). Writes keep to the
/// threads rule: not in a thread another session of the same bot takes part in; one it writes in becomes its own.
export async function slackApi(hub: Hub, key: string, method: string, params: Record<string, Json>, via: string | null, bot: string | null = null): Promise<string> {
  const { store } = hub;
  if (!isSlackMethod(method)) throw new Error(`not a Slack method: ${JSON.stringify(method)}`);
  if (["admin.", "apps.", "oauth."].some((p) => method.startsWith(p)) || method === "auth.revoke") throw new Error(`${method} is not for agents: it manages the Slack app itself`);
  const connect = via ?? slackConnectOf(hub, key, bot);
  const chat = hub.chat(connect);
  const textOf = (name: string): string | null => (typeof params[name] === "string" ? params[name] : null);
  const channel = textOf("channel") ?? textOf("channel_id");
  const surface = hub.surface(connect);
  // A write lands in a thread: the one named, the one its message is in, or (a new message) the one it starts.
  const write = WRITES.some((w) => method.startsWith(w));
  const named = textOf("thread_ts");
  const about = textOf("ts") ?? textOf("timestamp");
  let threadTs: string | null = null;
  if (write && channel !== null) {
    threadTs = named ?? (about !== null ? (store.threadOfMessage(surface, channel, about)?.threadTs ?? about) : null);
    const known = threadTs !== null ? store.threadAt(surface, channel, threadTs) : null;
    // Another session of the same bot there: the thread is its (other bots' sessions keep to their own).
    if (known && store.threadSessions(known.id).some((m) => m.session !== key && m.connect === connect)) {
      throw new Error(`${channel}/${threadTs ?? ""} is another session's conversation: this session cannot write there`);
    }
  }
  const postedText = textOf("text") ?? "";
  const result = await callApi(chat, method, params);
  if (write && channel !== null) {
    // Its thread is the session's now: a new message starts one.
    const resultTs = typeof result?.ts === "string" ? (result.ts as string) : null;
    const root = threadTs ?? resultTs;
    if (root !== null) {
      const thread = store.openThread(surface, channel, root, null, key);
      if (store.joinThread(thread.id, key, connect)) log.info("hub", "session took part in a thread through slack_api", { session: key, channel, threadTs: root, method });
      if (resultTs !== null && method === "chat.postMessage") {
        const [n] = store.insertMessage({ thread: thread.id, ts: resultTs, authorKind: "agent", author: key, text: postedText });
        hub.shared(thread.id, n, key, postedText);
      }
    }
  }
  const text = JSON.stringify(result);
  const chars = Array.from(text);
  return chars.length > 60_000 ? `${chars.slice(0, 60_000).join("")}… (cut at 60000 characters; ask for less, e.g. a smaller limit)` : text;
}
