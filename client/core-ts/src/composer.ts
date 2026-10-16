// What is being written in a chat, as the core keeps it (the `composer` topic, by the draft's key: `<station>:<chat>`,
// `new:<station>` a new chat there, `decision:…` a reply to one): its words, the passages quoted, the files going up
// to the station (the core uploads them, and says how far), whether it can be sent, and what went wrong. Each chat has
// its own while the page shows another; what is in it is kept on the device as the chat's draft (the `draft` topic),
// and read back from there the first time it is asked for. The pages only draw it and say what was done.
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
import type { Topic } from "./protocol.ts";
import { draftAt } from "./refs.ts";
import { StationAddr } from "./station/addr.ts";
import { isObject } from "./util.ts";
import { FileSource } from "./file-source.ts";
import { headerSize } from "./imageSize.ts";

type J = any;

/// A passage quoted, with what is said about it; `id` names it while it is written.
export type ComposerQuote = { id: string; author: string; text: string; comment: string; ts?: string; role?: string; file?: string };

/// A file in what is written: going up (`sent` of `size`), up (`done`, as the station keeps it) or failed (`error`).
/// `pasted`: long words pasted, kept as a file (what the page says of them). `ref`: one dragged in from where it is.
export type ComposerFile = { id: string; name: string; size: number; sent?: number; width?: number; height?: number; done: J | null; error: string | null; pasted?: J; ref?: ComposerRef };

/// A file or folder dragged in from where it is (a station's files, or Finder on a machine that is a station): named by
/// its path (`mode: "path"`: the message says which station has it and where, nothing goes up), or sent (`file`: it goes
/// up to the chat's station as a picked one would; a folder of the chat's own station zipped there first).
export type ComposerRef = { station: string; stationName: string; path: string; dir: boolean; mode: "path" | "file" };

/// A file handed to the core to send up: the page's id for it, and the file itself (`blob`), or where it is in a
/// station's drive (`drive`: the chat's station copies it among its uploads; another station's is read from there and
/// sent up as a picked one would be). A folder named by its path has neither.
export type FileIn = { id: string; name: string; size: number; blob?: Blob | FileSource; pasted?: J; drive?: { station?: string; root: string; path: string }; ref?: ComposerRef };

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
  taken: { text: string; quotes: ComposerQuote[]; files: ComposerFile[] } | null;
};

/// Bigger files are not sent: the station would refuse them.
export const MAX_FILE = 1024 * 1024 * 1024;
/// How much of a file goes up in one part.
const PART = 4 * 1024 * 1024;

const topicOf = (key: string): Topic => ({ topic: "composer", key });
const empty = (db?: AccountDb): State => ({ db, edited: 0, joined: null, text: "", rev: 0, quotes: [], focus: null, files: [], starting: false, error: null, version: 0, taken: null });
const draftKey = (station: string, chat: string) => chat === "new" ? `new:${station}` : `${station}:${chat}`;

export class Composers {
  #inner: Inner;
  #all = new Map<string, State>();
  #edits = 0;
  #keptId = 0;
  #uploads = new Map<string, { station: string; file: FileIn | null; done: Deferred.Deferred<J, CoreError>; error: boolean }>();
  /// Files named by their path, kept to send up should they be switched to files (`mode`), by id.
  #held = new Map<string, { station: string; file: FileIn }>();
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
    const uploading = s.files.some((f) => !f.done && !f.error && f.ref?.mode !== "path");
    const ready = (s.text.trim() !== "" || s.files.some((f) => !f.error) || s.quotes.length > 0) && !s.starting && !s.files.some((f) => f.pasted && f.error);
    return {
      text: s.text, rev: s.rev, quotes: s.quotes, ...(s.focus !== null ? { focus: s.focus } : {}),
      // Nothing said for what is not (yet): a file not up has no `done`, one not failed no `error`.
      files: s.files.map(({ done, error, ...f }) => ({ ...f, ...(done !== null ? { done } : {}), ...(error !== null ? { error } : {}) })),
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
    return this.#from(this.#kept(key), this.#db(key));
  }

  #from(kept: unknown, db: AccountDb | undefined): State {
    const s = empty(db);
    if (!isObject(kept)) return s;
    s.text = typeof kept.text === "string" ? kept.text : "";
    if (s.text) s.rev = 1;
    s.quotes = (Array.isArray(kept.quotes) ? kept.quotes : []).filter(isObject).map((q: J) => ({ ...q, id: `kept-${this.#keptId++}` }) as ComposerQuote);
    s.files = (Array.isArray(kept.files) ? kept.files : []).filter(isObject).map((f: J) => ({ id: `kept-${this.#keptId++}`, name: String(f.name ?? ""), size: Number(f.size ?? 0), done: f, error: null }));
    return s;
  }

  #draft(s: State) {
    return { text: s.text, quotes: s.quotes.map(({ id: _, ...q }) => q), files: s.files.flatMap((f) => f.done ? [f.done] : []) };
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
    if (!draft.text.trim() && draft.quotes.length === 0 && draft.files.length === 0) this.#inner.data.forgetTopic(topic);
    else if (immediate) this.#inner.data.set(topic, draft, false);
    else this.#inner.data.setSoon(topic, draft);
  }

  /// The creation reply arrived: join any live composers before their next edit or upload update.
  made(station: string, key: string): void {
    this.#state(`${station}:${key}`);
  }

  /// The draft API (including native clients) reads and replaces the same state as the web composer.
  readDraft(station: string, chat: string) {
    const draft = this.#draft(this.#state(draftKey(station, chat)));
    if (!draft.text.trim() && draft.quotes.length === 0 && draft.files.length === 0) draft.text = "";
    return draft;
  }

  putDraft(station: string, chat: string, value: unknown): void {
    const key = this.#keys(draftKey(station, chat))[0]!;
    const was = this.#state(key);
    const s = this.#from(value, was.db);
    if (!s.text.trim() && s.quotes.length === 0 && s.files.length === 0) s.text = "";
    s.rev = was.rev + 1;
    s.version = was.version;
    s.joined = was.joined;
    this.release(was.files);
    this.#all.set(key, s);
    this.#changed(key, s);
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

  quote(key: string, quote: ComposerQuote, focus: boolean): number {
    const s = this.#state(key);
    s.quotes = [...s.quotes, quote];
    if (focus) s.focus = quote.id;
    return this.#changed(key, s);
  }

  comment(key: string, id: string, comment: string): number {
    const s = this.#state(key);
    s.quotes = s.quotes.map((q) => (q.id === id ? { ...q, comment } : q));
    return this.#changed(key, s);
  }

  unquote(key: string, id: string): number {
    const s = this.#state(key);
    s.quotes = s.quotes.filter((q) => q.id !== id);
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
  /// takes it. Too big, it says so and does not go.
  add(key: string, station: string, files: FileIn[]): number {
    const s = this.#state(key);
    for (const f of files) {
      const ref = f.ref ? { ...f.ref, mode: f.ref.dir && !zippable(f, station) ? "path" as const : f.ref.mode } : undefined;
      if (ref?.mode === "path") {
        // Named by its path: nothing goes up unless it is switched to a file.
        s.files = [...s.files, { id: f.id, name: f.name, size: f.size, done: null, error: null, ref }];
        this.#held.set(f.id, { station, file: f });
        continue;
      }
      const tooBig = f.size > MAX_FILE;
      s.files = [...s.files, { id: f.id, name: f.name, size: f.size, done: null, error: tooBig ? t("core-misc.composer.too_big") : null, ...(f.pasted ? { pasted: f.pasted } : {}), ...(ref ? { ref } : {}) }];
      if (!tooBig) this.#upload(key, station, f);
      else if (f.blob instanceof FileSource) f.blob.close();
    }
    return this.#changed(key, s);
  }

  /// A file dragged in, named by its path or sent: switched to a file, it goes up (once: back to a path and to a file
  /// again, what went up is taken).
  mode(key: string, id: string, mode: "path" | "file"): number {
    const s = this.#state(key);
    const f = s.files.find((x) => x.id === id);
    const held = this.#held.get(id);
    if (!f?.ref || f.ref.mode === mode || (mode === "file" && f.ref.dir && !(held && zippable(held.file, held.station)))) return s.version;
    const ref = { ...f.ref, mode };
    s.files = s.files.map((x) => (x.id === id ? { ...x, ref } : x));
    if (mode === "file" && !this.#uploads.has(id)) {
      if (!held) s.files = s.files.map((x) => (x.id === id ? { ...x, error: t("core-misc.composer.upload_missing", { name: x.name }) } : x));
      else if (f.size > MAX_FILE) s.files = s.files.map((x) => (x.id === id ? { ...x, error: t("core-misc.composer.too_big") } : x));
      else this.#upload(key, held.station, held.file);
    }
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
    const change = (patch: Partial<ComposerFile>) => {
      for (const [k, s] of this.#all) {
        if (s.db !== this.#db(k)) continue;
        if (s.taken?.files.some((x) => x.id === f.id)) s.taken.files = s.taken.files.map((x) => x.id === f.id ? { ...x, ...patch } : x);
        if (!s.files.some((x) => x.id === f.id)) continue;
        s.files = s.files.map((x) => (x.id === f.id ? { ...x, ...patch } : x));
        this.#changed(k, s, true, false);
      }
    };
    // How far it has gone: in the composer, and in a message sent before it is up (one sent later starts from here).
    const went = (sent: number) => {
      if (this.#uploads.get(f.id) === upload) this.#sent.set(f.id, sent);
      change({ sent });
      inner.views.local.uploadChanged(f.id, { sent });
    };
    // An image's size, read while it goes up: every page holds its place from the first (the outbox's row too, before it
    // is up, even when it was sent before its size was read), and it travels with the file.
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
    // Its header first (a few bytes, at once); decoded only when that does not say.
    const decoded = (b: Blob) => typeof createImageBitmap === "function"
      ? createImageBitmap(b).then((m) => { const s = { width: m.width, height: m.height }; m.close(); return s; })
      : null;
    const sizing: Promise<{ width: number; height: number } | null> = blob instanceof Blob && blob.type.startsWith("image/")
      ? blob.slice(0, 64).arrayBuffer().then((head) => headerSize(new Uint8Array(head)) ?? decoded(blob)).then((s) => {
        if (s) {
          if (this.#uploads.get(f.id) === upload) this.#sizes.set(f.id, s);
          change(s);
          inner.views.local.uploadChanged(f.id, s);
        }
        return s;
      }, () => null)
      : Promise.resolve(null);
    const run = Effect.gen(function* () {
      const addr = yield* Effect.try({ try: () => StationAddr.parse(station), catch: asCoreError });
      let have = 0;
      let saved: J;
      while (saved === undefined) {
        if (!blob) return yield* Effect.fail(new CoreError("upload", t("core-misc.composer.upload_missing", { name: f.name })));
        const bytes = new Uint8Array(yield* Effect.tryPromise({ try: () => blob.slice(have, have + PART).arrayBuffer(), catch: asCoreError }));
        const told = yield* inner.stations.requests.uploadPart(addr, { id, name: f.name, size: f.size, offset: have }, bytes, null);
        if (told.file !== undefined) saved = told.file;
        else if (told.have === have) return yield* Effect.fail(new CoreError("upload", t("core-misc.composer.upload_failed")));
        else have = told.have;
        went(told.file !== undefined ? f.size : have);
      }
      const size = yield* Effect.promise(() => sizing);
      if (size) saved = { ...saved, ...size };
      return saved;
    });
    inner.runner.fork(
      run.pipe(
        Effect.match({
          onSuccess: (done) => { upload.file = null; change({ done }); Deferred.doneUnsafe(upload.done, Effect.succeed(done)); },
          onFailure: (e) => {
            upload.error = true;
            change({ error: e.message || t("core-misc.composer.upload_failed") });
            Deferred.doneUnsafe(upload.done, Effect.fail(e));
          },
        }),
        // A failed upload retains its source for the outbox's retry. Success or interruption releases it.
        Effect.ensuring(Effect.sync(() => { if (!upload.error && f.blob instanceof FileSource) f.blob.close(); })),
      ),
    );
    void key;
  }

  /// Outgoing messages hold file ids, independently of the composer or the page that submitted them.
  /// After a core restart the source Blob is gone: fail visibly rather than sending an incomplete message.
  uploaded(station: string, files: { id: string; name: string }[], retry = false): Effect.Effect<J[], CoreError> {
    return Effect.forEach(files, (f) => Effect.suspend(() => {
      let upload = this.#uploads.get(f.id);
      if (!upload || upload.station !== station) return Effect.fail(new CoreError("upload", t("core-misc.composer.upload_missing", { name: f.name })));
      if (retry && upload.error && upload.file) {
        this.#upload("", station, upload.file);
        upload = this.#uploads.get(f.id)!;
      }
      return Deferred.await(upload.done);
    }));
  }

  /// An image's size as read here (`{}` while it is not), for a message that takes it.
  sizeOf(id: string): { width?: number; height?: number } {
    return this.#sizes.get(id) ?? {};
  }

  /// How much of a file the station has so far (`{}` before its first part), for a message that takes it.
  sentOf(id: string): { sent?: number } {
    const sent = this.#sent.get(id);
    return sent !== undefined ? { sent } : {};
  }

  release(files: { id: string }[]): void {
    for (const f of files) {
      this.#sizes.delete(f.id);
      this.#sent.delete(f.id);
      const held = this.#held.get(f.id)?.file.blob;
      if (held instanceof FileSource && this.#uploads.get(f.id)?.file?.blob !== held) held.close();
      this.#held.delete(f.id);
      const source = this.#uploads.get(f.id)?.file?.blob;
      if (source instanceof FileSource) source.close();
      this.#uploads.delete(f.id);
    }
  }

  /// What is written, taken to be sent (the words trimmed), the composer left empty; `restore` puts it back.
  take(key: string): { text: string; attachments: J[]; quotes: J[]; files: string[]; version: number } {
    const s = this.#state(key);
    const taken = { text: s.text, quotes: s.quotes, files: s.files };
    s.taken = taken;
    this.#say(s, "");
    s.quotes = [];
    s.files = [];
    s.error = null;
    s.focus = null;
    const version = this.#changed(key, s);
    // Those named by their path go as words, after what is written: where each is.
    const named = taken.files.filter((f) => f.ref?.mode === "path");
    const sent = taken.files.filter((f) => f.ref?.mode !== "path");
    return {
      text: [taken.text.trim(), ...named.map((f) => pathWords(f.ref!))].filter((w) => w !== "").join("\n"),
      attachments: sent.flatMap((f) => (f.done ? [f.done] : [])),
      quotes: taken.quotes.map(({ author, text, comment, ts, role, file }) => ({ author, text, comment: comment.trim(), ...(ts ? { ts } : {}), ...(role ? { role } : {}), ...(file ? { file } : {}) })),
      files: sent.map((f) => f.id),
      version,
    };
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
    const next = { ...empty(was.db), joined: was.joined, text: s.text, rev: was.rev + 1, quotes: s.quotes, files: s.files, version: was.version };
    this.#all.set(to, next);
    this.#all.set(from, { ...empty(s.db), joined: s.joined, rev: s.rev + 1, version: s.version });
    this.#changed(from, this.#all.get(from)!);
    return this.#changed(to, next);
  }

  /// A new chat moved to another station: what is written goes with it; files stay with the station they went up to.
  move(from: string, to: string): number {
    const a = this.#state(from);
    const b = this.#state(to);
    if (a === b) return b.version;
    b.quotes = [...b.quotes, ...a.quotes];
    if (a.text) this.#say(b, a.text);
    b.error = null;
    a.quotes = [];
    this.#say(a, "");
    this.#changed(from, a);
    return this.#changed(to, b);
  }
}

/// Whether a folder dragged in can be sent as a file: one of the chat's own station's drive, zipped there.
const zippable = (f: FileIn, station: string) => !!f.drive && (f.drive.station === undefined || f.drive.station === station);

/// Where a file named by its path is, as the message says it: its station's name and its path there.
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
      const quote = { ...(q as J), id: str(p, "id"), comment: typeof q.comment === "string" ? q.comment : "" } as ComposerQuote;
      return { kind: "composer", key, act: { quote, focus: p.focus === true } };
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
          const blob = x.blob instanceof Blob || x.blob instanceof FileSource ? { blob: x.blob } : {};
          return { id: x.id, name: typeof x.name === "string" ? x.name : x.drive.path.split("/").at(-1) ?? "", size: typeof x.size === "number" ? x.size : 0, drive, ...blob, ...ref } as FileIn;
        }
        // A folder named by its path, with no drive to zip it from: nothing to send.
        if (ref.ref?.dir) return { id: x.id, name: typeof x.name === "string" ? x.name : "", size: 0, ...ref } as FileIn;
        if (!(x.blob instanceof Blob || x.blob instanceof FileSource)) throw CoreError.invalid(t("core-misc.params.missing", { field: "files" }));
        return { id: x.id, name: typeof x.name === "string" ? x.name : x.blob.name ?? "", size: typeof x.size === "number" ? x.size : x.blob.size, blob: x.blob, ...(isObject(x.pasted) ? { pasted: x.pasted } : {}), ...ref } as FileIn;
      });
      return { kind: "composer", key, act: { add: list, station: str(p, "station") } };
    }
    case "remove":
      return { kind: "composer", key, act: { remove: str(p, "id") } };
    case "mode":
      return { kind: "composer", key, act: { mode: str(p, "mode") === "file" ? "file" : "path", file: str(p, "id") } };
    case "take":
      return { kind: "composer", key, act: { take: true } };
    case "restore":
      return { kind: "composer", key, act: { restore: true, error: strOr(p, "error"), unlessWritten: p.unlessWritten === true } };
    case "carry":
      return { kind: "composer", key, act: { carry: str(p, "to") } };
    case "move":
      return { kind: "composer", key, act: { move: str(p, "to") } };
  }
  throw CoreError.invalid(`unknown call: ${name}`);
}

/// What a `composer.*` call does.
export type ComposerAct =
  | { text: string } | { append: string } | { quote: ComposerQuote; focus: boolean } | { comment: string; words: string }
  | { unquote: string } | { focused: true } | { error: string | null } | { starting: boolean } | { add: FileIn[]; station: string }
  | { remove: string } | { mode: "path" | "file"; file: string } | { take: true } | { restore: true; error: string | null; unlessWritten: boolean } | { carry: string } | { move: string };

export function install(): void {
  handlers.composer = (inner, call) => {
    const c = call as Extract<Call, { kind: "composer" }>;
    const all = inner.composers;
    const a = c.act;
    return Effect.sync(() => {
      if ("text" in a) return { version: all.text(c.key, a.text) };
      if ("append" in a) return { version: all.append(c.key, a.append) };
      if ("quote" in a) return { version: all.quote(c.key, a.quote, a.focus) };
      if ("comment" in a) return { version: all.comment(c.key, a.comment, a.words) };
      if ("unquote" in a) return { version: all.unquote(c.key, a.unquote) };
      if ("focused" in a) return { version: all.focused(c.key) };
      if ("error" in a && !("restore" in a)) return { version: all.error(c.key, a.error) };
      if ("starting" in a) return { version: all.starting(c.key, a.starting) };
      if ("add" in a) return { version: all.add(c.key, a.station, a.add) };
      if ("remove" in a) return { version: all.remove(c.key, a.remove) };
      if ("mode" in a) return { version: all.mode(c.key, a.file, a.mode) };
      if ("take" in a) return all.take(c.key);
      if ("restore" in a) return { version: all.restore(c.key, a.error, a.unlessWritten) };
      if ("carry" in a) return { version: all.carry(c.key, a.carry) };
      if ("move" in a) return { version: all.move(c.key, a.move) };
      return null;
    });
  };
}
