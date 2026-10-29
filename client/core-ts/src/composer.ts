// What is being written in a chat, as the core keeps it (the `composer` topic, by the draft's key: `<station>:<chat>`,
// `new:<workspace>` the workspace's new chat, whichever station it is to run on, `decision:…` a reply to one): its
// words, the passages quoted, the files going up to the station (the core uploads them, and says how far; a new
// chat's wait here and go up with its first message, to the station it goes to), whether it can be sent, and what went
// wrong. Each chat has its own while the page shows another; what is in it is kept on the device as the chat's draft
// (the `draft` topic), and read back from there the first time it is asked for. The pages only draw it and say what was
// done.
//
// The words are typed in the page, which has them at once: what it sends (`composer.text`) comes back in the topic's
// `text` without the page taking it again; the core's own words for it (read back, taken to send, put back, carried
// on) come with a new `rev`, which the page shows.
import { Deferred, Effect } from "effect";
import type { Inner } from "./core.ts";
import type { AccountDb } from "./db/account.ts";
import type { Call } from "./core/calls.ts";
import { handlers } from "./core/execute.ts";
import { asCoreError, CoreError } from "./error.ts";
import { t } from "./i18n.ts";
import { Beside, type Topic } from "./protocol.ts";
import { draftAt } from "./refs.ts";
import { StationAddr } from "./station/addr.ts";
import { isObject } from "./util.ts";
import { FileSource, isBlob } from "./file-source.ts";
import { outboxKeptId, sentKeptId } from "./drive-kept.ts";
import { shownSize } from "./imageSize.ts";
import { localId } from "./ids.ts";

type J = any;

/// A passage quoted, with what is said about it; `id` names it while it is written. Its picture, if it has one, is the
/// file that says it goes with it (`ComposerFile.quote`).
export type ComposerQuote = { id: string; author: string; text: string; comment: string; ts?: string; role?: string };

/// A file in what is written: going up (`sent` of `size`), up (`done`, as the station keeps it) or failed (`error`);
/// a new chat's waiting (`waits`) to go up with its message, to the station the message goes to (`take`). `pasted`:
/// long words pasted, kept as a file (what the page says of them). `ref`: one dragged in from where it is.
/// `link`: a link shared into the chat (share-in.ts), drawn as a file is and sent as words: nothing goes up.
/// `quote`: the quote it is the picture of (an image of a message quoted, a mark's screenshot): shown in its card, not
/// among the files, and out of the draft with it; the message names it in that quote (`file`).
export type ComposerFile = { id: string; name: string; size: number; sent?: number; width?: number; height?: number; done: J | null; error: string | null; waits?: true; pasted?: J; ref?: ComposerRef; link?: ComposerLink; quote?: string };

/// A link in what is written, as a file is: where it goes, what the app that shared it called it, and its site.
export type ComposerLink = { url: string; title?: string; site?: string };

/// What a link in what is written goes as: its title on a line, then where it goes.
const linkWords = (link: ComposerLink) => (link.title ? `${link.title}\n${link.url}` : link.url);

/// A quote as the page says it, its picture said apart (`attachment`, `composer.add`'s `quote`).
const quoteOf = (q: J, id: string): ComposerQuote => ({
  id, author: String(q.author ?? ""), text: String(q.text ?? ""), comment: typeof q.comment === "string" ? q.comment : "",
  ...(typeof q.ts === "string" && q.ts ? { ts: q.ts } : {}), ...(typeof q.role === "string" && q.role ? { role: q.role } : {}),
});

/// A quote as a message has it: its picture named by the name its file goes as (`file`), among the message's files.
function sentQuote({ id, ...q }: ComposerQuote, files: ComposerFile[]): J {
  const own = files.find((f) => f.quote === id);
  return { ...q, ...(own ? { file: String(own.done?.name ?? own.name) } : {}) };
}

/// The files up, each once (the same image quoted twice is one file of the message).
function upOnce(files: ComposerFile[]): J[] {
  const up = new Map<string, J>();
  for (const f of files) if (f.done && !up.has(f.done.path)) up.set(f.done.path, f.done);
  return [...up.values()];
}

/// Nothing of it goes up: named by its path, or a link.
const named = (f: ComposerFile) => f.ref?.mode === "path" || f.link !== undefined;

/// A new chat's draft: where it runs is known only as its first message goes, so its files wait for that.
const fresh = (key: string) => key.startsWith("new:");

/// Not waiting any more: going up.
const going = ({ waits: _, ...f }: ComposerFile): ComposerFile => f;

/// A file or folder dragged in from where it is (a station's files, or Finder on a machine that is a station): named by
/// its path (`mode: "path"`: the message says which station has it and where, nothing goes up), or sent (`file`: it goes
/// up to the chat's station as a picked one would; a folder of the chat's own station zipped there first).
export type ComposerRef = { station: string; stationName: string; path: string; dir: boolean; mode: "path" | "file" };

/// A file handed to the core to send up: the page's id for it, and the file itself (`blob`), or where it is in a
/// station's drive (`drive`: the chat's station copies it among its uploads; another station's is read from there and
/// sent up as a picked one would be). A folder named by its path has neither.
/// `kept`: its bytes are those kept on the device as it went up before (`outbox`, drive-kept.ts), not kept again.
/// `quote`: the quote it is the picture of (a mark's screenshot), when that quote is in the draft.
export type FileIn = { id: string; name: string; size: number; blob?: Blob | FileSource; pasted?: J; drive?: { station?: string; root: string; path: string }; ref?: ComposerRef; kept?: boolean; quote?: string };

type State = {
  /// Cached only for the account database it was read from.
  db: AccountDb | undefined;
  /// The last content edit, excluding upload progress and focus/status changes.
  edited: number;
  /// The station key already joined to this original key.
  joined: string | null;
  /// The words as typed (what the page last said, or the core's own).
  text: string;
  /// How many times the core has set the words itself.
  rev: number;
  quotes: ComposerQuote[];
  /// The quote just added, whose comment takes the focus.
  focus: string | null;
  files: ComposerFile[];
  starting: boolean;
  error: string | null;
  /// Every change, counted: a page waits for the one it made before taking the topic's value again.
  version: number;
  /// What was taken to send, until it is sent or put back.
  taken: { text: string; quotes: ComposerQuote[]; files: ComposerFile[]; id: string } | null;
  /// The draft's own name ("" until asked for: `#id`), kept with it on the device: what is written to a chat between
  /// two sends is one draft, and the next is another (taken to send, or put back empty). What goes up from it is named
  /// by it (the station gives back an upload it finished within the hour by its id), so the same file in the next
  /// message, or in another new chat, is another upload.
  id: string;
};

/// Bigger files are not sent: the station would refuse them.
export const MAX_FILE = 1024 * 1024 * 1024;
/// How much of a file goes up in one part.
const PART = 4 * 1024 * 1024;
/// How much more of a file has gone before it is said again, at the least.
const SENT_STEP = 64 * 1024;
/// The biggest file kept on the device as it goes up with a message (`outbox`, drive-kept.ts), and once it is up
/// (`keepSent`): a bigger one whose source the app no longer has (it ended meanwhile) fails, to be added again, and its
/// chat reads it from its station.
const KEEP_OUTBOX_MOST = 256 * 1024 * 1024;

/// A file sent up from here, kept on the device as it is, a part at a time, under the name its station keeps it by
/// (drive-kept.ts `sent`): its chat shows it, and opens it, from here, not read back from the station it went to. One
/// that could not be read again whole is not kept (its chat reads it from its station).
function keepSent(inner: Inner, station: string, path: string, blob: Blob | FileSource, size: number): Effect.Effect<void> {
  const name = path.split("/").at(-1)!;
  const id = sentKeptId(station, name);
  const keep = Effect.gen(function* () {
    for (let at = 0; at < size; at += PART) {
      const bytes = new Uint8Array(yield* Effect.tryPromise({ try: () => blob.slice(at, at + PART).arrayBuffer(), catch: asCoreError }));
      if (bytes.length !== Math.min(PART, size - at)) return yield* Effect.fail(new CoreError("upload", t("core-misc.composer.upload_missing", { name })));
      yield* inner.driveKept.keep(id, "sent", 0, size, blob.type, at, bytes);
    }
  });
  return Effect.flatMap(Effect.result(keep), (kept) => (kept._tag === "Failure" ? inner.driveKept.forget(id) : Effect.void));
}

const topicOf = (key: string): Topic => ({ topic: "composer", key });
const empty = (db?: AccountDb): State => ({ db, edited: 0, joined: null, text: "", rev: 0, quotes: [], focus: null, files: [], starting: false, error: null, version: 0, taken: null, id: "" });
const draftKey = (station: string, chat: string) => chat === "new" ? `new:${station}` : `${station}:${chat}`;

export class Composers {
  #inner: Inner;
  #all = new Map<string, State>();
  #edits = 0;
  #uploads = new Map<string, { station: string; file: FileIn | null; done: Deferred.Deferred<J, CoreError>; error: boolean }>();
  /// Files named by their path, kept to send up should they be switched to files (`mode`), by id.
  #held = new Map<string, { station: string; file: FileIn }>();
  /// A new chat's files as they were handed over, by id, until they leave its draft: each goes up from here to the
  /// station its message goes to (`take`), again should that change once it has (the draft put back).
  #sources = new Map<string, FileIn>();
  /// Images' sizes as read here, by upload id, until the upload is let go: a message the page sent before it heard of
  /// one is given it all the same (`sizeOf`).
  #sizes = new Map<string, { width: number; height: number }>();
  /// How much of each the station has, by upload id, while it goes up: a message sent part way through starts from there
  /// (`sentOf`).
  #sent = new Map<string, number>();

  constructor(inner: Inner) {
    this.#inner = inner;
  }

  /// The topic's value: what is written in `key`, read from the chat's draft the first time.
  value(key: string): unknown {
    const s = this.#state(key);
    const uploading = s.files.some((f) => !f.done && !f.error && !f.waits && !named(f));
    const ready = (s.text.trim() !== "" || s.files.some((f) => !f.error) || s.quotes.length > 0) && !s.starting && !s.files.some((f) => f.pasted && f.error);
    // Nothing said for what is not (yet): a file not up has no `done`, one not failed no `error`.
    const shown = ({ done, error, quote: _, ...f }: ComposerFile) => ({ ...f, ...(done !== null ? { done } : {}), ...(error !== null ? { error } : {}) });
    return {
      text: s.text, rev: s.rev, ...(s.focus !== null ? { focus: s.focus } : {}),
      // A quote's picture in it, not among the files.
      quotes: s.quotes.map((q) => {
        const own = s.files.find((f) => f.quote === q.id);
        return own ? { ...q, own: shown(own) } : q;
      }),
      files: s.files.filter((f) => f.quote === undefined).map(shown),
      uploading, ready, starting: s.starting, ...(s.error !== null ? { error: s.error } : {}), version: s.version,
    };
  }

  /// A chat made here keeps one composer under its original key. Its page uses that key until reload, then the
  /// station's session key; the persisted creation record connects them even before the station is reached again.
  #keys(key: string): string[] {
    const at = draftAt(key);
    if (!at) return [key];
    const [station, session] = at;
    const local = this.#inner.views.local;
    const original = local.pendingKey(station, session);
    if (!original) return [key];
    const pending = local.pending(original);
    if (pending?.station !== station || !pending.made) return [key];
    return [`${station}:${original}`, `${station}:${pending.made[0]}`];
  }

  #state(key: string): State {
    const keys = this.#keys(key);
    key = keys[0]!;
    const before = this.#cached(key);
    const alias = keys[1];
    if (!alias) {
      if (before) return before;
      const s = this.#read(key);
      this.#all.set(key, s);
      return s;
    }
    const other = this.#cached(alias);
    if (before?.joined === alias && !other) return before;
    // Both names may have been opened before the creation reply connected them. Keep the latest actual edit,
    // including a send that emptied it; an empty subscription or a file's progress must not displace that edit.
    const savedAlias = this.#kept(alias);
    const s = before && before.edited > (other?.edited ?? 0) ? before
      : other && other.edited > 0 ? other
      // Older clients left later drafts under the station key after reload. With no live edits, that copy wins.
      : isObject(savedAlias) ? (other ?? this.#from(savedAlias, this.#db(key)))
      : (before ?? this.#read(key));
    s.rev = Math.max(s.rev, before?.rev ?? 0, other?.rev ?? 0) + 1;
    s.version = Math.max(s.version, before?.version ?? 0, other?.version ?? 0) + 1;
    s.joined = alias;
    this.#all.set(key, s);
    this.#all.delete(alias);
    // Consolidate in one database burst. Also cancel either delayed write, so it cannot resurrect the old copy.
    this.#forget(key);
    this.#save(key, s, true);
    this.#forget(alias);
    this.#tell(keys);
    return s;
  }

  #db(key: string): AccountDb | undefined {
    const at = draftAt(key);
    return at ? this.#inner.data.of(at[0]) : undefined;
  }

  #cached(key: string): State | undefined {
    const s = this.#all.get(key);
    if (s && s.db !== this.#db(key)) {
      this.#all.delete(key);
      return undefined;
    }
    return s;
  }

  #kept(key: string): unknown {
    const at = draftAt(key);
    return at ? this.#inner.data.get({ topic: "draft", station: at[0], chat: at[1] }) : undefined;
  }

  #read(key: string): State {
    return this.#from(this.#kept(key) ?? this.#before(key), this.#db(key));
  }

  /// A workspace's new chat's draft as it was kept before it had one whatever its station (by `new:<station>`): the
  /// one of the station it was to start on, moved under its own key.
  #before(key: string): unknown {
    const at = draftAt(key);
    if (!at || at[1] !== "new" || at[0].includes("/")) return undefined;
    const id = this.#inner.choose.keptStation(at[0]);
    const old = { topic: "draft", station: `${at[0]}/${id}`, chat: "new" };
    const kept = id !== "" ? this.#inner.data.get(old) : undefined;
    if (!isObject(kept)) return undefined;
    this.#inner.data.set({ topic: "draft", station: at[0], chat: "new" }, kept, false);
    this.#inner.data.forgetTopic(old);
    return kept;
  }

  #from(kept: unknown, db: AccountDb | undefined): State {
    const s = empty(db);
    if (!isObject(kept)) return s;
    s.text = typeof kept.text === "string" ? kept.text : "";
    if (s.text) s.rev = 1;
    s.files = (Array.isArray(kept.files) ? kept.files : []).filter(isObject).map((f: J) => ({ id: localId("kept"), name: String(f.name ?? ""), size: Number(f.size ?? 0), done: f, error: null }));
    // A new chat's waiting, by the id its bytes are kept on the device under (`#wait`).
    for (const w of Array.isArray(kept.waiting) ? kept.waiting : []) {
      if (!isObject(w) || typeof w.id !== "string") continue;
      const size = typeof w.width === "number" && typeof w.height === "number" ? { width: w.width, height: w.height } : {};
      s.files.push({ id: w.id, name: String(w.name ?? ""), size: Number(w.size ?? 0), ...size, done: null, error: null, waits: true, ...(isObject(w.pasted) ? { pasted: w.pasted } : {}) });
    }
    s.quotes = (Array.isArray(kept.quotes) ? kept.quotes : []).filter(isObject).map((q: J) => {
      const quote = quoteOf(q, localId("kept"));
      // Its picture: the file it names, each quote its own (the same image quoted twice is a file each).
      const named = typeof q.file === "string" && q.file ? s.files.find((f) => f.name === q.file) : undefined;
      if (named && named.quote === undefined) named.quote = quote.id;
      else if (named) s.files.push({ ...named, id: localId("kept"), quote: quote.id });
      return quote;
    });
    if (typeof kept.id === "string") s.id = kept.id;
    for (const l of Array.isArray(kept.links) ? kept.links : []) {
      if (isObject(l) && typeof l.url === "string") s.files.push(linkFile(localId("kept"), l as ComposerLink));
    }
    return s;
  }

  #draft(s: State) {
    const links = s.files.flatMap((f) => (f.link ? [f.link] : []));
    const waiting = s.files.filter((f) => f.waits).map(({ id, name, size, width, height, pasted }) => ({ id, name, size, ...(width && height ? { width, height } : {}), ...(pasted ? { pasted } : {}) }));
    return { text: s.text, quotes: s.quotes.map((q) => sentQuote(q, s.files)), files: upOnce(s.files), ...(waiting.length ? { waiting } : {}), ...(links.length ? { links } : {}), ...(s.id ? { id: s.id } : {}) };
  }

  /// The draft's name, given the first time it is asked for (`State.id`): the core's, as its other names are (random:
  /// a count would name another draft the same after a restart), and said with the draft, so a replay has it as it was.
  #id(s: State): string {
    if (s.id === "") s.id = localId("draft");
    return s.id;
  }

  #forget(key: string): void {
    const at = draftAt(key);
    if (at) this.#inner.data.forgetTopic({ topic: "draft", station: at[0], chat: at[1] });
  }

  #save(key: string, s: State, immediate = false): void {
    const at = draftAt(key);
    if (!at || s.db !== this.#db(key)) return;
    const topic = { topic: "draft", station: at[0], chat: at[1] };
    const draft = this.#draft(s);
    if (!draft.text.trim() && draft.quotes.length === 0 && draft.files.length === 0 && !draft.waiting && !draft.links) this.#inner.data.forgetTopic(topic);
    else if (immediate) this.#inner.data.set(topic, draft, false);
    else this.#inner.data.setSoon(topic, draft);
  }

  /// The creation reply arrived: join any live composers before their next edit or upload update.
  made(station: string, key: string): void {
    this.#state(`${station}:${key}`);
  }

  /// The draft API (including native clients) reads and replaces the same state as the web composer.
  readDraft(station: string, chat: string) {
    const s = this.#state(draftKey(station, chat));
    this.#id(s);
    const draft = this.#draft(s);
    if (!draft.text.trim() && draft.quotes.length === 0 && draft.files.length === 0 && !draft.waiting) draft.text = "";
    return draft;
  }

  /// The draft as the page has it now; its name kept (whatever the page says of it), or, put back empty (sent, or all of
  /// it taken out), a new one for what is written next. Answers the name.
  putDraft(station: string, chat: string, value: unknown): { id: string } {
    const key = this.#keys(draftKey(station, chat))[0]!;
    const was = this.#state(key);
    const s = this.#from(value, was.db);
    const blank = !s.text.trim() && s.quotes.length === 0 && s.files.length === 0 && !s.files.some((f) => f.link);
    if (blank) s.text = "";
    s.id = blank ? "" : this.#id(was);
    this.#id(s);
    s.rev = was.rev + 1;
    s.version = was.version;
    s.joined = was.joined;
    this.release(was.files);
    this.#all.set(key, s);
    this.#changed(key, s);
    return { id: s.id };
  }

  /// A change made: the topic told, the chat's draft kept (written a moment after its last change).
  #changed(key: string, s: State, count = true, edited = true): number {
    if (edited) s.edited = ++this.#edits;
    if (count) s.version++;
    const keys = this.#keys(key);
    this.#tell(keys);
    this.#save(keys[0]!, s);
    return s.version;
  }

  #tell(keys: string[]): void {
    for (const key of keys) {
      this.#inner.store.invalidate(topicOf(key));
      const at = draftAt(key);
      if (at) this.#inner.store.invalidate({ topic: "draft", station: at[0], chat: at[1] });
    }
  }

  /// The core's own words for it: shown in place of what was typed.
  #say(s: State, text: string): void {
    s.text = text;
    s.rev++;
  }

  text(key: string, text: string): number {
    const s = this.#state(key);
    if (s.text === text) return s.version;
    s.text = text;
    // Not counted: the page has the words already (and waits for no answer to them).
    return this.#changed(key, s, false);
  }

  /// Words added after what is written (a visualization's, a pasted text put back), on a line of their own.
  append(key: string, words: string): number {
    const s = this.#state(key);
    this.#say(s, s.text.trim() ? `${s.text.trimEnd()}\n${words}` : words);
    return this.#changed(key, s);
  }

  /// A link shared into it (share-in.ts), after the files it has, unless it has that link already: drawn as a file is,
  /// sent as words after what is written.
  link(key: string, link: ComposerLink): number {
    const s = this.#state(key);
    if (s.files.some((f) => f.link?.url === link.url)) return s.version;
    s.files = [...s.files, linkFile(localId("link"), link)];
    return this.#changed(key, s);
  }

  /// Words put after what is written, as `append`, unless it has them already (shared into the chat once more).
  offer(key: string, words: string): number {
    const s = this.#state(key);
    if (s.text.includes(words.trim())) return s.version;
    return this.append(key, words);
  }

  /// A passage quoted; or a file of a message (`attachment`, already on the station: it goes again with the message,
  /// nothing goes up; `fileId`, the page's id for it), its picture.
  quote(key: string, quote: ComposerQuote, focus: boolean, attachment?: J, fileId?: string): number {
    const s = this.#state(key);
    s.quotes = [...s.quotes, quote];
    if (attachment) {
      s.files = [...s.files, { id: fileId ?? localId("quoted"), name: String(attachment.name ?? ""), size: Number(attachment.size ?? 0), done: attachment, error: null, quote: quote.id }];
    }
    if (focus) s.focus = quote.id;
    return this.#changed(key, s);
  }

  comment(key: string, id: string, comment: string): number {
    const s = this.#state(key);
    s.quotes = s.quotes.map((q) => (q.id === id ? { ...q, comment } : q));
    return this.#changed(key, s);
  }

  /// A quote taken out, its picture with it.
  unquote(key: string, id: string): number {
    const s = this.#state(key);
    const own = s.files.filter((f) => f.quote === id);
    s.quotes = s.quotes.filter((q) => q.id !== id);
    s.files = s.files.filter((f) => f.quote !== id);
    this.release(own);
    if (s.focus === id) s.focus = null;
    return this.#changed(key, s);
  }

  focused(key: string): number {
    const s = this.#state(key);
    if (s.focus === null) return s.version;
    s.focus = null;
    return this.#changed(key, s, true, false);
  }

  error(key: string, error: string | null): number {
    const s = this.#state(key);
    if (s.error === error) return s.version;
    s.error = error;
    return this.#changed(key, s, true, false);
  }

  starting(key: string, starting: boolean): number {
    const s = this.#state(key);
    if (s.starting === starting) return s.version;
    s.starting = starting;
    return this.#changed(key, s, true, false);
  }

  /// Files picked, pasted or dropped: each goes up to `station` at once, and waits there in no chat until a message
  /// takes it; a new chat's waits here, to go up with its message (`#wait`). Too big, it says so and does not go.
  add(key: string, station: string, files: FileIn[]): number {
    const s = this.#state(key);
    for (let f of files) {
      if (fresh(key)) {
        // (one of a station's drive: of the one it was dragged from, whichever the message goes to)
        if (f.drive && f.drive.station === undefined) f = { ...f, drive: { ...f.drive, station } };
        this.#sources.set(f.id, f);
      }
      const ref = f.ref ? { ...f.ref, mode: f.ref.dir && !zippable(f, station) ? "path" as const : f.ref.mode } : undefined;
      if (ref?.mode === "path") {
        // Named by its path: nothing goes up unless it is switched to a file.
        s.files = [...s.files, { id: f.id, name: f.name, size: f.size, done: null, error: null, ref }];
        this.#held.set(f.id, { station, file: f });
        continue;
      }
      const tooBig = f.size > MAX_FILE;
      const quote = f.quote !== undefined && s.quotes.some((q) => q.id === f.quote) ? { quote: f.quote } : {};
      const waits = !tooBig && fresh(key) ? { waits: true as const } : {};
      s.files = [...s.files, { id: f.id, name: f.name, size: f.size, done: null, error: tooBig ? t("core-misc.composer.too_big") : null, ...waits, ...(f.pasted ? { pasted: f.pasted } : {}), ...(ref ? { ref } : {}), ...quote }];
      if (tooBig) { if (f.blob instanceof FileSource) f.blob.close(); }
      else if (fresh(key)) this.#wait(f);
      else this.#upload(key, station, f);
    }
    return this.#changed(key, s);
  }

  /// A file dragged in, named by its path or sent: switched to a file, it goes up (once: back to a path and to a file
  /// again, what went up is taken); a new chat's waits to go with its message.
  mode(key: string, id: string, mode: "path" | "file"): number {
    const s = this.#state(key);
    const f = s.files.find((x) => x.id === id);
    const held = this.#held.get(id);
    if (!f?.ref || f.ref.mode === mode || (mode === "file" && f.ref.dir && !(held && zippable(held.file, held.station)))) return s.version;
    const ref = { ...f.ref, mode };
    s.files = s.files.map((x) => (x.id === id ? (mode === "path" ? going({ ...x, ref }) : { ...x, ref }) : x));
    if (mode === "file" && !this.#uploads.has(id)) {
      if (!held) s.files = s.files.map((x) => (x.id === id ? { ...x, error: t("core-misc.composer.upload_missing", { name: x.name }) } : x));
      else if (f.size > MAX_FILE) s.files = s.files.map((x) => (x.id === id ? { ...x, error: t("core-misc.composer.too_big") } : x));
      else if (fresh(key)) {
        s.files = s.files.map((x) => (x.id === id ? { ...x, waits: true } : x));
        this.#wait(this.#sources.get(id) ?? held.file);
      } else this.#upload(key, held.station, held.file);
    }
    return this.#changed(key, s);
  }

  /// A file that failed to go up, sent up again from what was kept of it (a failed upload keeps its source). One that
  /// never went (too big, its source gone) stays as it is.
  retry(key: string, id: string): number {
    const s = this.#state(key);
    const upload = this.#uploads.get(id);
    if (!upload?.error || !upload.file || !s.files.some((x) => x.id === id && x.error !== null)) return s.version;
    s.files = s.files.map((x) => {
      if (x.id !== id) return x;
      const { sent: _, ...rest } = x;
      return { ...rest, error: null };
    });
    this.#upload(key, upload.station, upload.file);
    return this.#changed(key, s);
  }

  remove(key: string, id: string): number {
    const s = this.#state(key);
    s.files = s.files.filter((f) => f.id !== id);
    this.release([{ id }]);
    return this.#changed(key, s);
  }

  /// One file going up, a part at a time (the station goes on from what it has); its place in whichever composer it
  /// is in by then said as it goes.
  #upload(key: string, station: string, f: FileIn): void {
    const inner = this.#inner;
    const upload = { station, file: f as FileIn | null, done: Deferred.makeUnsafe<J, CoreError>(), error: false };
    this.#uploads.set(f.id, upload);
    const id = Array.from(crypto.getRandomValues(new Uint8Array(12)), (b) => b.toString(16).padStart(2, "0")).join("");
    // Gone up again to another station since (a new chat's, `take`): what this one does says nothing of the file.
    const replaced = () => this.#uploads.has(f.id) && this.#uploads.get(f.id) !== upload;
    const change = (patch: Partial<ComposerFile>) => { if (!replaced()) this.#patch(f.id, patch); };
    // How far it has gone: in the composer, and in a message sent before it is up (one sent later starts from here). Said
    // as the bytes go, a step at a time (a big file's at most some 200 times: a waiting message is kept on each).
    const step = Math.max(SENT_STEP, Math.ceil(f.size / 200));
    let said = -1;
    const went = (sent: number) => {
      if (replaced() || (sent !== f.size && said >= 0 && Math.abs(sent - said) < step)) return;
      said = sent;
      if (this.#uploads.get(f.id) === upload) this.#sent.set(f.id, sent);
      change({ sent });
      inner.views.local.uploadChanged(f.id, { sent });
    };
    // An image's or a film's size, read while it goes up: every page holds its place from the first (the outbox's row
    // too, before it is up, even when it was sent before its size was read), and it travels with the file.
    // Another station's file: read from there a part at a time, as a picked one is read from the page.
    const elsewhere = f.drive?.station !== undefined && f.drive.station !== station ? f.drive : null;
    const blob = f.blob ?? (elsewhere ? remoteSource(inner, elsewhere as { station: string; root: string; path: string }, f.size) : undefined);
    if (f.drive && !elsewhere) {
      const drive = f.drive;
      inner.runner.fork(
        Effect.flatMap(Effect.try({ try: () => StationAddr.parse(station), catch: asCoreError }), (addr) => inner.stations.requests.driveStage(addr, drive.root, drive.path, null, f.ref?.dir === true)).pipe(
          Effect.match({
            onSuccess: (done) => { upload.file = null; change({ sent: f.size, done }); Deferred.doneUnsafe(upload.done, Effect.succeed(done)); },
            onFailure: (e) => { upload.error = true; change({ error: e.message || t("core-misc.composer.upload_failed") }); Deferred.doneUnsafe(upload.done, Effect.fail(e)); },
          }),
        ),
      );
      return;
    }
    // A file from here kept whole on the device, with what it is, read through beside its going up (not as it goes: the
    // app ended part way up, what had gone was all there was, and its message failed all the same, pengxiao
    // 2026-10-25): its message goes on from it should the app end before it is sent (`fromKept`). Kept already when it
    // is that; no more once it is up or let go.
    const noted = { station, name: f.name, size: f.size, type: f.blob?.type ?? "" };
    const keeping = f.blob !== undefined && f.kept !== true && f.size > 0 && f.size <= KEEP_OUTBOX_MOST;
    if (keeping) this.#keepWhole(f, noted, () => this.#uploads.get(f.id) === upload && upload.file !== null);
    const kept = keeping || f.kept === true;
    // (read once: a new chat's was as it was added)
    const sizing: Promise<{ width: number; height: number } | null> = this.#sizes.has(f.id) ? Promise.resolve(this.#sizes.get(f.id)!)
      : (isBlob(blob) || blob instanceof FileSource) ? this.#measure(f.id, blob) : Promise.resolve(null);
    const run = Effect.gen(function* () {
      const addr = yield* Effect.try({ try: () => StationAddr.parse(station), catch: asCoreError });
      let have = 0;
      let saved: J;
      // Nothing yet, out of its size: said at once.
      went(0);
      // Named first: a station that has it already (sent before) copies its own, and nothing more goes. Only one here
      // (another station's would be read across for it).
      const local = f.blob;
      const named = local && f.size > 0 ? yield* Effect.promise(() => inner.stations.requests.uploadName(local, f.size)) : null;
      if (named) {
        const had = yield* Effect.orElseSucceed(inner.stations.requests.uploadHave(addr, { id, name: f.name, size: f.size, sha256: named }, null), () => null);
        if (had !== null) { saved = had; went(f.size); }
      }
      while (saved === undefined) {
        if (!blob) return yield* Effect.fail(new CoreError("upload", t("core-misc.composer.upload_missing", { name: f.name })));
        const bytes = new Uint8Array(yield* Effect.tryPromise({ try: () => blob.slice(have, have + PART).arrayBuffer(), catch: asCoreError }));
        const from = have;
        const told = yield* inner.stations.requests.uploadPart(addr, { id, name: f.name, size: f.size, offset: have }, bytes, null, (n) => went(from + n));
        if (told.file !== undefined) saved = told.file;
        else if (told.have === have) return yield* Effect.fail(new CoreError("upload", t("core-misc.composer.upload_failed")));
        else have = told.have;
        went(told.file !== undefined ? f.size : have);
      }
      const path = isObject(saved) ? saved.path : undefined;
      const size = yield* Effect.promise(() => sizing);
      if (size) saved = { ...saved, ...size };
      // What its station said written down for its message (before the message can take it and let it go).
      const ours = kept && !replaced();
      if (ours) yield* inner.driveKept.noteUpload(f.id, { ...noted, done: saved });
      // Kept on the device as it went, whatever it is, before its message can name it, so its chat neither reads it back
      // nor waits for it: the bytes kept for its message, kept on as that once they are all there, else read again.
      const sent = typeof path === "string" && f.size > 0 && f.size <= KEEP_OUTBOX_MOST ? path : null;
      const moved = sent !== null && ours && (yield* inner.driveKept.rename(outboxKeptId(f.id), sentKeptId(station, sent.split("/").at(-1)!), "sent", f.size));
      if (!moved) {
        if (ours) yield* inner.driveKept.forget(outboxKeptId(f.id));
        if (sent !== null && local) yield* keepSent(inner, station, sent, local, f.size);
      }
      return saved;
    });
    inner.runner.fork(
      run.pipe(
        Effect.match({
          onSuccess: (done) => {
            upload.file = null;
            // Put up from here: every message it goes with says which upload it was, the same file to the pages before
            // it was up and after, whenever it was sent.
            if (f.blob) inner.views.local.uploadedHere(station, isObject(done) ? done.path : undefined, f.id);
            change({ done });
            Deferred.doneUnsafe(upload.done, Effect.succeed(done));
          },
          onFailure: (e) => {
            upload.error = true;
            change({ error: e.message || t("core-misc.composer.upload_failed") });
            Deferred.doneUnsafe(upload.done, Effect.fail(e));
          },
        }),
        // A failed upload retains its source for the outbox's retry; a new chat's file, until it leaves the draft.
        // Success or interruption releases it.
        Effect.ensuring(Effect.sync(() => { if (!upload.error && f.blob instanceof FileSource && this.#sources.get(f.id)?.blob !== f.blob) f.blob.close(); })),
      ),
    );
    void key;
  }

  /// What is said of a file, in whichever composer it is in by then (and in what was taken of it, to be put back).
  #patch(id: string, patch: Partial<ComposerFile>): void {
    for (const [k, s] of this.#all) {
      if (s.db !== this.#db(k)) continue;
      if (s.taken?.files.some((x) => x.id === id)) s.taken.files = s.taken.files.map((x) => x.id === id ? { ...x, ...patch } : x);
      if (!s.files.some((x) => x.id === id)) continue;
      s.files = s.files.map((x) => (x.id === id ? { ...x, ...patch } : x));
      this.#changed(k, s, true, false);
    }
  }

  /// An image's or a film's size, read from what its bytes say first (a few of them, at once: imageSize.ts), decoded
  /// only when they do not say, and only where this can (Hermes cannot): every page holds its place from the first (the
  /// outbox's row too, before it is up, even when it was sent before its size was read), and it travels with the file.
  /// The desktop's and the phone's cores have the file as a FileSource (file-port.ts, the host's), read a part at a time:
  /// the same way here.
  #measure(id: string, b: Blob | FileSource): Promise<{ width: number; height: number } | null> {
    if (!b.type.startsWith("image/") && !b.type.startsWith("video/")) return Promise.resolve(null);
    const decoded = () => typeof createImageBitmap === "function" && b.type.startsWith("image/")
      ? (isBlob(b) ? Promise.resolve(b) : Promise.all(Array.from({ length: Math.ceil(b.size / PART) }, (_, i) => b.slice(i * PART, (i + 1) * PART).arrayBuffer()))
        .then((parts) => new Blob(parts, { type: b.type })))
        .then((whole) => createImageBitmap(whole)).then((m) => { const s = { width: m.width, height: m.height }; m.close(); return s; })
      : null;
    return shownSize((start, end) => b.slice(start, end).arrayBuffer().then((part) => new Uint8Array(part)), b.size).then((s) => s ?? decoded()).then((s) => {
      // (not for one let go meanwhile)
      if (s && (this.#uploads.has(id) || this.#sources.has(id))) {
        this.#sizes.set(id, s);
        this.#patch(id, s);
        this.#inner.views.local.uploadChanged(id, s);
      }
      return s;
    }, () => null);
  }

  /// A file's bytes kept whole on the device, a part at a time while `still`, with what it is (`noted`): what its
  /// message goes up from should the app end first (`#fromKept`).
  #keepWhole(f: FileIn, noted: { station: string; name: string; size: number; type: string }, still: () => boolean): void {
    const inner = this.#inner;
    const source = f.blob!;
    inner.runner.fork(Effect.gen(function* () {
      yield* inner.driveKept.noteUpload(f.id, noted);
      for (let at = 0; at < f.size && still(); at += PART) {
        const bytes = yield* Effect.orElseSucceed(Effect.tryPromise({ try: () => source.slice(at, at + PART).arrayBuffer(), catch: asCoreError }), () => null);
        if (bytes === null || !still()) return;
        yield* inner.driveKept.keep(outboxKeptId(f.id), "outbox", 0, f.size, noted.type, at, new Uint8Array(bytes));
      }
    }));
  }

  /// A new chat's file waiting for its message: kept whole on the device while it is in the draft, for no station yet
  /// (its draft comes back with it should the app end; one too big to keep is added again), its size read.
  #wait(f: FileIn): void {
    const blob = f.blob;
    if (!blob) return;
    if (f.size > 0 && f.size <= KEEP_OUTBOX_MOST) this.#keepWhole(f, { station: "", name: f.name, size: f.size, type: blob.type }, () => this.#sources.get(f.id)?.blob === blob);
    void this.#measure(f.id, blob);
  }

  /// Outgoing messages hold file ids, independently of the composer or the page that submitted them: one a new chat's
  /// draft holds still goes up now, to the message's station. After a core restart the source Blob is gone: fail visibly
  /// rather than sending an incomplete message.
  uploaded(station: string, files: { id: string; name: string }[], retry = false): Effect.Effect<J[], CoreError> {
    return Effect.forEach(files, (f) => Effect.suspend(() => {
      let upload = this.#uploads.get(f.id);
      const source = this.#sources.get(f.id);
      if (!upload && source) {
        this.#upload("", station, { ...source, kept: true });
        upload = this.#uploads.get(f.id)!;
      }
      if (!upload || upload.station !== station) return this.#fromKept(station, f);
      if (retry && upload.error && upload.file) {
        this.#upload("", station, upload.file);
        upload = this.#uploads.get(f.id)!;
      }
      return Deferred.await(upload.done);
    }));
  }

  /// A message's file this core did not set going (the app ended since), from what was kept of it as it went: what its
  /// station said once it was up, else sent up again from its bytes kept whole; else it fails, to be added again.
  #fromKept(station: string, f: { id: string; name: string }): Effect.Effect<J, CoreError> {
    const inner = this.#inner;
    const missing = new CoreError("upload", t("core-misc.composer.upload_missing", { name: f.name }));
    return Effect.gen({ self: this }, function* () {
      const noted = yield* inner.driveKept.uploadNoted(f.id);
      // (a new chat's kept as it waited: for whichever station its message goes to)
      if (!isObject(noted) || (noted.station !== station && noted.station !== "") || typeof noted.size !== "number") return yield* Effect.fail(missing);
      if (noted.done !== undefined && noted.done !== null && noted.station === station) return noted.done as J;
      const id = outboxKeptId(f.id);
      const size = noted.size;
      const type = typeof noted.type === "string" ? noted.type : "";
      if (!(yield* inner.driveKept.whole(id, size))) return yield* Effect.fail(missing);
      const read = (start: number, end: number) => Effect.runPromise(inner.driveKept.read(id, 0, size, start, end - start)).then((got) => {
        if (got === null) throw missing;
        return got.bytes.buffer.slice(got.bytes.byteOffset, got.bytes.byteOffset + got.bytes.byteLength) as ArrayBuffer;
      });
      // (another call for it meanwhile: the one it set going)
      if (!this.#uploads.has(f.id)) this.#upload("", station, { id: f.id, name: f.name, size, blob: new FileSource(size, type, read, () => {}), kept: true });
      return yield* Deferred.await(this.#uploads.get(f.id)!.done);
    });
  }

  /// An image's or a film's size as read here (`{}` while it is not), for a message that takes it.
  sizeOf(id: string): { width?: number; height?: number } {
    return this.#sizes.get(id) ?? {};
  }

  /// How much of a file the station has so far (`{}` before its first part), for a message that takes it.
  sentOf(id: string): { sent?: number } {
    const sent = this.#sent.get(id);
    return sent !== undefined ? { sent } : {};
  }

  /// A picture of the draft the page holds no bytes of (a draft kept, read again as the app starts): as this device
  /// keeps it, up as it went (`keepSent`), else one waiting or going up as it is kept for its message
  /// (`#keepWhole`); null where none is kept here (drawn as any other file).
  picture(key: string, id: string): Effect.Effect<Beside | null> {
    const s = this.#state(key);
    const f = [...s.files, ...(s.taken?.files ?? [])].find((x) => x.id === id);
    if (!f || f.pasted || f.link) return Effect.succeed(null);
    const inner = this.#inner;
    const station = draftAt(key)?.[0];
    const path = isObject(f.done) && typeof f.done.path === "string" ? f.done.path : "";
    const sent = station && path ? inner.driveKept.held(sentKeptId(station, path.split("/").at(-1)!)) : Effect.succeed(null);
    return Effect.map(
      Effect.flatMap(sent, (got) => (got !== null ? Effect.succeed(got) : inner.driveKept.held(outboxKeptId(id)))),
      (got) => (got !== null && got.type.startsWith("image/") ? new Beside({ type: got.type }, got.bytes) : null),
    );
  }

  release(files: { id: string }[]): void {
    for (const f of files) {
      this.#unkeep(f.id);
      this.#sizes.delete(f.id);
      this.#sent.delete(f.id);
      const held = this.#held.get(f.id)?.file.blob;
      if (held instanceof FileSource && this.#uploads.get(f.id)?.file?.blob !== held) held.close();
      this.#held.delete(f.id);
      const source = this.#uploads.get(f.id)?.file?.blob;
      if (source instanceof FileSource) source.close();
      this.#uploads.delete(f.id);
      this.#inner.runner.fork(this.#inner.driveKept.dropUpload(f.id));
    }
  }

  /// A new chat's file out of its draft: what it was read from let go, unless what sends it up reads from it still.
  #unkeep(id: string): void {
    const kept = this.#sources.get(id)?.blob;
    this.#sources.delete(id);
    if (kept instanceof FileSource && kept !== this.#uploads.get(id)?.file?.blob && kept !== this.#held.get(id)?.file.blob) kept.close();
  }

  /// What is written, taken to be sent (the words trimmed), the composer left empty; `restore` puts it back. Its files
  /// as they are at this moment, each one way: up, as the station keeps it (`attachments`), or still going up
  /// (`uploads`: its message waits for it). The page sends them as said here, not as it last drew them: one up in
  /// between went as both, and twice. `station`, the one the message goes to: a new chat's files go up there now, each a
  /// file still going up.
  take(key: string, station: string | null = null): { text: string; attachments: J[]; quotes: J[]; uploads: { id: string; name: string; size: number }[]; version: number } {
    const s = this.#state(key);
    if (station !== null) s.files = s.files.map((f) => this.#toward(f, station));
    const taken = { text: s.text, quotes: s.quotes, files: s.files, id: this.#id(s) };
    s.taken = taken;
    // what is written next is another draft
    s.id = "";
    this.#say(s, "");
    s.quotes = [];
    s.files = [];
    s.error = null;
    s.focus = null;
    const version = this.#changed(key, s);
    // Links and those named by their path go as words, after what is written: each link, then where each file is.
    const links = taken.files.flatMap((f) => (f.link ? [f.link] : []));
    const paths = taken.files.filter((f) => f.ref?.mode === "path");
    const sent = taken.files.filter((f) => !named(f));
    // (one up goes as the station has it: nothing more is read of it)
    for (const f of sent) if (f.done) this.#unkeep(f.id);
    return {
      text: [taken.text.trim(), ...links.map(linkWords), ...paths.map((f) => pathWords(f.ref!))].filter((w) => w !== "").join("\n"),
      attachments: upOnce(sent),
      quotes: taken.quotes.map((q) => sentQuote({ ...q, comment: q.comment.trim() }, sent)),
      uploads: sent.filter((f) => !f.done && !f.error).map(({ id, name, size }) => ({ id, name, size })),
      version,
    };
  }

  /// A new chat's file as its message goes to `station`: one waiting goes up there now (after a restart, from its bytes
  /// kept here); one up, or going up, to another (its station changed as the draft was put back) up there again.
  #toward(f: ComposerFile, station: string): ComposerFile {
    if (named(f)) return f;
    const kept = this.#sources.get(f.id);
    if (f.waits) {
      if (kept) this.#upload("", station, { ...kept, kept: true });
      else this.#inner.runner.fork(Effect.ignore(this.#fromKept(station, f), { log: "Unhandled", message: "draft file read back" }));
      return going(f);
    }
    const upload = this.#uploads.get(f.id);
    if (!kept || !upload || upload.station === station) return f;
    this.#upload("", station, { ...kept, kept: true });
    const { sent: _, ...rest } = f;
    return { ...rest, done: null, error: null };
  }

  /// What was taken comes back (a chat that could not be made, a message never sent), saying why; with `unlessWritten`,
  /// only while nothing new is written there.
  restore(key: string, error: string | null, unlessWritten: boolean): number {
    const s = this.#state(key);
    const back = s.taken;
    if (!back) return s.version;
    if (unlessWritten && (s.text.trim() || s.files.length || s.quotes.length)) return s.version;
    s.taken = null;
    this.#say(s, back.text);
    s.quotes = back.quotes;
    s.files = back.files;
    s.id = back.id;
    s.error = error;
    return this.#changed(key, s);
  }

  /// What is written in `from` goes on into `to` (a new chat becoming the chat it made), `from` left empty.
  carry(from: string, to: string): number {
    from = this.#keys(from)[0]!;
    to = this.#keys(to)[0]!;
    const s = this.#state(from);
    if (from === to) return s.version;
    // Counted on from where `to` was: what was shown of it before is older than this.
    const was = this.#state(to);
    const next = { ...empty(was.db), joined: was.joined, text: s.text, rev: was.rev + 1, quotes: s.quotes, files: s.files, version: was.version, id: s.id };
    this.#all.set(to, next);
    this.#all.set(from, { ...empty(s.db), joined: s.joined, rev: s.rev + 1, version: s.version });
    this.#changed(from, this.#all.get(from)!);
    return this.#changed(to, next);
  }
}

/// Whether a folder dragged in can be sent as a file: one of the chat's own station's drive, zipped there.
const zippable = (f: FileIn, station: string) => !!f.drive && (f.drive.station === undefined || f.drive.station === station);

/// Where a file named by its path is, as the message says it: its station's name and its path there.
/// A link as a file of what is written.
function linkFile(id: string, link: ComposerLink): ComposerFile {
  return { id, name: link.title || link.url, size: 0, done: null, error: null, link };
}

export const pathWords = (ref: ComposerRef) => t(ref.dir ? "common.folderOn" : "common.pathOn", { station: ref.stationName, path: ref.path });

/// Another station's file read from its drive a part at a time (`drive.read`), to be sent up to the chat's station.
function remoteSource(inner: Inner, at: { station: string; root: string; path: string }, size: number): FileSource {
  const addr = StationAddr.parse(at.station);
  return new FileSource(size, "", (start, end) => Effect.runPromise(inner.stations.requests.driveRead(addr, at.root, at.path, start, end - start, null)).then((got) => {
    const bytes = got.bytes;
    return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength) as ArrayBuffer;
  }), () => {});
}

// ── the calls ──

const str = (p: unknown, k: string): string => {
  const v = isObject(p) ? (p as Record<string, unknown>)[k] : undefined;
  if (typeof v !== "string" || v === "") throw CoreError.invalid(t("core-misc.params.missing", { field: k }));
  return v;
};
const strOr = (p: unknown, k: string): string | null => {
  const v = isObject(p) ? (p as Record<string, unknown>)[k] : undefined;
  return typeof v === "string" ? v : null;
};

/// `composer.*`: parsed here, run by `install`'s handler.
export function parseComposer(name: string, params: unknown): Call | null {
  if (!name.startsWith("composer.")) return null;
  const what = name.slice("composer.".length);
  const p = isObject(params) ? (params as Record<string, unknown>) : {};
  const key = str(p, "key");
  switch (what) {
    case "text":
      return { kind: "composer", key, act: { text: strOr(p, "text") ?? "" } };
    case "append":
      return { kind: "composer", key, act: { append: str(p, "words") } };
    case "quote": {
      const q = p.quote;
      if (!isObject(q) || typeof q.author !== "string" || typeof q.text !== "string") throw CoreError.invalid(t("core-misc.params.missing", { field: "quote" }));
      const quote = quoteOf(q, str(p, "id"));
      const attachment = isObject(p.attachment) && typeof (p.attachment as J).path === "string" ? p.attachment as J : undefined;
      const fileId = typeof p.fileId === "string" && p.fileId !== "" ? p.fileId : undefined;
      return { kind: "composer", key, act: { quote, focus: p.focus === true, ...(attachment ? { attachment, ...(fileId ? { fileId } : {}) } : {}) } };
    }
    case "comment":
      return { kind: "composer", key, act: { comment: str(p, "id"), words: strOr(p, "comment") ?? "" } };
    case "unquote":
      return { kind: "composer", key, act: { unquote: str(p, "id") } };
    case "focused":
      return { kind: "composer", key, act: { focused: true } };
    case "error":
      return { kind: "composer", key, act: { error: strOr(p, "error") } };
    case "starting":
      return { kind: "composer", key, act: { starting: p.starting === true } };
    case "add": {
      const files = Array.isArray(p.files) ? p.files : [];
      const list = files.map((f: J) => {
        const x = f as J;
        if (!isObject(f) || typeof x.id !== "string") throw CoreError.invalid(t("core-misc.params.missing", { field: "files" }));
        // Dragged in from where it is: named by its path, or sent.
        const r = x.ref;
        const ref = isObject(r) && typeof r.station === "string" && typeof r.path === "string"
          ? { ref: { station: r.station, stationName: typeof r.stationName === "string" ? r.stationName : r.station, path: r.path, dir: r.dir === true, mode: r.mode === "file" ? "file" as const : "path" as const } }
          : {};
        // A file of a station's drive: where it is (its station, when not the chat's).
        if (isObject(x.drive) && typeof x.drive.root === "string" && typeof x.drive.path === "string") {
          const drive = { ...(typeof x.drive.station === "string" ? { station: x.drive.station } : {}), root: x.drive.root, path: x.drive.path };
          // The file itself too, when the page has it (one from Finder): sent up from there to another station.
          const blob = isBlob(x.blob) || x.blob instanceof FileSource ? { blob: x.blob } : {};
          return { id: x.id, name: typeof x.name === "string" ? x.name : x.drive.path.split("/").at(-1) ?? "", size: typeof x.size === "number" ? x.size : 0, drive, ...blob, ...ref } as FileIn;
        }
        // A folder named by its path, with no drive to zip it from: nothing to send.
        if (ref.ref?.dir) return { id: x.id, name: typeof x.name === "string" ? x.name : "", size: 0, ...ref } as FileIn;
        if (!(isBlob(x.blob) || x.blob instanceof FileSource)) throw CoreError.invalid(t("core-misc.params.missing", { field: "files" }));
        return { id: x.id, name: typeof x.name === "string" ? x.name : x.blob.name ?? "", size: typeof x.size === "number" ? x.size : x.blob.size, blob: x.blob, ...(isObject(x.pasted) ? { pasted: x.pasted } : {}), ...(typeof x.quote === "string" ? { quote: x.quote } : {}), ...ref } as FileIn;
      });
      return { kind: "composer", key, act: { add: list, station: str(p, "station") } };
    }
    case "remove":
      return { kind: "composer", key, act: { remove: str(p, "id") } };
    case "retry":
      return { kind: "composer", key, act: { retry: str(p, "id") } };
    case "mode":
      return { kind: "composer", key, act: { mode: str(p, "mode") === "file" ? "file" : "path", file: str(p, "id") } };
    case "take":
      return { kind: "composer", key, act: { take: true, station: strOr(p, "station") || null } };
    case "restore":
      return { kind: "composer", key, act: { restore: true, error: strOr(p, "error"), unlessWritten: p.unlessWritten === true } };
    case "carry":
      return { kind: "composer", key, act: { carry: str(p, "to") } };
    case "picture":
      return { kind: "composer", key, act: { picture: str(p, "id") } };
  }
  throw CoreError.invalid(`unknown call: ${name}`);
}

/// What a `composer.*` call does.
export type ComposerAct =
  | { text: string } | { append: string } | { quote: ComposerQuote; focus: boolean; attachment?: J; fileId?: string } | { comment: string; words: string }
  | { unquote: string } | { focused: true } | { error: string | null } | { starting: boolean } | { add: FileIn[]; station: string }
  | { remove: string } | { retry: string } | { mode: "path" | "file"; file: string } | { take: true; station: string | null } | { restore: true; error: string | null; unlessWritten: boolean } | { carry: string }
  | { picture: string };

export function install(): void {
  handlers.composer = (inner, call) => {
    const c = call as Extract<Call, { kind: "composer" }>;
    const all = inner.composers;
    const a = c.act;
    // (its bytes beside the answer, read from what the device keeps)
    if ("picture" in a) return all.picture(c.key, a.picture);
    return Effect.sync(() => {
      if ("text" in a) return { version: all.text(c.key, a.text) };
      if ("append" in a) return { version: all.append(c.key, a.append) };
      if ("quote" in a) return { version: all.quote(c.key, a.quote, a.focus, a.attachment, a.fileId) };
      if ("comment" in a) return { version: all.comment(c.key, a.comment, a.words) };
      if ("unquote" in a) return { version: all.unquote(c.key, a.unquote) };
      if ("focused" in a) return { version: all.focused(c.key) };
      if ("error" in a && !("restore" in a)) return { version: all.error(c.key, a.error) };
      if ("starting" in a) return { version: all.starting(c.key, a.starting) };
      if ("add" in a) return { version: all.add(c.key, a.station, a.add) };
      if ("remove" in a) return { version: all.remove(c.key, a.remove) };
      if ("retry" in a) return { version: all.retry(c.key, a.retry) };
      if ("mode" in a) return { version: all.mode(c.key, a.file, a.mode) };
      if ("take" in a) return all.take(c.key, a.station);
      if ("restore" in a) return { version: all.restore(c.key, a.error, a.unlessWritten) };
      if ("carry" in a) return { version: all.carry(c.key, a.carry) };
      return null;
    });
  };
}
