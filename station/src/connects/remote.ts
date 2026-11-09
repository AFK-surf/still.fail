// A connect is its workspace's: a chat of it may run on any station of the workspace. The connect itself (its link to
// its platform, its config.json entry and tokens) runs on one station, the one it was added on or moved to by hand
// (`connect.take`), and nowhere else: while that station is off, so is the connect. That station
// - takes every event of its platform, and hands one to the station a chat of its thread runs on (`connect.event`): a
//   thread it handed on before (the threads table, `connect_threads`), or a new conversation, which starts on the station
//   the connect's `station` names (absent: this one);
// - does for the chats of other stations what their surface asks (`connect.call`): posts and cards, the status lines,
//   files both ways, names, the platform's API.
// A connect is known across the workspace by its id on the station it was added on (its origin) and that station:
// there as its id, on every other station as `<id>@<origin>` (localOf), wherever it runs since. A station a chat of it runs
// on and that does not run it has it as a connect of its hub's (as config.json's are, `connects()`) whose surface is a
// RemoteSurface asking the station it runs on, and whose people and channels go into its own names books; one it was
// moved to has it in config.json under that same id. So a chat's session, and the thread it is in, keep the connect's
// id as the connect moves. A Comma connect's Tasks run where the connect is (its protocol keeps them in its station's
// store), as does a single-session connect's one session.
import { randomUUID } from "node:crypto";
import { mkdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from "node:fs";
import { open } from "node:fs/promises";
import { basename, join } from "node:path";
import { type Bytes, bytesOf, withBytes } from "../mesh/bus.ts";
import { fileBytes, oneBytes, writeBytes } from "../mesh/files.ts";
import { log } from "../ops/log.ts";
import type { ChatEvent, ChatMessage, ChatSurface, InboundFile, Member, Person, Place, ThreadRef } from "../sessions/chat.ts";
import type { Connect, ConnectKind, ConnectMode } from "../sessions/config.ts";
import type { Attachment } from "../store/rows.ts";
import type { CardEnd } from "./card-ends.ts";
import type { BotIdentity } from "./connections.ts";
import { REMOTE_FILE, channelKey, personKey } from "./keys.ts";
import type { NameBook } from "./names.ts";

type Json = any;

/// What a station asks of the station a connect runs on: an event of its platform for a chat here; a call of a chat's
/// surface there; a connect moved here.
export const EVENT = "connect.event";
export const CALL = "connect.call";
export const TAKE = "connect.take";
/// A connect moved: the station it runs on now, told to the workspace's others.
export const MOVED = "connect.moved";
/// The connects a station runs, as another of the workspace asks before one is added (one connect, one station).
export const LIST = "connect.list";

/// The kinds whose chats run on other stations: Slack's and Feishu's. A Comma connect's Tasks stay where it is.
export const ROUTED: readonly ConnectKind[] = ["slack", "feishu"];

/// A connect as the workspace knows it: its id where it was added, and that station.
export type Known = { id: string; origin: string };

/// The connect's id on station `here`.
export const localOf = (c: Known, here: string) => (c.origin === here ? c.id : `${c.id}@${c.origin}`);
/// The connect an id of station `here` names (one of its own adding has no `@`: connect ids are slugs).
export function knownOf(id: string, here: string): Known {
  const at = id.lastIndexOf("@");
  return at > 0 && at < id.length - 1 ? { id: id.slice(0, at), origin: id.slice(at + 1) } : { id, origin: here };
}
/// The connect a request names.
export const knownIn = (v: Json): Known | null => (typeof v?.id === "string" && v.id !== "" && typeof v?.origin === "string" && v.origin !== "" ? { id: v.id, origin: v.origin } : null);

/// A connect as the station it runs on describes it to one a chat of it runs on: what its hub reads of it (config.json's
/// entry, its tokens left out), and what its surface says without being asked (its bot, its platform, how it mentions
/// and links).
export type Described = {
  kind: ConnectKind;
  /// The still.fail workspace its chats are of.
  workspace: string;
  mode: ConnectMode;
  requireMention: boolean;
  botNameSaid?: string;
  bind: { runtime: string; model?: string; effort?: string };
  botUserId: string;
  botName: string;
  identity: BotIdentity | null;
  platform: string | null;
  /// The platform's workspace (Slack's team), as its surface says (`workspace()`).
  team: string | null;
  cards: boolean;
  loginCards: boolean;
  /// How a person is mentioned: what goes before their id and after it.
  mention: [string, string];
  /// How a new session's link is said, `\u0001` its address and `\u0002` its label; null: it is not said.
  link: string | null;
  /// The surface's calls it has, of those it may not (ChatSurface's optional ones).
  has: string[];
};

/// The optional calls of a surface a remote one has only where the connect's has them (the hub tells by their absence).
const OPTIONAL = ["cardEnded", "download", "userName", "working", "standsAt", "api", "userEmail", "userOf", "channelName", "places", "peopleIn", "begin", "edit", "history"] as const;
/// What a station a chat runs on may call of a connect's surface here: those, and the names of people and channels.
const CALLS = new Set<string>(["post", "person", "channel", ...OPTIONAL]);

/// `surface` of `connect` (config.json's entry, as the hub reads it), as it is described to another station.
export function describe(connect: Connect, workspace: string, surface: ChatSurface): Described {
  const mention = surface.mention?.("\u0001") ?? "<@\u0001>";
  const at = mention.indexOf("\u0001");
  return {
    kind: connect.kind,
    workspace,
    mode: connect.mode,
    requireMention: connect.requireMention,
    ...(connect.slack.botName ? { botNameSaid: connect.slack.botName } : {}),
    bind: { runtime: connect.bind.runtime, ...(connect.bind.model ? { model: connect.bind.model } : {}), ...(connect.bind.effort ? { effort: connect.bind.effort } : {}) },
    botUserId: surface.botUserId(),
    botName: surface.botName?.() ?? "",
    identity: surface.identity?.() ?? null,
    platform: surface.platform?.() ?? null,
    team: surface.workspace(),
    cards: surface.cards === true,
    loginCards: surface.loginCards === true,
    mention: at < 0 ? ["<@", ">"] : [mention.slice(0, at), mention.slice(at + 1)],
    link: surface.sessionLink ? surface.sessionLink("\u0001", "\u0002") : "<\u0001|\u0002>",
    has: OPTIONAL.filter((name) => typeof (surface as any)[name] === "function"),
  };
}

/// A described connect as the hub of a station its chats run on reads it (sessions/config.ts `Connect`): no profile of its
/// own (its station's are not this one's), its runtime and model as there.
export function connectOf(id: string, d: Described): Connect {
  return {
    id,
    kind: d.kind,
    enabled: true,
    mode: d.mode,
    requireMention: d.requireMention,
    slack: { botName: d.botNameSaid },
    bind: { runtime: d.bind.runtime as Connect["bind"]["runtime"], model: d.bind.model, effort: d.bind.effort },
    workspace: d.workspace,
    remote: true,
  };
}

/// Asks the station a connect runs on: a call of its surface and its arguments, with bytes after it (a file it is to
/// post), answered with what the call gave (and bytes: a file it fetched).
export type Ask = (station: string, request: Json) => Promise<Json>;

/// The bytes after an answer, all of them, at most `limit`.
async function bytesIn(bytes: Bytes, limit: number): Promise<Buffer> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of bytes) {
    size += chunk.length;
    if (size > limit) throw new Error("that station's answer is too long");
    chunks.push(chunk);
  }
  return Buffer.concat(chunks);
}

/// A file a chat posts or fetches through another station: at most this.
const FILE_MAX = 1024 * 1024 * 1024;

/// A connect of another station as the hub here uses it: each call asks that station (`connect.call`), what it said of
/// the connect answers the rest. Its names go into this station's names book of its kind.
export class RemoteSurface implements ChatSurface {
  /// Its id here, the connect it is, and the station it runs on.
  readonly id: string;
  readonly known: Known;
  readonly station: string;
  private d: Described;
  private readonly ask: Ask;
  private readonly names: NameBook | null;
  /// The files of the answers `api` gave, as that station read them.
  private readonly files = new WeakMap<object, InboundFile[]>();

  constructor(id: string, known: Known, station: string, described: Described, ask: Ask, names: NameBook | null) {
    this.id = id;
    this.known = known;
    this.station = station;
    this.d = described;
    this.ask = ask;
    this.names = names;
    // The hub tells a call the connect does not have by its absence.
    for (const name of OPTIONAL) if (!described.has.includes(name)) Object.defineProperty(this, name, { value: undefined });
  }

  get described(): Described {
    return this.d;
  }

  private call(op: string, args: Json[], bytes?: Bytes): Promise<Json> {
    const request = { method: CALL, workspace: this.d.workspace, connect: this.known, op, args };
    return this.ask(this.station, bytes ? withBytes(request, bytes) : request).then((got) => got?.result ?? null);
  }

  /// A call no one waits on: said in the log when it did not go.
  private told(op: string, args: Json[]) {
    void this.call(op, args).catch((error) => log.warn("connects", "a call to the connect's station did not go", { connect: this.id, op, error: (error as Error).message }));
  }

  botUserId(): string {
    return this.d.botUserId;
  }
  botName(): string {
    return this.d.botName;
  }
  identity(): BotIdentity | null {
    return this.d.identity;
  }
  platform(): string {
    return this.d.platform ?? this.d.kind;
  }
  mention(user: string): string {
    return `${this.d.mention[0]}${user}${this.d.mention[1]}`;
  }
  workspace(): string | null {
    return this.d.team;
  }
  get cards(): boolean {
    return this.d.cards;
  }
  get loginCards(): boolean {
    return this.d.loginCards;
  }
  sessionLink(url: string, label: string): string | null {
    return this.d.link === null ? null : this.d.link.replace("\u0001", url).replace("\u0002", label);
  }

  /// Its files go first, each as the bytes after a call of its own, and the post names them as that station keeps them.
  async post(thread: ThreadRef, message: string, files: Attachment[], card?: Json | null): Promise<string> {
    const there: Attachment[] = [];
    for (const file of files) {
      const size = statSync(file.path).size;
      const kept = await this.call("upload", [{ name: file.name, size }], fileBytes(file.path, 0, size));
      if (typeof kept?.path !== "string") throw new Error("the connect's station did not keep the file");
      there.push({ ...file, path: kept.path });
    }
    return String(await this.call("post", [thread, message, there, card ?? null]));
  }

  async cardEnded(thread: ThreadRef, ts: string, text: string, card: Json, end: CardEnd): Promise<void> {
    await this.call("cardEnded", [thread, ts, text, card, end]);
  }

  async download(file: InboundFile): Promise<Uint8Array> {
    const got = await this.ask(this.station, { method: CALL, workspace: this.d.workspace, connect: this.known, op: "download", args: [file], whole: true });
    const bytes = bytesOf(got);
    if (bytes === null) throw new Error("the connect's station answered without the file");
    return bytesIn(bytes, FILE_MAX);
  }

  answerFiles(answer: Json): InboundFile[] {
    return answer !== null && typeof answer === "object" ? (this.files.get(answer) ?? []) : [];
  }

  async api(method: string, params: Record<string, Json>): Promise<Json> {
    const got = await this.call("api", [method, params]);
    const answer = got?.answer ?? null;
    if (answer !== null && typeof answer === "object" && Array.isArray(got?.files)) this.files.set(answer, got.files);
    return answer;
  }

  userName(user: string): Promise<string | null> {
    return this.call("userName", [user]);
  }
  userEmail(user: string): Promise<string | null> {
    return this.call("userEmail", [user]);
  }
  userOf(email: string): Promise<string | null> {
    return this.call("userOf", [email]);
  }
  channelName(channel: string): Promise<string | null> {
    return this.call("channelName", [channel]);
  }
  places(): Promise<Place[]> {
    return this.call("places", []);
  }
  peopleIn(channel: string): Promise<Member[]> {
    return this.call("peopleIn", [channel]);
  }
  begin(channel: string, message: string): Promise<{ thread: ThreadRef; ts: string }> {
    return this.call("begin", [channel, message]);
  }
  edit(thread: ThreadRef, ts: string, message: string): Promise<boolean> {
    return this.call("edit", [thread, ts, message]);
  }
  history(thread: ThreadRef, before: string, limit: number): Promise<ChatMessage[]> {
    return this.call("history", [thread, before, limit]);
  }
  working(thread: ThreadRef, messageTs: string | null, status: string, page?: string | null): void {
    this.told("working", [thread, messageTs, status, page ?? null]);
  }
  standsAt(thread: ThreadRef, stands: { kind: "done" | "need" | "left"; words: string | null } | null): void {
    this.told("standsAt", [thread, stands]);
  }

  /// Where its names are kept: a Slack workspace's team (two connects of one share them), else the connect itself.
  private place(): string {
    return this.d.kind === "slack" && this.d.team ? this.d.team : this.id;
  }

  knownPerson(user: string): Person | null {
    if (this.names === null) return null;
    return this.names.person(personKey(this.place(), user), () => this.call("person", [user]), (known) => known.picture === undefined);
  }

  knownChannel(channel: string): string | null {
    if (this.names === null) return null;
    return this.names.channel(channelKey(this.place(), channel), () => this.call("channel", [channel]));
  }
}

/// How a station answers another's call of one of its connects' surfaces (`surface`: the connect's, null when it does not
/// run here). Files a remote chat posts are kept in `uploads` until they are posted (or for the process's life at most).
export function answerCall(surface: (connect: Known, workspace: string | undefined) => ChatSurface | undefined, uploads: string) {
  return async (_peer: string, request: Json, workspace?: string): Promise<Json> => {
    const op = typeof request?.op === "string" ? request.op : "";
    const known = knownIn(request?.connect);
    const chat = known === null ? undefined : surface(known, workspace);
    if (chat === undefined) throw new Error("that connect does not run on this station");
    const args: Json[] = Array.isArray(request?.args) ? request.args : [];
    if (op === "upload") {
      const bytes = bytesOf(request);
      const name = basename(String(args[0]?.name ?? "file")) || "file";
      if (bytes === null) throw new Error("no file came");
      const dir = join(uploads, randomUUID());
      mkdirSync(dir, { recursive: true });
      const path = join(dir, name);
      const file = await open(path, "w");
      try {
        await writeBytes(file, bytes, 0, FILE_MAX);
      } finally {
        await file.close();
      }
      return { result: { path } };
    }
    if (!CALLS.has(op)) throw new Error("no such call");
    if (op === "post") {
      const [thread, message, files, card] = args;
      const kept = (Array.isArray(files) ? files : []) as Attachment[];
      // Only what came for it, from where uploads keeps it.
      for (const f of kept) if (!f.path.startsWith(uploads + "/") && !f.path.startsWith(uploads + "\\")) throw new Error("that file did not come here");
      try {
        return { result: await chat.post(thread, String(message), kept, card) };
      } finally {
        for (const f of kept) rmSync(join(f.path, ".."), { recursive: true, force: true });
      }
    }
    if (op === "download") {
      const bytes = await chat.download!(args[0]);
      return withBytes({ size: bytes.length }, oneBytes(Buffer.from(bytes)));
    }
    if (op === "api") {
      const answer = await chat.api!(String(args[0]), args[1] ?? {});
      return { result: { answer, files: chat.answerFiles?.(answer) ?? [] } };
    }
    if (op === "person") {
      const user = String(args[0]);
      const known = chat.knownPerson?.(user) ?? null;
      if (known !== null) return { result: known };
      const name = (await chat.userName?.(user)) ?? null;
      if (name === null) return { result: null };
      return { result: { name, email: (await chat.userEmail?.(user).catch(() => null)) ?? "" } };
    }
    if (op === "channel") return { result: (await chat.channelName?.(String(args[0]))) ?? null };
    const f = (chat as any)[op];
    if (typeof f !== "function") throw new Error("that connect has no such call");
    return { result: (await f.apply(chat, args)) ?? null };
  };
}

/// The connects of other stations a chat here runs on, as the station each runs on described it last, and which station
/// that is (<data>/remote-connects.json, kept so that a chat of one has its surface as the station starts, before the next
/// event comes): by their ids here.
export class RemoteConnects {
  private readonly path: string;
  private readonly known = new Map<string, Remote>();
  private readonly surfaces = new Map<string, RemoteSurface>();
  private readonly ask: Ask;
  private readonly names: (kind: ConnectKind) => NameBook | null;
  private readonly here: () => string;

  constructor(data: string, here: () => string, ask: Ask, names: (kind: ConnectKind) => NameBook | null) {
    this.path = join(data, REMOTE_FILE);
    this.here = here;
    this.ask = ask;
    this.names = names;
    for (const [id, r] of Object.entries(readRemote(data))) this.known.set(id, r);
  }

  /// What the connect's station (`station`) said of it now: kept, and its surface made again when that changed.
  learn(id: string, station: string, described: Described) {
    const had = this.known.get(id);
    const next: Remote = { station, described };
    if (had !== undefined && JSON.stringify(had) === JSON.stringify(next)) return;
    this.known.set(id, next);
    this.surfaces.delete(id);
    this.save();
  }

  /// The connect runs on `station` now (moved there); none of this station's any more when that is this one.
  moved(id: string, station: string) {
    const had = this.known.get(id);
    if (had === undefined) return;
    if (station === this.here()) this.known.delete(id);
    else this.known.set(id, { ...had, station });
    this.surfaces.delete(id);
    this.save();
  }

  /// Its surface: a connect of another station a chat here ran on (none for any other id).
  surface(id: string): RemoteSurface | undefined {
    const had = this.surfaces.get(id);
    if (had !== undefined) return had;
    const r = this.known.get(id);
    if (r === undefined) return undefined;
    const made = new RemoteSurface(id, knownOf(id, this.here()), r.station, r.described, this.ask, this.names(r.described.kind));
    this.surfaces.set(id, made);
    return made;
  }

  /// As the hub reads them, with config.json's.
  connects(): Connect[] {
    return [...this.known].map(([id, r]) => connectOf(id, r.described));
  }

  private save() {
    const tmp = `${this.path}.${process.pid}.tmp`;
    writeFileSync(tmp, JSON.stringify(Object.fromEntries(this.known)) + "\n");
    renameSync(tmp, this.path);
  }
}

/// A connect of another station, as remote-connects.json keeps it: where it runs, what that station said of it.
export type Remote = { station: string; described: Described };


/// The connects of other stations kept in `data`, by remote id; none when the file is not there or does not read.
export function readRemote(data: string): Record<string, Remote> {
  try {
    const raw = JSON.parse(readFileSync(join(data, REMOTE_FILE), "utf8"));
    if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return {};
    return Object.fromEntries(Object.entries(raw).filter(([, r]: [string, any]) => typeof r?.station === "string" && typeof r?.described?.kind === "string")) as Record<string, Remote>;
  } catch {
    return {};
  }
}

/// The thread an event is of.
export const threadOfEvent = (event: ChatEvent): ThreadRef => (event.type === "message" ? { channel: event.message.channel, threadTs: event.message.threadTs } : { channel: event.channel, threadTs: event.threadTs });
