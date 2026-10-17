// What the app has done, through the core's calls by name (docs/client-core.md → Calls; client/core-ts/src/ops.ts), as
// the web pages do (web/src/api.ts → stationApi). The app never makes a request itself: the core knows the request
// and brings the topics it touches up to date before it answers; nothing here keeps a cache (data/Calls.kt).
import { CoreError, type CoreClient } from "../../../../web/src/core/client.ts";
import { bindCloudOperations, bindStationOperations } from "../../../../web/src/core/operations.ts";
import type { Attachment, ChatPublished, PublishPreview, Quote, SlackIdentity } from "../../../../web/src/core/shapes.ts";
import { AUTH_REDIRECT } from "../build";
import { t } from "../i18n";
import { AddedMembers, type SlackPerson } from "./Accounts";

/** The bytes of a file in one `station.upload.part` (web/src/api.ts UPLOAD_PART). */
const UPLOAD_PART = 4 * 1024 * 1024;
/** How much of a part has come, as a part read with `progress` says while it comes. */
function partLoaded(heard: unknown): number | null {
  const v = (heard as { loaded?: unknown } | null)?.loaded;
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v) : NaN;
  return Number.isFinite(n) ? Math.trunc(n) : null;
}
/** How much of a part has gone, as a part sent with `progress` says while it goes. */
function partSent(heard: unknown): number | null {
  const v = (heard as { sent?: unknown } | null)?.sent;
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v) : NaN;
  return Number.isFinite(n) ? Math.trunc(n) : null;
}
/** A number the core said (it may say one as text), or null. */
function numberOf(v: unknown): number | null {
  const n = typeof v === "number" ? v : typeof v === "string" ? Number(v) : NaN;
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

/** The bytes of a file in one `station.file.part`. */
const FILE_PART = 4 * 1024 * 1024;
/** The most of a file of the drive one `drive.read` asks for (the station gives at most 8 MB). */
export const DRIVE_PART = 4 * 1024 * 1024;

// ── bytes as the protocol carries them (base64) ──

const B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/** Bytes as base64, the protocol's form for them (Base64.NO_WRAP). */
export function toBase64(bytes: Uint8Array): string {
  // In pieces: a string of a whole part's characters at once overflows the call's arguments.
  let bin = "";
  for (let i = 0; i < bytes.length; i += 0x8000) bin += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  if (typeof globalThis.btoa === "function") return globalThis.btoa(bin);
  let out = "";
  for (let i = 0; i < bin.length; i += 3) {
    const a = bin.charCodeAt(i), b = bin.charCodeAt(i + 1), c = bin.charCodeAt(i + 2);
    const n = (a << 16) | ((b || 0) << 8) | (c || 0);
    out += B64[(n >> 18) & 63]! + B64[(n >> 12) & 63]! + (i + 1 < bin.length ? B64[(n >> 6) & 63]! : "=") + (i + 2 < bin.length ? B64[n & 63]! : "=");
  }
  return out;
}

/** Bytes from base64 (Base64.DEFAULT). */
export function fromBase64(text: string): Uint8Array {
  const bin = globalThis.atob(text.replace(/\s+/g, ""));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

/** A new id for an upload: 32 hex digits (a UUID without its dashes). */
function uploadId(): string {
  const bytes = new Uint8Array(16);
  const crypto = (globalThis as { crypto?: { getRandomValues?: (a: Uint8Array) => Uint8Array } }).crypto;
  if (crypto?.getRandomValues) crypto.getRandomValues(bytes);
  else for (let i = 0; i < 16; i++) bytes[i] = Math.floor(Math.random() * 256);
  bytes[6] = (bytes[6]! & 0x0f) | 0x40;
  bytes[8] = (bytes[8]! & 0x3f) | 0x80;
  return Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
}

// ── files on the phone, read and written a part at a time ──
// NATIVE: there is no file system module in this app yet (expo-file-system): a picked file's ByteSource (the Android
// app's ContentResolver InputStream) and a DiskFile on the phone's disk (java.io.File) come from it. What goes up and
// comes down a part at a time is here in whole.

/** A file read as it goes (java.io.InputStream): `read` fills `into` from `offset` with at most `length` bytes (-1 at its end). */
export interface ByteSource {
  read(into: Uint8Array, offset: number, length: number): Promise<number>;
  /** Passes over at most `n` bytes; how many it did (0 or less: none more). */
  skip(n: number): Promise<number>;
  close(): void;
}

/** A file on the phone's disk, written at its end (java.io.FileOutputStream(into, true)). */
export interface DiskFile {
  /** How many bytes it has. */
  length(): Promise<number>;
  append(bytes: Uint8Array): Promise<void>;
}

/** A part of a file of the drive (`drive.read`): its type, the whole file's size and when it last changed (null when the
 * station does not say), the bytes. */
export class DriveRead {
  constructor(readonly type: string, readonly total: number, readonly bytes: Uint8Array, readonly mtime: number | null = null) {}
}

/**
 * The folders in one on the station (`drive.folders`), to pick one to lend: where, its parent (none at the top), the home,
 * the folders in it (`entries`; `folders`, their names alone, is all a station from before gives), the way there from the
 * home or the top (`crumbs`), and where folders usually are (`places`: the home, its own folders, the disks). Each says
 * whether the station may read it (macOS keeps some from a station it did not give full disk access).
 */
export interface DriveFolders {
  path: string; parent?: string | null; home?: string; folders?: string[];
  entries?: PickFolder[] | null; crumbs?: DriveCrumb[] | null; places?: PickFolder[];
  /** The station may not list it (it answers so, with nothing in it; one from before refuses instead). */
  unreadable?: boolean;
}

/** A folder to pick from: its name (a place's in the asker's words), where it is, whether the station may read it, whether it is a disk. */
export interface PickFolder { name: string; path: string; unreadable?: boolean; disk?: boolean }

/** A step of the way to a folder: its name, where it is. */
export interface DriveCrumb { name: string; path: string }

/** Reads from `input` until `part` is full; a short file is an error. */
async function fill(input: ByteSource, part: Uint8Array): Promise<number> {
  let got = 0;
  while (got < part.length) {
    const n = await input.read(part, got, part.length - got);
    if (n < 0) throw new Error("short file");
    got += n;
  }
  return got;
}

/** Passes over `left` bytes of `input`. */
async function skipAll(input: ByteSource, left: number): Promise<void> {
  while (left > 0) {
    const n = await input.skip(left);
    if (n <= 0) throw new Error("short file");
    left -= n;
  }
}

/** The admin API of one station, by what each call does. */
export class StationApi {
  readonly #core: CoreClient;
  readonly #ops: ReturnType<typeof bindStationOperations>;

  constructor(core: CoreClient, readonly station: string) {
    this.#core = core;
    this.#ops = bindStationOperations((name, params) => core.call(name, { ...params, station }));
  }

  #op(name: string, params: Record<string, unknown> = {}): Promise<unknown> {
    return this.#core.call(name, { ...params, station: this.station });
  }

  #chat(call: string, thread: number, params: Record<string, unknown> = {}): Promise<unknown> {
    return this.#core.call(call, { station: this.station, thread, ...params });
  }

  /** Sends to the chat: the message shows at once from the view's outbox, and leaves it once the station has it. */
  async send(thread: number, text: string, attachments: Attachment[] = [], quotes: Quote[] = []): Promise<void> {
    await this.#chat("chat.send", thread, { text, attachments, quotes });
  }

  /** A failed message from the outbox: send it again, or drop it. */
  async retry(thread: number, id: string): Promise<void> { await this.#chat("chat.retry", thread, { id }); }
  async discard(thread: number, id: string): Promise<void> { await this.#chat("chat.discard", thread, { id }); }

  /** Brings the page before the chat's first loaded message into the view. */
  async older(thread: number): Promise<void> { await this.#chat("chat.older", thread); }

  /** Brings the page after the chat's last loaded message into the view (it shows a window short of its end), as many
   *  going at its start; they are read, not said: none comes in with a motion. */
  async newer(thread: number): Promise<void> { await this.#chat("chat.newer", thread); }

  /** The chat's latest page in place of what it shows: the reader goes to its end. */
  async latest(thread: number): Promise<void> { await this.#chat("chat.latest", thread); }

  /** Where the reader leaves the chat: the message at the top of what shows and how far below the list's top its top
   *  is (`offset`, px), or none at its end (it opens there next, while nothing is unread). */
  async place(thread: number, seq: number | null, offset: number | null = null): Promise<void> {
    await this.#chat("chat.place", thread, { ...(seq != null ? { seq } : {}), ...(offset != null ? { offset } : {}) });
  }

  /** Brings the page of an agent's execution history before what it shows into the view. */
  async historyOlder(key: string): Promise<void> { await this.#core.call("history.older", { station: this.station, key }); }

  /** Reads whole an execution history's step or thought shown in brief, as it is opened (its transcript entries). */
  async historyDetail(key: string, entries: number[]): Promise<void> {
    if (entries.length === 0) return;
    await this.#core.call("history.detail", { station: this.station, key, from: Math.min(...entries), to: Math.max(...entries) });
  }

  // ── connects (web/src/api.ts → stationApi) ──

  /** Changes a connect: any of `bind`, `mode`, `requireMention`, `enabled`, `slack`, `owner`. */
  async putConnect(id: string, body: Record<string, unknown>): Promise<void> { await this.#ops.connectPut({ id, input: body }); }
  async deleteConnect(id: string): Promise<void> { await this.#ops.connectDelete({ id }); }
  async reconnect(id: string): Promise<void> { await this.#ops.connectReconnect({ id }); }
  /** A single-session connect's session: `session` null makes a new one (named `title`). */
  async bindSession(connect: string, session: string | null, title: string): Promise<void> {
    await this.#ops.connectBindSession({ connect, session, ...(title.trim() !== "" ? { title } : {}) });
  }
  /** Who the Slack tokens are (null with the errors when they do not work). */
  async verifySlack(connect: string | null, install: string | null, appToken: string, botToken: string): Promise<[SlackIdentity | null, string[]]> {
    const r = await this.#ops.slackVerify<{ identity?: SlackIdentity | null; errors?: string[] }>({
      ...(connect != null ? { connect } : {}), ...(install != null ? { install } : {}), appToken, botToken,
    });
    return [r.identity ?? null, (r.errors ?? []).map(String)];
  }
  /** A Slack workspace's app configuration token (its refresh token); answers which workspace. */
  async addConfigToken(refreshToken: string): Promise<string> {
    return String((await this.#ops.slackAddConfigToken<{ teamId: string }>({ refreshToken })).teamId);
  }
  /**
   * Makes a Slack app with still.fail's manifest in the workspace of `team`: its name and description, the rest as a new
   * app's. The station keeps it, waiting for its connect (the overview's `slackApps`); answers its app id.
   * With `settings` whole (and its icon, a data URL): answers its app id and why the icon did not go up.
   */
  makeSlackApp(team: string, name: string, description: string): Promise<string>;
  makeSlackApp(team: string, settings: Record<string, unknown>, icon: string | null): Promise<[string, string | null]>;
  async makeSlackApp(team: string, a: string | Record<string, unknown>, b: string | null): Promise<string | [string, string | null]> {
    if (typeof a === "string") {
      const settings = {
        name: a, displayName: a, description: b ?? "", longDescription: "", backgroundColor: "#F3E3D3",
        groups: Object.fromEntries(SLACK_GROUPS.map((g) => [g, true])),
      };
      return String((await this.#ops.slackMakeApp<{ appId: string }>({ team, settings })).appId);
    }
    const r = await this.#ops.slackMakeApp<{ appId: string; iconError?: string | null }>({ team, settings: a, ...(b != null ? { icon: b } : {}) });
    return [String(r.appId), r.iconError ?? null];
  }
  /** Drops an app made here from the waiting ones; it stays in Slack. */
  async dropSlackApp(appId: string): Promise<void> { await this.#ops.slackDropApp({ appId }); }
  /** The people of the Slack workspaces this station's connects are in, once each by email, and what could not be read. */
  async slackPeople(): Promise<[SlackPerson[], string[]]> {
    const r = await this.#ops.slackPeople<{ people?: SlackPerson[] | null; errors?: string[] | null }>();
    return [r.people ?? [], (r.errors ?? []).map(String)];
  }
  /** Where to make a Slack app by hand from still.fail's manifest. */
  async createAppUrl(name: string): Promise<string> { return String((await this.#ops.slackCreateAppUrl<{ url: string }>({ name })).url); }
  /** A new connect; answers its id. */
  async createConnect(body: Record<string, unknown>): Promise<string> { return String((await this.#ops.connectCreate<{ id: string }>({ input: body })).id); }

  // ── profiles ──

  /** Changes a profile: any of `name`, `access`, `env`, `models`. */
  async putProfile(id: string, body: Record<string, unknown>): Promise<void> { await this.#ops.profilePut({ id, input: body }); }
  async deleteProfile(id: string): Promise<void> { await this.#ops.profileDelete({ id }); }
  /** Shared with the workspace's other stations (`allow` null: every one), or no longer. */
  async shareProfile(id: string, on: boolean, allow: string[] | null): Promise<void> { await this.#ops.profileShare({ id, on, ...(allow != null ? { allow } : {}) }); }
  /** A shared profile moved to another station (its subscription signed in there from then on). */
  async moveProfile(id: string, to: string): Promise<void> { await this.#ops.profileMove({ id, to }); }
  /** A skill shared with the workspace's other stations, or no longer. */
  async shareSkill(name: string, on: boolean): Promise<void> { await this.#ops.skillShare({ name, on }); }
  async resetQuota(id: string): Promise<void> { await this.#ops.profileResetQuota({ id }); }
  async refreshQuota(id: string): Promise<void> { await this.#ops.profileQuota({ id }); }
  async startLogin(profile: string): Promise<void> { await this.#ops.profileLogin({ id: profile }); }
  async cancelLogin(profile: string): Promise<void> { await this.#ops.profileCancelLogin({ id: profile }); }
  async loginCode(profile: string, code: string): Promise<void> { await this.#ops.profileLoginCode({ id: profile, code }); }
  /** A subscription signed in before its profile exists: the station makes the profile when it succeeds. Answers the login's id. */
  async newLogin(runtime: string): Promise<string> { return String((await this.#ops.loginNew<{ id: string }>({ runtime })).id); }
  async newLoginCode(id: string, code: string): Promise<void> { await this.#ops.loginCode({ id, code }); }
  async dropLogin(id: string): Promise<void> { await this.#ops.loginDrop({ id }); }
  /** A keyed (or variables) profile, made only once its key is checked; answers its id. */
  async addProfile(runtime: string | null, kind: string, key: string | null, provider: string | null = null, endpoint: string | null = null): Promise<string> {
    const access = { kind, ...(key != null ? { key } : {}), ...(provider != null ? { provider } : {}), ...(endpoint != null ? { endpoint } : {}) };
    return String((await this.#ops.profileAdd<{ id: string }>({ ...(runtime != null ? { runtime } : {}), access })).id);
  }
  /** A profile on the machine's own login of `runtime` (one kept in a file); answers its id. */
  async useMachineLogin(runtime: string): Promise<string> {
    return String((await this.#ops.profileUseMachineLogin<{ id: string }>({ runtime })).id);
  }

  /** Starts the session's runtime ahead of a message. */
  async warm(key: string): Promise<void> { await this.#ops.sessionWarm({ key }); }

  async stop(key: string): Promise<void> { await this.#ops.sessionStop({ key }); }

  /**
   * How it runs from its next turn on: a model, how hard it thinks, and who runs it (a profile kept to by hand, or
   * null: the station's pick).
   */
  async sessionSettings(key: string, model: string, effort: string | null, profile: string | null): Promise<void> {
    await this.#ops.sessionSettings({ key, model, effort, profile });
  }

  /** Releases an idle agent's process. */
  async evict(key: string): Promise<void> { await this.#ops.sessionEvict({ key }); }

  /** A new chat: its session and its thread, made before its first message so files can go into it. */
  async newChat(runtime: string, model: string, effort: string | null): Promise<[string, number]> {
    const r = await this.#ops.sessionNew<{ key: string; thread: { id: number } }>({ runtime, model, ...(effort != null ? { effort } : {}) });
    return [String(r.key), Number(r.thread.id)];
  }

  /** The chat of an agent that has none yet, bound to its session; answers the thread. */
  async chatFor(session: string): Promise<number> { return Number((await this.#ops.chatForSession<{ id: number }>({ session })).id); }

  /** Checks a profile, which lists the models it can use. */
  async checkProfile(id: string): Promise<void> { await this.#ops.profileCheck({ id }); }

  /** "这是我" (bound) or "不是我" on a Slack user: the station takes them for the viewer, or no longer. */
  async slackIdentity(user: string, bound: boolean): Promise<void> { await this.#ops.slackIdentity({ user, bound }); }

  /** Replaces a profile's enabled models. */
  async setModels(profile: string, models: string[]): Promise<void> { await this.#ops.profilePut({ id: profile, input: { models } }); }

  /** One model named by hand, added to those enabled (a provider that does not list its models). */
  async addModel(profile: string, model: string): Promise<void> { await this.#ops.profileAddModel({ id: profile, model }); }

  /**
   * Puts a file on the station, in no chat yet; a message that sends it takes it into its chat. It goes a part at a
   * time (`station.upload.part`, web/src/api.ts the same), read from `open` as it goes, so a big one is never all in
   * memory; `onProgress` hears how much of it the station has after each part.
   */
  async upload(name: string, size: number, open: () => ByteSource, width: number | null, height: number | null, onProgress: (sent: number) => void = () => undefined): Promise<Attachment> {
    const id = uploadId();
    let input = open();
    let at = 0;
    let saved: Attachment;
    try {
      let have = 0;
      let done: Attachment | null = null;
      // Said at once (nothing yet), then as each part goes.
      onProgress(0);
      while (done === null) {
        // The station goes on from what it has: elsewhere than where the file was read to, read again from there.
        if (at !== have) { input.close(); input = open(); await skipAll(input, have); at = have; }
        const part = new Uint8Array(Math.min(UPLOAD_PART, size - have));
        const got = await fill(input, part);
        at += got;
        const from = have;
        const told = await this.#core.call("station.upload.part", {
          station: this.station, id, name, size, offset: have, bytes: toBase64(part), progress: true,
        }, (heard) => { const n = partSent(heard); if (n !== null) onProgress(from + n); }) as { file?: Attachment | null; have?: number };
        const file = told.file ?? null;
        if (file !== null) { done = file; onProgress(size); break; }
        const next = numberOf(told.have) ?? have + got;
        // Nothing more: a part the station could not take.
        if (next === have) throw new CoreError({ code: "upload", message: t("android-chat.file.uploadFailed") });
        have = next;
        onProgress(have);
      }
      saved = done;
    } finally { input.close(); }
    // An image's size travels with it, so every page can hold its place before it loads.
    return width != null && height != null ? { ...saved, width, height } : saved;
  }

  /**
   * A file of the station's drive put among its uploads, as one sent up would be (a folder: zipped there, `zip`), for a
   * message to send (`drive.stage`): the phone's Station 文件 switched to a file (StationFiles.kt).
   */
  async driveStage(root: string, path: string, zip: boolean): Promise<Attachment> {
    return await this.#ops.driveStage<Attachment>({ root, path, ...(zip ? { zip: true } : {}) });
  }

  /**
   * A big file sent to the session, onto the disk at `into` a part at a time (`station.file.part`), never all in
   * memory; `onProgress` hears the bytes so far and the whole size (`size`, as its message says, until the station
   * says), at once and then as each part comes. What is already in `into` is gone on from. Throws `unsupported` from a
   * station from before parts.
   */
  async fileToDisk(key: string, name: string, into: DiskFile, size: number, onProgress: (at: number, of: number) => void = () => undefined): Promise<void> {
    let at = await into.length();
    let total = Number.MAX_SAFE_INTEGER;
    onProgress(at, size);
    while (at < total) {
      const from = at;
      const of = total === Number.MAX_SAFE_INTEGER ? size : total;
      const got = await this.#core.call("station.file.part", {
        station: this.station, key, name, offset: at, length: FILE_PART, progress: true,
      }, (heard) => { const n = partLoaded(heard); if (n !== null) onProgress(from + n, of); }) as { total?: number; bytes: string };
      total = numberOf(got.total) ?? total;
      const bytes = fromBase64(got.bytes);
      if (bytes.length === 0) break;
      await into.append(bytes);
      at += bytes.length;
      onProgress(at, total);
    }
  }

  /** The first `length` bytes of a file sent to the session (`station.file.part`); throws `unsupported` from a station from before parts. */
  async fileHead(key: string, name: string, length: number): Promise<Uint8Array> {
    const got = await this.#core.call("station.file.part", { station: this.station, key, name, offset: 0, length }) as { bytes: string };
    return fromBase64(got.bytes);
  }

  /** A video's poster as the station makes it (a small JPEG of its first frame); null when it has none. */
  async poster(key: string, name: string): Promise<Uint8Array | null> {
    const got = await this.#core.call("station.poster", { station: this.station, key, name }) as { bytes: string } | null;
    if (got == null) return null;
    return fromBase64(got.bytes);
  }

  /**
   * A file sent to the session. With `thumb`: the file and its type as the station says (web/src/api.ts → file), an
   * image as a chat shows it (its thumbnail, where the station keeps one; an older station answers the image itself).
   * `onProgress`: the bytes so far and the whole size (null when the station does not say) as a whole file comes.
   */
  file(key: string, name: string): Promise<Uint8Array>;
  file(key: string, name: string, thumb: boolean, onProgress?: ((loaded: number, total: number | null) => void) | null): Promise<[string, Uint8Array]>;
  async file(key: string, name: string, thumb?: boolean, onProgress: ((loaded: number, total: number | null) => void) | null = null): Promise<Uint8Array | [string, Uint8Array]> {
    if (thumb === undefined) {
      const answer = await this.#core.call("station.file", { station: this.station, key, name }) as { bytes: string };
      return fromBase64(answer.bytes);
    }
    const params = { station: this.station, key, name, ...(thumb ? { thumb: true } : {}), ...(onProgress != null ? { progress: true } : {}) };
    const answer = await (onProgress == null ? this.#core.call("station.file", params) : this.#core.call("station.file", params, (got) => {
      const o = got as { loaded?: unknown; total?: unknown } | null;
      const loaded = numberOf(o?.loaded);
      if (loaded !== null) onProgress(loaded, numberOf(o?.total));
    })) as { type?: unknown; bytes: string };
    const type = typeof answer.type === "string" ? answer.type : "";
    return [type, fromBase64(answer.bytes)];
  }

  /** What a visualization's widget kept (widget.state; null when nothing, or an older station that keeps nothing). */
  async widgetState(key: string, path: string): Promise<unknown | null> {
    return (await this.#ops.widgetState<{ state?: unknown } | null>({ key, path }))?.state ?? null;
  }
  /** Keeps what a visualization's widget asks to keep (widget.setState), for the next time it is shown. */
  async setWidgetState(key: string, path: string, state: unknown): Promise<void> {
    await this.#ops.widgetSetState({ key, path, state });
  }

  // ── background jobs and web services (web/src/Jobs.tsx) ──

  // A job and its output are topics (Topics.job, Topics.jobLog): the core reads them again while shown.
  /** Stops a job from the app (its agent is told who did). */
  async stopJob(id: string): Promise<void> { await this.#ops.jobStop({ id }); }
  /** Clears a session's ended jobs (stopped, failed, ended by itself) off its pages, as the station keeps them. */
  async clearEndedJobs(session: string): Promise<void> { await this.#ops.jobClearEnded({ session }); }

  // ── decisions (client/core-ts/src/decisions.ts) ──

  /** Answers a decision with one of its options: the viewer's message in its chat, the label quoting the post. */
  async answerDecision(thread: number, seq: number, option: string): Promise<void> {
    await this.#op("decision.answer", { thread, seq, option });
  }
  /** Answers a card with the chat composer's text, attachments and quotes, also quoting the post that asked. */
  async replyDecision(thread: number, seq: number, text: string, attachments: Attachment[] = [], quotes: Quote[] = []): Promise<void> {
    await this.#op("decision.reply", { thread, seq, text, attachments, quotes });
  }
  /** Sets a decision aside on this device (待定): last on the decisions page, still pending; nothing is sent. */
  async deferDecision(thread: number, seq: number): Promise<void> { await this.#op("decision.defer", { thread, seq }); }
  /** Dismisses a decision for the viewer, on every device of theirs: off their list, still pending for others. */
  async keepChat(thread: number): Promise<void> { await this.#ops.chatKeep({ thread }); }
  async dismissDecision(thread: number, seq: number): Promise<void> { await this.#ops.decisionDismiss({ thread, seq }); }

  // ── the archive (web/src/pages/Archive.tsx) ──

  /** A chat into the archive or back: its thread (with its session when it is that session's own), or an agent with no chat yet. */
  async setArchived(thread: number | null, session: string, archived: boolean): Promise<void> {
    await this.#ops.chatArchive({ session, ...(thread != null ? { thread } : {}), archived });
  }
  /** Keeps a chat at the top of the viewer's list, or lets it go (by its item's id, its session's key). */
  async setPinned(session: string, pinned: boolean): Promise<void> { await this.#ops.chatPin({ session, pinned }); }
  /** Shares a chat with the viewer's other workspaces ticked (none: no longer), their agents sending in it too when `write`. */
  async share(thread: number | null, session: string, to: string[], write: boolean): Promise<void> {
    await this.#op("chat.xshare", { session, ...(thread != null ? { thread } : {}), to, write });
  }
  /**
   * The chats of other workspaces a text written here refers to by its marks that are not shared with this station's
   * workspace yet (sending it would leave this workspace's agents unable to read them): docs/chat-share.md.
   */
  async outsideRefs(text: string): Promise<OutsideRef[]> {
    return ((await this.#op("chat.outsideRefs", { text })) as { chats?: OutsideRef[] } | null)?.chats ?? [];
  }
  /** What a public snapshot of the chat would hold now (nothing kept): its messages, what was hidden in them, its attachments. */
  async publishPreview(thread: number): Promise<PublishPreview> { return (await this.#op("chat.publishPreview", { thread })) as PublishPreview; }
  /** Keeps a public snapshot of the chat up to `upto` (the preview's last message), with the attachments ticked: its link. */
  async publish(thread: number, upto: number, files: string[]): Promise<ChatPublished> {
    return (await this.#op("chat.publish", { thread, upto, files })) as ChatPublished;
  }
  /** Revokes one of the chat's public snapshots: its link opens nothing any more. */
  async unpublish(thread: number, id: string): Promise<void> { await this.#op("chat.unpublish", { thread, id }); }
  /** Shares this station's chat `id` with one workspace more (`workspace`), telling its station `prefer` first. */
  async shareInto(id: string, workspace: string, prefer: string | null): Promise<void> {
    await this.#op("chat.xshareAdd", { id, workspace, ...(prefer != null ? { prefer } : {}) });
  }
  /**
   * This station (by its address in its home workspace) added to `workspace` as it is (docs/multi-workspace.md):
   * answers what it is called there, null when the station does not say. A refusal comes in words.
   */
  async joinWorkspace(workspace: string): Promise<string | null> {
    const name = ((await this.#op("station.join", { workspace })) as { joined?: { name?: unknown } | null } | null)?.joined?.name;
    return typeof name === "string" ? name : null;
  }
  /** Deletes a session for good: its chat, its history and its workspace directory. */
  async deleteSession(key: string): Promise<void> { await this.#ops.sessionDelete({ key }); }

  // ── what a chat runs on, chosen (client/core-ts/src/choose.ts; web/src/pick.ts) ──

  /**
   * A new chat, there at once, made with what is picked on this station (web/src/NewChat.tsx → useEnsureChat): the
   * core has its page, its row and what is sent to it under the key it answers (the station makes it behind it, told
   * that key as `clientKey`, so its row is known for this one's, never guessed).
   */
  async createNewChat(): Promise<string> {
    return String(((await this.#core.call("newChat.create", { station: this.station })) as { key: string }).key);
  }
  /** Picks in a model control's panel (`of`: new, session:<key>, …; null: the default, the station's pick); `open`: from what it runs on now again. */
  async pickSet(of: string, fill: Record<string, unknown>): Promise<void> {
    await this.#core.call("pick.set", { station: this.station, of, ...fill });
  }
  /** What the panel picked becomes what it runs on (nothing changed: nothing done). */
  async pickSave(of: string): Promise<void> { await this.#core.call("pick.save", { station: this.station, of }); }

  // ── the machine's own sessions (web/src/MachineSessions.tsx) ──

  /** Sessions the machine's own Claude Code and Codex kept (in a terminal); a station from before them fails it. */
  async machineSessions(): Promise<MachineSession[]> {
    return (await this.#ops.machineSessionsList<{ sessions?: MachineSession[] }>()).sessions ?? [];
  }
  /** One of them to look at first: what was said in it (the latest `limit`), and how many there are in all. */
  async machineSession(runtime: string, id: string, limit = 200): Promise<[MachineSaid[], number]> {
    const r = await this.#ops.machineSessionsRead<{ said?: MachineSaid[]; total?: unknown }>({ runtime, id, limit });
    const said = r.said ?? [];
    return [said, numberOf(r.total) ?? said.length];
  }
  /** A chat going on with one of them (the one already going on with it, if any); answers its key. */
  async continueMachineSession(runtime: string, id: string): Promise<string> {
    return String((await this.#ops.machineSessionsContinue<{ key: string }>({ runtime, id })).key);
  }

  // ── the station's software, its memory, Slack apps (web/src/api.ts → stationApi) ──

  /** Updates the station or a runtime (`id`: station | claude | codex | dsh), or installs a runtime not there; the overview says how it goes. */
  async updateSoftware(id: string): Promise<void> { await this.#ops.softwareUpdate({ id }); }
  /** Reads again what versions are out. */
  async checkSoftware(): Promise<void> { await this.#ops.softwareCheck(); }
  /** Puts the station on a channel (`stable` | `beta`); its versions are read again. */
  async setSoftwareChannel(channel: string): Promise<void> { await this.#ops.softwareChannel({ channel }); }
  /** Turns the station's updating by itself on or off; turned on, it reads what is out and updates at once. */
  async setSoftwareAuto(on: boolean): Promise<void> { await this.#ops.softwareAuto({ on }); }
  /** The agents' memory on the station: the global one and the skills (projects' memories among them), as they are. */
  memory(): Promise<unknown> { return this.#ops.memoryGet(); }
  /**
   * Writes what changed of a connect's Slack app (any of name, displayName, description, longDescription,
   * backgroundColor, groups; `icon`: a data URL) into its manifest; answers whether Slack wants its new permissions
   * approved, and why the icon did not go up.
   */
  async putSlackApp(connect: string, input: Record<string, unknown>): Promise<Record<string, unknown>> {
    return await this.#ops.connectPutSlackApp<Record<string, unknown>>({ connect, input });
  }
  /** Forgets the viewer's configuration token of a Slack workspace. */
  async removeConfigToken(team: string): Promise<void> { await this.#ops.slackRemoveConfigToken({ team }); }
  /** Hands Slack's install code to the station that made the app; answers the workspace it went into. */
  async slackInstalled(code: string, state: string): Promise<string | null> {
    const team = (await this.#ops.slackInstalled<{ team?: unknown } | null>({ code, state }))?.team;
    return team == null ? null : String(team);
  }

  // ── the station's drive (docs/drive.md) ──

  /** The folders the station lends its members, the whole list (the workspace's owners and admins). */
  async driveSetRoots(roots: string[]): Promise<void> { await this.#ops.driveSetRoots({ roots }); }

  // ── what macOS lets a Mac station's still.fail Helper do (docs/remote-screens.md "Grants") ──

  /**
   * The helper's window for `grant` (a StationGrant's id) put up on the Mac. Answers whether the next step is the
   * Mac's screen from here: the window is up and that screen can be seen and driven.
   */
  async requestGrant(grant: string): Promise<boolean> {
    const r = await this.#ops.permissionsRequest<unknown>({ grant });
    if (r === null || typeof r !== "object" || Array.isArray(r)) return false;
    const o = r as { window?: unknown; screen?: unknown };
    return String(o.window) === "up" && String(o.screen) === "true";
  }
  /** The folders in `path` on the station (its home when null), to pick one to lend (owners and admins). */
  async driveFolders(path: string | null): Promise<DriveFolders> {
    return await this.#ops.driveFolders<DriveFolders>(path != null ? { path } : {});
  }
  async driveMkdir(root: string, path: string): Promise<void> { await this.#ops.driveMkdir({ root, path }); }
  async driveRename(root: string, from: string, to: string): Promise<void> { await this.#ops.driveRename({ root, from, to }); }
  /** To the machine's trash where the station has one (`permanent`: for good; `no_trash` where none takes it). */
  async driveRemove(root: string, path: string, permanent = false): Promise<void> {
    await this.#ops.driveRemove({ root, path, ...(permanent ? { permanent: true } : {}) });
  }
  /** A folder zipped on the station to download: where the zip is (a root of its own and its path there), its name and size. */
  async driveZip(root: string, path: string): Promise<DriveZip> { return await this.#ops.driveZip<DriveZip>({ root, path }); }
  /** A folder read again, answering once it is (its page's refresh). */
  async driveRefresh(root: string, path: string): Promise<void> { await this.#core.call("drive.refresh", { station: this.station, root, path }); }
  /** Where a file was left on this device (a text's offset, a video's time in ms), of how much when known. */
  async drivePlace(root: string, path: string, at: number, of: number | null): Promise<void> {
    await this.#core.call("drive.place", { station: this.station, root, path, at, ...(of != null ? { of } : {}) });
  }

  /** A part of a file of the drive (at most DRIVE_PART), with the file's whole size as the station has it now; `heard`: its bytes so far, as they come. */
  async driveRead(root: string, path: string, offset: number, length: number, heard: ((loaded: number) => void) | null = null): Promise<DriveRead> {
    const params = { station: this.station, root, path, offset, length: Math.min(length, DRIVE_PART), ...(heard != null ? { progress: true } : {}) };
    const got = await (heard == null ? this.#core.call("drive.read", params) : this.#core.call("drive.read", params, (p) => {
      const n = partLoaded(p);
      if (n !== null) heard(n);
    })) as { bytes: string; total?: unknown; mtime?: unknown; type?: unknown };
    const bytes = fromBase64(got.bytes);
    const total = numberOf(got.total) ?? offset + bytes.length;
    const mtime = numberOf(got.mtime);
    return new DriveRead(typeof got.type === "string" ? got.type : "", total, bytes, mtime);
  }

  /**
   * The first `limit` bytes of a file of the drive (the whole of it when shorter), a part at a time; `onProgress` hears
   * bytes so far and its size (`size`, as its folder said, until the station says), as each part comes.
   */
  async driveBytes(root: string, path: string, limit = Number.MAX_SAFE_INTEGER, size = Number.MAX_SAFE_INTEGER, onProgress: (at: number, of: number) => void = () => undefined): Promise<Uint8Array> {
    const parts: Uint8Array[] = [];
    let at = 0;
    let total = Number.MAX_SAFE_INTEGER;
    while (at < Math.min(total, limit)) {
      const from = at;
      const of = Math.min(total === Number.MAX_SAFE_INTEGER ? size : total, limit);
      const got = await this.driveRead(root, path, at, Math.min(DRIVE_PART, Math.min(total, limit) - at), of === Number.MAX_SAFE_INTEGER ? null : (n) => onProgress(from + n, of));
      total = got.total;
      if (got.bytes.length === 0) break;
      parts.push(got.bytes);
      at += got.bytes.length;
      onProgress(at, total);
    }
    const out = new Uint8Array(at);
    let i = 0;
    for (const p of parts) { out.set(p, i); i += p.length; }
    return out;
  }

  /**
   * A file of the drive onto the phone's disk at `into`, a part at a time, never all in memory; what is in `into`
   * already is gone on from. `onProgress` as driveBytes's.
   */
  async driveToDisk(root: string, path: string, into: DiskFile, size = Number.MAX_SAFE_INTEGER, onProgress: (at: number, of: number) => void = () => undefined): Promise<void> {
    let at = await into.length();
    let total = Number.MAX_SAFE_INTEGER;
    while (at < total) {
      const from = at;
      const of = total === Number.MAX_SAFE_INTEGER ? size : total;
      const got = await this.driveRead(root, path, at, DRIVE_PART, of === Number.MAX_SAFE_INTEGER ? null : (n) => onProgress(from + n, of));
      total = got.total;
      if (got.bytes.length === 0) break;
      await into.append(got.bytes);
      at += got.bytes.length;
      onProgress(at, total);
    }
  }

  /**
   * Puts a file into a folder of the drive (`path`: where it goes, under `root`), a part at a time (`drive.upload.part`,
   * as `upload` does for a chat), read from `open` as it goes; `onProgress` hears how much of it the station has. A
   * station that has a file of that name already refuses the first part with `exists`, unless `replace`. Once whole, the
   * core has read its folder again.
   */
  async driveUpload(root: string, path: string, size: number, open: () => ByteSource, replace = false, onProgress: (have: number) => void = () => undefined): Promise<void> {
    const id = uploadId();
    let input = open();
    let at = 0;
    try {
      let have = 0;
      let done = false;
      // Small first, doubling while parts go through (as DriveSource's reads): a name taken is told after a quarter
      // of a megabyte sent, not four.
      let planned = 256 * 1024;
      while (!done) {
        // The station goes on from what it has: elsewhere than where the file was read to, read again from there.
        if (at !== have) { input.close(); input = open(); await skipAll(input, have); at = have; }
        const part = new Uint8Array(Math.min(planned, size - have));
        const got = await fill(input, part);
        at += got;
        const told = await this.#core.call("drive.upload.part", {
          station: this.station, root, path, id, offset: have, total: size,
          ...(replace ? { replace: true } : {}),
          bytes: toBase64(part),
        }) as { entry?: unknown; have?: unknown };
        const entry = told.entry ?? null;
        const next = numberOf(told.have) ?? have + got;
        // Whole and in its place.
        if (entry !== null) done = true;
        // All of it there with no entry said (an empty file): the folder is read again all the same.
        else if (next >= size) done = true;
        // Nothing more taken: a part the station could not take.
        else if (next === have) throw new CoreError({ code: "upload", message: t("android-chat.file.uploadFailed") });
        planned = next === have + got ? Math.min(planned * 2, UPLOAD_PART) : 256 * 1024;
        have = next;
        onProgress(done ? size : have);
      }
    } finally { input.close(); }
  }

  // ── a chat itself (web/src/api.ts → rename; chats made here, by their key) ──

  /** Sends to a chat by its key (one made here, made by its station or not): it waits in the chat until it can go. */
  async sendIn(session: string, text: string, attachments: Attachment[] = [], quotes: Quote[] = []): Promise<void> {
    await this.#op("chat.send", { session, text, attachments, quotes });
  }
  /** A failed message of such a chat, by its key: sent again, or dropped. */
  async retryIn(session: string, id: string): Promise<void> { await this.#op("chat.retry", { session, id }); }
  async discardIn(session: string, id: string): Promise<void> { await this.#op("chat.discard", { session, id }); }
  /** A chat named by hand; an empty name: named by its first message again. */
  async rename(thread: number | null, session: string, title: string): Promise<void> {
    await this.#ops.chatRename({ session, ...(thread != null ? { thread } : {}), title });
  }
}

/** A session the station's machine kept (its own Claude Code or Codex, in a terminal); `session`: the chat going on with it. */
export interface MachineSession {
  runtime: string;
  id: string;
  cwd: string;
  title?: string | null;
  first?: string | null;
  model?: string | null;
  updatedAt: number;
  session?: string | null;
  /** Its runtime, where it ran (the home directory as ~) and how long ago, in a line (the core's). */
  meta?: string | null;
}

/** Something said in one of them: by the person, else by its agent; when, in ms. */
export interface MachineSaid { person: boolean; text: string; at?: number | null }

export const Auth = {
  // The Android app comes back on stillfail:// (stillfail-beta:// for the beta app, so the released app never takes its
  // sign-in, nor it theirs); this app on the scheme its build says (build.ts AUTH_REDIRECT), which cloud takes too.
  REDIRECT: AUTH_REDIRECT,

  /** The URL to open in a Custom Tab; still.fail cloud comes back to REDIRECT. The device signs in by the name the core gives it. */
  async begin(core: CoreClient): Promise<string> {
    return String(((await core.call("auth.begin", { redirect_uri: Auth.REDIRECT, return_to: "/" })) as { url: string }).url);
  },

  /** Finishes a sign-in with the callback's query string ("?code=…&state=…"). */
  async complete(core: CoreClient, query: string): Promise<void> {
    await core.call("auth.complete", { query });
  },

  async signOut(core: CoreClient, account: string): Promise<void> {
    await core.call("auth.signOut", { account });
  },
};

/** still.fail cloud's account API: what the app has done there, by name, done by the core as one of the signed-in accounts (web/src/cloud/api.ts). */
export class Cloud {
  readonly #ops: ReturnType<typeof bindCloudOperations>;

  constructor(core: CoreClient, account: string) {
    this.#ops = bindCloudOperations((name, params) => core.call(name, { ...params, account }));
  }

  /** `code`: an invite code, for an account not let in yet (still.fail is invite-only). Answers the new workspace's id. */
  async createWorkspace(name: string, code: string): Promise<string> {
    return String((await this.#ops.workspaceCreate<{ id: string }>({ name, ...(code !== "" ? { invite_code: code } : {}) })).id);
  }

  /** Answers the workspace joined. */
  async acceptInvitation(id: string): Promise<string> { return String((await this.#ops.invitationAccept<{ id: string }>({ id })).id); }

  async declineInvitation(id: string): Promise<void> { await this.#ops.invitationDecline({ id }); }

  async renameWorkspace(workspace: string, name: string): Promise<void> { await this.#ops.workspaceRename({ workspace, name }); }
  /** Its icon and emoji together, as a station's (setStationMark); "" takes either away. */
  async setWorkspaceMark(workspace: string, emoji: string, icon: string): Promise<void> { await this.#ops.workspaceRename({ workspace, emoji, icon }); }
  /** The workspace's own relays, the whole list (cloud directory.ts setRelays). */
  async setRelays(workspace: string, relays: string[]): Promise<void> { await this.#ops.workspaceSetRelays({ workspace, relays }); }
  async deleteWorkspace(workspace: string): Promise<void> { await this.#ops.workspaceDelete({ workspace }); }
  /** Leaving a workspace is removing oneself. */
  async removeMember(workspace: string, member: string): Promise<void> { await this.#ops.workspaceRemoveMember({ workspace, member }); }
  async setRole(workspace: string, member: string, role: string): Promise<void> { await this.#ops.workspaceSetRole({ workspace, member, role }); }
  /** Adds people by email: members at once, or from their first sign-in; no invitation to accept. */
  async addMembers(workspace: string, role: string, emails: string[]): Promise<AddedMembers> {
    const r = await this.#ops.workspaceAddMembers<Record<string, unknown>>({ workspace, role, emails });
    const list = (key: string) => (Array.isArray(r[key]) ? (r[key] as unknown[]).map(String) : []);
    return new AddedMembers(list("joined"), list("added"), list("already"));
  }
  /** An email added and not signed in yet, taken off. */
  async removeAdded(workspace: string, email: string): Promise<void> { await this.#ops.workspaceRemoveAdded({ workspace, email }); }
  async revokeInvitation(workspace: string, invitation: string): Promise<void> { await this.#ops.workspaceRevokeInvitation({ workspace, invitation }); }
  /** A one-time token for a machine to join as a station: the installer's command, and the command for a machine that has ember. */
  async enroll(workspace: string, name: string): Promise<Enrollment> {
    const r = await this.#ops.workspaceEnroll<{ install: string; command: string }>({ workspace, name });
    return new Enrollment(String(r.install), String(r.command));
  }
  async renameStation(workspace: string, station: string, name: string): Promise<void> { await this.#ops.workspaceRenameStation({ workspace, station, name }); }
  /** Its icon and emoji together (web/src/stationPick.ts); "" takes either away. */
  async setStationMark(workspace: string, station: string, emoji: string, icon: string): Promise<void> {
    await this.#ops.workspaceRenameStation({ workspace, station, emoji, icon });
  }
  async removeStation(workspace: string, station: string): Promise<void> { await this.#ops.workspaceRemoveStation({ workspace, station }); }
  async revokeLoginSession(id: string): Promise<void> { await this.#ops.loginSessionRevoke({ id }); }
  /** What an invitation link leads to, for the account looking: the workspace, the role, who invited, whose email it is for. */
  async previewInvitation(token: string): Promise<InvitationPreview> { return await this.#ops.invitationPreview<InvitationPreview>({ token }); }
  /** Accepts an invitation by its link's token; answers the workspace joined. */
  async acceptInvitationToken(token: string): Promise<string> { return String((await this.#ops.invitationAccept<{ id: string }>({ token })).id); }
}

export interface InvitationPreview { workspace: string; name: string; role?: string; inviter?: string; email?: string | null }

export class Enrollment {
  constructor(readonly install: string, readonly command: string) {}
}

/** The permission groups a new Slack app is made with (web/src/pages/SlackApp.tsx → GROUPS), all on. */
const SLACK_GROUPS = ["base", "public", "dm", "customize", "files", "reactions", "channels", "people", "extras", "canvases", "lists", "topics", "usergroups", "search", "connect", "more"];

// still.fail cloud's invite-code errors in words; the core passes their codes through.
const INVITE_ERRORS: Record<string, string> = {
  get invite_code_required() { return t("android-misc.invite.codeRequired"); },
  get invite_code_invalid() { return t("android-misc.invite.codeInvalid"); },
  get invite_code_used() { return t("android-misc.invite.codeUsed"); },
  get invite_code_expired() { return t("android-misc.invite.codeExpired"); },
};

/** Whether creating a workspace failed for want of a (good) invite code. */
export function needsInviteCode(e: CoreError | null | undefined): boolean {
  return e != null && e.code in INVITE_ERRORS;
}

// Its limits: what an account may create, and how many a workspace holds (web/src/cloud/api.ts LIMIT_ERRORS).
const LIMIT_ERRORS: Record<string, string> = {
  get too_many_workspaces() { return t("android-misc.limit.workspaces"); },
  get too_many_members() { return t("android-misc.limit.members"); },
};

/** What a failure says: still.fail cloud's codes in words, else the core's message. */
export function errorText(e: CoreError): string {
  return (e.code in INVITE_ERRORS ? INVITE_ERRORS[e.code] : undefined) ?? (e.code in LIMIT_ERRORS ? LIMIT_ERRORS[e.code] : undefined) ?? e.message;
}

/** A chat of another workspace a text refers to (`chat.outsideRefs`): `may`, whether the viewer may share it (its starter, or an owner or admin there). */
export interface OutsideRef { station: string; id: string; title: string; workspace: string; workspaceName: string; may: boolean }

/** A folder zipped on the station (`drive.zip`): read as any file of the drive is, by its root and path. */
export interface DriveZip { root: string; path: string; name: string; size: number }
