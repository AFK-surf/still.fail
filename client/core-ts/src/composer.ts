// What is being written in a chat, as the core keeps it (the `composer` topic, by the draft's key: `<station>:<chat>`,
// `new:<station>` a new chat there, `decision:…` a reply to one): its words, the passages quoted, the files going up
// to the station (the core uploads them, and says how far), whether it can be sent, and what went wrong. Each chat has
// its own while the page shows another; what is in it is kept on the device as the chat's draft (the `draft` topic),
// and read back from there the first time it is asked for. The pages only draw it and say what was done.
//
// The words are typed in the page, which has them at once: what it sends (`composer.text`) comes back in the topic's
// `text` without the page taking it again; the core's own words for it (read back, taken to send, put back, carried
// on) come with a new `rev`, which the page shows.
import { Effect } from "effect";
import type { Inner } from "./core.ts";
import type { Call } from "./core/calls.ts";
import { handlers } from "./core/execute.ts";
import { asCoreError, CoreError } from "./error.ts";
import { t } from "./i18n.ts";
import type { Topic } from "./protocol.ts";
import { draftAt } from "./refs.ts";
import { StationAddr } from "./station/addr.ts";
import { isObject } from "./util.ts";

type J = any;

/// A passage quoted, with what is said about it; `id` names it while it is written.
export type ComposerQuote = { id: string; author: string; text: string; comment: string; ts?: string; role?: string; file?: string };

/// A file in what is written: going up (`sent` of `size`), up (`done`, as the station keeps it) or failed (`error`).
/// `pasted`: long words pasted, kept as a file (what the page says of them).
export type ComposerFile = { id: string; name: string; size: number; sent?: number; done: J | null; error: string | null; pasted?: J };

/// A file handed to the core to send up: the page's id for it, the file itself.
export type FileIn = { id: string; name: string; size: number; blob: Blob; pasted?: J };

type State = {
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
const empty = (): State => ({ text: "", rev: 0, quotes: [], focus: null, files: [], starting: false, error: null, version: 0, taken: null });

export class Composers {
  #inner: Inner;
  #all = new Map<string, State>();

  constructor(inner: Inner) {
    this.#inner = inner;
  }

  /// The topic's value: what is written in `key`, read from the chat's draft the first time.
  value(key: string): unknown {
    const s = this.#state(key);
    const uploading = s.files.some((f) => !f.done && !f.error);
    const ready = (s.text.trim() !== "" || s.files.some((f) => f.done) || s.quotes.length > 0) && !uploading && !s.starting && !s.files.some((f) => f.pasted && f.error);
    return {
      text: s.text, rev: s.rev, quotes: s.quotes, ...(s.focus !== null ? { focus: s.focus } : {}),
      // Nothing said for what is not (yet): a file not up has no `done`, one not failed no `error`.
      files: s.files.map(({ done, error, ...f }) => ({ ...f, ...(done !== null ? { done } : {}), ...(error !== null ? { error } : {}) })),
      uploading, ready, starting: s.starting, ...(s.error !== null ? { error: s.error } : {}), version: s.version,
    };
  }

  #state(key: string): State {
    let s = this.#all.get(key);
    if (!s) {
      s = empty();
      const at = draftAt(key);
      const kept = at ? this.#inner.data.get({ topic: "draft", station: at[0], chat: at[1] }) : undefined;
      if (isObject(kept)) {
        const text = typeof kept.text === "string" ? kept.text : "";
        s.text = text;
        if (text) s.rev = 1;
        let n = 0;
        s.quotes = (Array.isArray(kept.quotes) ? kept.quotes : []).filter(isObject).map((q: J) => ({ ...q, id: `kept-${n++}` }) as ComposerQuote);
        s.files = (Array.isArray(kept.files) ? kept.files : []).filter(isObject).map((f: J) => ({ id: `kept-${n++}`, name: String(f.name ?? ""), size: Number(f.size ?? 0), done: f, error: null }));
      }
      this.#all.set(key, s);
    }
    return s;
  }

  /// A change made: the topic told, the chat's draft kept (written a moment after its last change).
  #changed(key: string, s: State, count = true): number {
    if (count) s.version++;
    this.#inner.store.invalidate(topicOf(key));
    const at = draftAt(key);
    if (at) {
      const topic = { topic: "draft", station: at[0], chat: at[1] };
      const quotes = s.quotes.map(({ id: _, ...q }) => q);
      const files = s.files.flatMap((f) => (f.done ? [f.done] : []));
      if (!s.text.trim() && quotes.length === 0 && files.length === 0) this.#inner.data.forgetTopic(topic);
      else this.#inner.data.setSoon(topic, { text: s.text, quotes, files });
    }
    return s.version;
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
    return this.#changed(key, s);
  }

  error(key: string, error: string | null): number {
    const s = this.#state(key);
    if (s.error === error) return s.version;
    s.error = error;
    return this.#changed(key, s);
  }

  starting(key: string, starting: boolean): number {
    const s = this.#state(key);
    if (s.starting === starting) return s.version;
    s.starting = starting;
    return this.#changed(key, s);
  }

  /// Files picked, pasted or dropped: each goes up to `station` at once, and waits there in no chat until a message
  /// takes it. Too big, it says so and does not go.
  add(key: string, station: string, files: FileIn[]): number {
    const s = this.#state(key);
    for (const f of files) {
      const tooBig = f.size > MAX_FILE;
      s.files = [...s.files, { id: f.id, name: f.name, size: f.size, done: null, error: tooBig ? t("core-misc.composer.too_big") : null, ...(f.pasted ? { pasted: f.pasted } : {}) }];
      if (!tooBig) this.#upload(key, station, f);
    }
    return this.#changed(key, s);
  }

  remove(key: string, id: string): number {
    const s = this.#state(key);
    s.files = s.files.filter((f) => f.id !== id);
    return this.#changed(key, s);
  }

  /// One file going up, a part at a time (the station goes on from what it has); its place in whichever composer it
  /// is in by then said as it goes.
  #upload(key: string, station: string, f: FileIn): void {
    const inner = this.#inner;
    const id = Array.from(crypto.getRandomValues(new Uint8Array(12)), (b) => b.toString(16).padStart(2, "0")).join("");
    const change = (patch: Partial<ComposerFile>) => {
      for (const [k, s] of this.#all) {
        if (!s.files.some((x) => x.id === f.id)) continue;
        s.files = s.files.map((x) => (x.id === f.id ? { ...x, ...patch } : x));
        this.#changed(k, s);
      }
    };
    const run = Effect.gen(function* () {
      const addr = yield* Effect.try({ try: () => StationAddr.parse(station), catch: asCoreError });
      let have = 0;
      let saved: J;
      while (saved === undefined) {
        const bytes = new Uint8Array(yield* Effect.promise(() => f.blob.slice(have, have + PART).arrayBuffer()));
        const told = yield* inner.stations.requests.uploadPart(addr, { id, name: f.name, size: f.size, offset: have }, bytes, null);
        if (told.file !== undefined) saved = told.file;
        else if (told.have === have) return yield* Effect.fail(new CoreError("upload", t("core-misc.composer.upload_failed")));
        else have = told.have;
        change({ sent: told.file !== undefined ? f.size : have });
      }
      // An image's size travels with it, so every page can hold its place before it loads.
      if (f.blob.type.startsWith("image/") && typeof createImageBitmap === "function") {
        const size = yield* Effect.promise(() => createImageBitmap(f.blob).then((b) => { const s = { width: b.width, height: b.height }; b.close(); return s; }, () => null));
        if (size) saved = { ...saved, ...size };
      }
      return saved;
    });
    inner.runner.fork(
      run.pipe(
        Effect.match({
          onSuccess: (done) => change({ done }),
          onFailure: (e) => change({ error: e.message || t("core-misc.composer.upload_failed") }),
        }),
      ),
    );
    void key;
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
    return {
      text: taken.text.trim(),
      attachments: taken.files.flatMap((f) => (f.done ? [f.done] : [])),
      quotes: taken.quotes.map(({ author, text, comment, ts, role, file }) => ({ author, text, comment: comment.trim(), ...(ts ? { ts } : {}), ...(role ? { role } : {}), ...(file ? { file } : {}) })),
      files: taken.files.map((f) => f.id),
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
    const s = this.#state(from);
    // Counted on from where `to` was: what was shown of it before is older than this.
    const was = this.#state(to);
    const next = { ...empty(), text: s.text, rev: was.rev + 1, quotes: s.quotes, files: s.files, version: was.version };
    this.#all.set(to, next);
    this.#all.set(from, { ...empty(), rev: s.rev + 1, version: s.version });
    this.#changed(from, this.#all.get(from)!);
    return this.#changed(to, next);
  }

  /// A new chat moved to another station: what is written goes with it; files stay with the station they went up to.
  move(from: string, to: string): number {
    const a = this.#state(from);
    const b = this.#state(to);
    b.quotes = [...b.quotes, ...a.quotes];
    if (a.text) this.#say(b, a.text);
    b.error = null;
    a.quotes = [];
    this.#say(a, "");
    this.#changed(from, a);
    return this.#changed(to, b);
  }
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
        if (!isObject(f) || typeof (f as J).id !== "string" || !((f as J).blob instanceof Blob)) throw CoreError.invalid(t("core-misc.params.missing", { field: "files" }));
        const x = f as J;
        return { id: x.id, name: typeof x.name === "string" ? x.name : x.blob.name ?? "", size: typeof x.size === "number" ? x.size : x.blob.size, blob: x.blob, ...(isObject(x.pasted) ? { pasted: x.pasted } : {}) } as FileIn;
      });
      return { kind: "composer", key, act: { add: list, station: str(p, "station") } };
    }
    case "remove":
      return { kind: "composer", key, act: { remove: str(p, "id") } };
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
  | { remove: string } | { take: true } | { restore: true; error: string | null; unlessWritten: boolean } | { carry: string } | { move: string };

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
      if ("take" in a) return all.take(c.key);
      if ("restore" in a) return { version: all.restore(c.key, a.error, a.unlessWritten) };
      if ("carry" in a) return { version: all.carry(c.key, a.carry) };
      if ("move" in a) return { version: all.move(c.key, a.move) };
      return null;
    });
  };
}
