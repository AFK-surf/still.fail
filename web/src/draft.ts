import { type PastedInfo } from "./pastedText.ts";
// What is being written to a chat, the same on a wide screen (Chat.tsx's Composer) and a phone (mobile/ChatHost.tsx):
// its text, the passages it quotes, and files on their way to the station. The core keeps it, by the draft's `key`
// (client/core-ts/src/composer.ts, the `composer` topic): each chat has its own while another shows, kept on the device
// as the chat's draft; the core sends its files up and says how far. This only shows it and says what is done to it:
// what is typed is the page's at once (and told to the core as it is typed), the rest as the page has done it until
// the core has it too. A reference's mark goes as written: the core makes it a link as it is sent.
import { createContext, useEffect, useLayoutEffect, useRef, useState, type MutableRefObject } from "react";
import { CoreError, useChatSend, type Attachment, type ChatTo, type Quote } from "./api.ts";
import { core, useTopicSelect } from "./core/react.ts";
import type { ComposerFile, ComposerLink, ComposerRef, ComposerView } from "./core/shapes.ts";
import { track } from "./telemetry.ts";
import { useStation } from "./station.tsx";
import { keepSentImage, uploadImageKey } from "./sentImages.ts";
import { useToast } from "@stillfail/ui/toast.tsx";
import { setPrefs, usePrefs } from "./prefs.ts";
import { t } from "./i18n.ts";

export const MAX_FILE = 1024 * 1024 * 1024;

/** A file on its way to the station: uploading (`sent`: how much of it the station has), uploaded, or failed.
 * `preview`: an image's local picture, until it leaves the draft. */
export interface Pending { id: string; name: string; size: number; sent?: number; width?: number; height?: number; done: Attachment | null; error: string | null; preview?: string; image?: Blob; pasted?: PastedInfo; pastedFile?: File; ref?: ComposerRef; link?: ComposerLink }

/** A file or folder dragged in from where it is: which station has it and where (`ref`), and how to send it should it be
 * switched to a file: where it is in that station's drive, or the file itself (one from Finder). */
export interface Dropped { name: string; size: number; ref: Omit<ComposerRef, "mode">; drive?: { station: string; root: string; path: string }; blob?: File }

/** Where a file named by its path is, as the message says it (the core's words for it, composer.ts `pathWords`). */
export const pathWords = (ref: ComposerRef) => t(ref.dir ? "common.folderOn" : "common.pathOn", { station: ref.stationName, path: ref.path });
/** What a link of the draft goes as (the core's words for it, composer.ts `linkWords`): its title on a line, then where it goes. */
export const linkWords = (link: ComposerLink) => (link.title ? `${link.title}\n${link.url}` : link.url);
/** Whether a file of the draft goes as words (named by its path, or a link shared in), not as a file. */
const named = (f: { ref?: ComposerRef | undefined; link?: ComposerLink | undefined }) => f.ref?.mode === "path" || f.link !== undefined;

/** A passage quoted in the message being written, with what is said about it. */
export interface DraftQuote extends Quote { id: string }

export interface Draft {
  text: string; setText(text: string): void;
  files: Pending[];
  /** Files picked, pasted or dropped: each goes to the station at once (and waits there in no chat, until a message takes it). */
  add(files: FileList | File[], pasted?: PastedInfo): void;
  /** Files and folders dragged in from where they are: named by their path until switched to files (`setMode`). */
  addDropped(items: Dropped[]): void;
  /** A file dragged in, named by its path or sent as a file. */
  setMode(id: string, mode: "path" | "file"): void;
  /** Whether this chat takes files dragged in as files (folders are named by their path all the same), and setting it. */
  asFiles: boolean; setAsFiles(on: boolean): void;
  remove(id: string): void;
  /** A file that failed to go up, sent up again. */
  retry(id: string): void;
  quotes: DraftQuote[];
  /** Quotes added (a preview's marks), as they are. */
  addQuotes(quotes: DraftQuote[]): void;
  /** What is said about a quote. */
  comment(id: string, comment: string): void;
  unquote(id: string): void;
  /** Quotes a passage; its comment line then asks for the focus (`focusQuote`, until `quoteFocused`). */
  quote(q: Omit<Quote, "comment">): void;
  focusQuote: string | null; quoteFocused(): void;
  /** A file still going up; sending queues the message until it is there. */
  uploading: boolean;
  /** Something to send, and nothing holding it: text, a file that is up, or a quote. */
  ready: boolean;
  /** A new chat being made for the message. */
  starting: boolean;
  error: string | null; setError(error: string | null): void;
  /** Takes what is written away and hands it back (the text trimmed), for a page that sends it its own way. */
  take(): { text: string; files: Pending[]; quotes: DraftQuote[] };
  /** Puts back what `take` took (sending it failed). */
  restore(): void;
  /**
   * Sends what is written into the chat `open` answers (the chat's thread; making it first for a new one, `first`).
   * Answers the thread, or null when there was no chat to send into (the draft is back, and says why).
   */
  send(open: () => Promise<ChatTo>, options?: { first?: boolean; onSending?: (text: string | null) => void }): Promise<ChatTo | null>;
}

/**
 * What another part of the page puts into a chat's draft: a preview's marks (its screenshot and a quote each), or the
 * words an inline visualization asks to send (Viz.tsx), there for the person to send or not.
 */
export interface Offer {
  files: File[]; quotes: DraftQuote[]; text?: string;
  /** Files and folders of a station's, named by their path (a chat's 文件 tab). */
  dropped?: Dropped[];
  /** A passage selected in the chat, quoted with its comment line taking the focus. */
  quote?: Omit<Quote, "comment">;
}

/** The key of the draft of the chat a part of the page sits in, for what offers to it from within a message. */
export const DraftKey = createContext<string | undefined>(undefined);

/** The composer showing each chat's draft, by its key: what takes an offer for it. */
const inboxes = new Map<string, (offer: Offer) => void>();

/** Puts files and quotes into the draft of the chat `key`, when its composer is there: says whether it was. */
export function offerToDraft(key: string, offer: Offer): boolean {
  const take = inboxes.get(key);
  take?.(offer);
  return take !== undefined;
}

/** Takes what is offered to the draft `key` while it shows. */
export function useDraftInbox(key: string | undefined, take: (offer: Offer) => void): void {
  const latest = useRef(take);
  latest.current = take;
  useEffect(() => {
    if (key === undefined) return;
    const inbox = (offer: Offer) => latest.current(offer);
    inboxes.set(key, inbox);
    return () => { if (inboxes.get(key) === inbox) inboxes.delete(key); };
  }, [key]);
}

/** A new chat's draft before it has a key of its own (the phone's, before its station is known). */
export const NO_KEY = "new:";

/** What the page has of each file besides what the core says: its picture, the file itself (sent again, shown whole). */
const local = new Map<string, Pick<Pending, "preview" | "image" | "pastedFile">>();

/** The station each file picked or pasted here went up to, and the file itself: one that went to another station than
 * the message goes to (its path there means nothing to this one) goes up again before it is sent. */
const wentTo = new Map<string, { station: string; file: File }>();
// Also remember the origin of restored attachments whose local File is no longer available.
const fileStations = new Map<string, string>();

let nextId = 1;

/** What the composer shows of the core's (`ComposerView`), as the page has it now. */
interface Shown { quotes: DraftQuote[]; files: ComposerFile[]; focus: string | null; starting: boolean; error: string | null }
const NOTHING: Shown = { quotes: [], files: [], focus: null, starting: false, error: null };

const sameButWords = (a: ComposerView | undefined, b: ComposerView | undefined) => a === b || (!!a && !!b && a.rev === b.rev
  && a.version === b.version && a.quotes === b.quotes && a.files === b.files && a.focus === b.focus && a.starting === b.starting
  && a.error === b.error && a.uploading === b.uploading && a.ready === b.ready);

function shownOf(view: ComposerView): Shown {
  return { quotes: view.quotes as DraftQuote[], files: view.files, focus: view.focus ?? null, starting: view.starting, error: view.error ?? null };
}

export function useDraft({ key: given, station, carry }: {
  /** Whose draft it is. With none (a new chat, before it is made), what is written goes on into the first key it gets. */
  key: string | undefined;
  /** The address of the station its files go up to, when the draft lives outside that station's context (the phone's host). */
  station?: string | undefined;
  /** A key whose draft goes on from what is written now, instead of its own (a new chat becoming its chat). */
  carry?: MutableRefObject<string | null>;
}): Draft {
  const key = given ?? NO_KEY;
  const chat = useChatSend(station);
  const contextStation = useStation().address;
  const toast = useToast();
  // What is written: the page's at once, the core's when it says something of its own (`rev`).
  const [text, setTextState] = useState("");
  const [shown, setShown] = useState<Shown>(NOTHING);
  // The core's answers to what the page did: until the last of them is in, what the page did is what shows.
  const pending = useRef(0);
  const acked = useRef(0);
  const seenRev = useRef(-1);
  // Not drawn again for the words the page typed (they come back in `text` with every key): only for what the core
  // changed (its own words, with a new `rev`; quotes, files, whether it can be sent).
  const view = useTopicSelect<ComposerView, ComposerView | undefined>({ topic: "composer", key }, (s) => s.value, sameButWords);
  const now = useRef({ key, text, shown, view });
  now.current = { key, text, shown, view };

  // Another chat (or the first key, or the chat a new one made): what is written goes where it belongs, in the core.
  const was = useRef(key);
  useLayoutEffect(() => {
    const before = was.current;
    if (before === key) return;
    was.current = key;
    // Each key counts its own versions: what was answered for the one before says nothing of this one's (counted on from
    // it, this one's were all older until it had been written to as much, and the one before's files stayed shown).
    seenRev.current = -1;
    acked.current = 0;
    if (carry && carry.current === key) {
      carry.current = null;
      void act("carry", { key: before, to: key });
      return;
    }
    if (before === NO_KEY) {
      // The first key: what was written before it goes on into it; with nothing written, its own draft comes back.
      const { text: written, shown: s } = now.current;
      if (written || s.files.length || s.quotes.length) { void act("carry", { key: before, to: key }); return; }
    } else if (before.startsWith("new:") && key.startsWith("new:")) {
      // The selector changes where this message will run, not which message is being written. Carry its files too;
      // adopting the destination's files made the pasted picture disappear or turn into an older draft's picture.
      const moving = now.current.shown.files;
      for (const f of moving) if (!named(f) && !fileStations.has(f.id)) fileStations.set(f.id, before.slice(4));
      void act("carry", { key: before, to: key });
      // Start fresh uploads from the local bytes, with fresh ids: a late answer from the old station cannot replace
      // the new attachment. These calls are queued behind carry, before the core's destination draft is adopted.
      for (const f of moving) {
        const source = wentTo.get(f.id);
        if (named(f) || !source || source.station === (station ?? contextStation)) continue;
        remove(f.id);
        add([source.file], f.pasted as PastedInfo | undefined);
      }
      return;
    }
    // Shown as the core has it (at once when it has it already), else empty until it says.
    adopt(now.current.view, true);
  }, [key]); // eslint-disable-line react-hooks/exhaustive-deps

  /** The core's value shown, unless the page has done something it has not answered yet. */
  const adopted = useRef<ComposerView | undefined>(undefined);
  const adopt = (v: ComposerView | undefined, force = false) => {
    if (!v) { if (force) { adopted.current = undefined; setShown(NOTHING); setTextState(""); } return; }
    if (!force && (pending.current > 0 || v.version < acked.current || v === adopted.current)) return;
    adopted.current = v;
    // Only what changed draws again: the topic changes with every word typed, and the rest of it stays as it was.
    setShown((s) => {
      const next = shownOf(v);
      return next.quotes === s.quotes && next.files === s.files && next.focus === s.focus && next.starting === s.starting && next.error === s.error ? s : next;
    });
    if (v.rev !== seenRev.current) {
      seenRev.current = v.rev;
      setTextState(v.text);
    }
  };
  useLayoutEffect(() => adopt(view), [view]); // eslint-disable-line react-hooks/exhaustive-deps

  /** Has the core do `what` to this draft; `show` is what the page shows of it meanwhile. */
  const act = (what: string, params: Record<string, unknown>, show?: (s: Shown) => Shown) => {
    if (show) setShown((s) => show(s));
    pending.current++;
    const at = now.current.key;
    return core().call(`composer.${what}`, { key: at, ...params }).then(
      (answer) => {
        const version = (answer as { version?: number } | null)?.version;
        // An answer for the key before (another chat shows by now) counts nothing here.
        if (typeof version === "number" && now.current.key === at) acked.current = Math.max(acked.current, version);
        return answer;
      },
      () => undefined,
    ).finally(() => {
      pending.current--;
      adopt(now.current.view);
    });
  };

  const setText = (next: string) => {
    setTextState(next);
    void act("text", { text: next });
  };
  const setError = (error: string | null) => { void act("error", { error }, (s) => ({ ...s, error })); };
  const add = (picked: FileList | File[], pasted?: PastedInfo) => {
    const files = Array.from(picked).map((file) => {
      const id = `f${Date.now()}-${nextId++}`;
      // Images show at once from the local file; the picture lives until the file leaves the draft.
      const preview = file.type.startsWith("image/") || pasted !== undefined ? URL.createObjectURL(file) : undefined;
      local.set(id, { ...(preview ? { preview, ...(pasted === undefined ? { image: file } : {}) } : {}), ...(pasted === undefined ? {} : { pastedFile: file }) });
      return { id, name: file.name, size: file.size, blob: file, ...(pasted ? { pasted } : {}) };
    });
    const ids = new Set(files.map((f) => f.id));
    for (const f of files) {
      wentTo.set(f.id, { station: station ?? contextStation, file: f.blob });
      fileStations.set(f.id, station ?? contextStation);
    }
    void act("add", { station: station ?? contextStation, files }, (s) => ({
      ...s,
      files: [...s.files, ...files.map((f): ComposerFile => ({ id: f.id, name: f.name, size: f.size, ...(f.size > MAX_FILE ? { error: t("web-main.draft.tooBig") } : {}), ...(pasted ? { pasted } : {}) }))],
    })).then((answer) => {
      // Not taken (no core keeps it, as on the site's demo): they could not go up.
      if (answer === undefined) setShown((x) => ({ ...x, files: x.files.map((f) => (ids.has(f.id) && !f.done && !f.error ? { ...f, error: t("web-main.draft.uploadFailed") } : f)) }));
    });
  };
  // Files dragged in go as files where this chat says so (prefs' `dropFiles`), else as the settings say (`dropAs`);
  // folders are named by their path all the same.
  const byDefault = usePrefs((p) => p.dropAs === "file");
  const asFiles = usePrefs((p) => p.dropFiles[key]) ?? byDefault;
  const addDropped = (items: Dropped[]) => {
    const files = items.map((f) => ({ id: `f${Date.now()}-${nextId++}`, name: f.name, size: f.size, ref: { ...f.ref, mode: asFiles && !f.ref.dir ? "file" as const : "path" as const }, ...(f.drive ? { drive: f.drive } : {}), ...(f.blob ? { blob: f.blob } : {}) }));
    void act("add", { station: station ?? contextStation, files }, (s) => ({
      ...s,
      files: [...s.files, ...files.map((f): ComposerFile => ({ id: f.id, name: f.name, size: f.size, ref: f.ref }))],
    }));
  };
  const setMode = (id: string, mode: "path" | "file") => {
    void act("mode", { id, mode }, (s) => ({ ...s, files: s.files.map((f) => (f.id === id && f.ref && !(mode === "file" && f.ref.dir) ? { ...f, ref: { ...f.ref, mode } } : f)) }));
  };
  const remove = (id: string) => {
    const l = local.get(id);
    if (l?.preview) URL.revokeObjectURL(l.preview);
    local.delete(id);
    wentTo.delete(id);
    fileStations.delete(id);
    void act("remove", { id }, (s) => ({ ...s, files: s.files.filter((f) => f.id !== id) }));
  };
  const retry = (id: string) => {
    void act("retry", { id }, (s) => ({
      ...s,
      files: s.files.map((f) => {
        if (f.id !== id) return f;
        const { error: _, sent: __, ...going } = f;
        return going;
      }),
    }));
  };
  const addQuotes = (quotes: DraftQuote[]) => {
    for (const q of quotes) void act("quote", { id: q.id, quote: q }, (s) => ({ ...s, quotes: [...s.quotes, q] }));
  };
  const quote = (q: Omit<Quote, "comment">) => {
    const id = `${Date.now()}`;
    void act("quote", { id, quote: { ...q, comment: "" }, focus: true }, (s) => ({ ...s, quotes: [...s.quotes, { ...q, comment: "", id }], focus: id }));
  };
  const comment = (id: string, words: string) => {
    void act("comment", { id, comment: words }, (s) => ({ ...s, quotes: s.quotes.map((x) => (x.id === id ? { ...x, comment: words } : x)) }));
  };
  const unquote = (id: string) => {
    void act("unquote", { id }, (s) => ({ ...s, quotes: s.quotes.filter((x) => x.id !== id), focus: s.focus === id ? null : s.focus }));
  };
  const quoteFocused = () => { void act("focused", {}, (s) => ({ ...s, focus: null })); };

  const files: Pending[] = shown.files.map((f) => ({ ...f, done: (f.done ?? null) as Attachment | null, error: f.error ?? null, ...(f.sent != null ? { sent: f.sent } : {}), ...(f.pasted ? { pasted: f.pasted as PastedInfo } : {}), ...local.get(f.id) }));
  const quotes = shown.quotes;
  const uploading = files.some((f) => !f.done && !f.error && !named(f));
  const ready = (Boolean(text.trim()) || files.some((f) => !f.error) || quotes.length > 0) && !shown.starting && !files.some((f) => f.pasted && f.error);

  const back = useRef<{ text: string; shown: Shown } | null>(null);
  const take = () => {
    back.current = { text, shown };
    const taken = { text: text.trim(), files, quotes };
    setTextState("");
    void act("take", {}, () => ({ ...NOTHING }));
    return taken;
  };
  const restore = (error: string | null = null, unlessWritten = false) => {
    const kept = back.current;
    if (unlessWritten && (now.current.text.trim() || now.current.shown.files.length || now.current.shown.quotes.length)) return;
    if (kept) setTextState(kept.text);
    void act("restore", { error, unlessWritten }, () => (kept ? { ...kept.shown, error } : { ...NOTHING, error }));
  };
  const send: Draft["send"] = async (open, { first = false, onSending } = {}) => {
    const from = key;
    // A file that went up to another station than this one (picked before the chat's station was changed): not sent
    // from there, which this one would refuse; it goes up here again and the message waits to be sent once more.
    const here = station ?? contextStation;
    const unavailable = files.filter((f) => !named(f) && fileStations.has(f.id) && fileStations.get(f.id) !== here && !wentTo.has(f.id));
    if (unavailable.length) {
      setError(t("web-main.draft.selectAgain", { names: unavailable.map((f) => f.name).join(", ") }));
      return null;
    }
    const astray = files.filter((f) => !named(f) && !f.error && wentTo.has(f.id) && wentTo.get(f.id)!.station !== here);
    if (astray.length) {
      for (const f of astray) {
        const { file } = wentTo.get(f.id)!;
        remove(f.id);
        add([file], f.pasted);
      }
      setError(t("web-main.draft.otherStation", { names: astray.map((f) => f.name).join(", ") }));
      return null;
    }
    // Its images' pictures stay here until the station's are read: one still going up by its upload's id, as its outbox
    // row and then its message draw it.
    for (const f of files) {
      if (!f.image || f.error) continue;
      if (f.done) keepSentImage(station ?? contextStation, f.done.path, f.image);
      else keepSentImage(station ?? contextStation, uploadImageKey(f.id), f.image, 10 * 60_000);
    }
    const { text: written, files: all, quotes: sentQuotes } = take();
    // Links and those named by their path go as words after what is written (each link, then where each file is), as
    // the core takes them; the rest as files.
    const value = [written, ...all.flatMap((f) => (f.link ? [linkWords(f.link)] : [])), ...all.filter((f) => f.ref?.mode === "path").map((f) => pathWords(f.ref!))]
      .filter((w) => w !== "").join("\n");
    const sentFiles = all.filter((f) => !named(f));
    const attachments = sentFiles.flatMap((f) => (f.done ? [f.done] : []));
    const sent = sentQuotes.map(({ author, text: q, comment: c, ts, role, file }) => ({ author, text: q, comment: c.trim(), ...(ts ? { ts } : {}), ...(role ? { role } : {}), ...(file ? { file } : {}) }));
    if (first) onSending?.(value);
    let to: ChatTo;
    try {
      void act("starting", { starting: first }, (s) => ({ ...s, starting: first }));
      to = await open();
    } catch (failure) {
      // No chat to send into (a new one could not be made): the draft comes back.
      restore(failure instanceof Error ? failure.message : String(failure));
      onSending?.(null);
      return null;
    } finally {
      void act("starting", { starting: false }, (s) => ({ ...s, starting: false }));
    }
    // Its files' pictures go once it is sent (or kept in the outbox); back in the composer, they come with it.
    const drop = () => {
      for (const f of sentFiles) {
        const l = local.get(f.id);
        if (l?.preview) URL.revokeObjectURL(l.preview);
        local.delete(f.id);
        wentTo.delete(f.id);
        fileStations.delete(f.id);
      }
    };
    const at = performance.now();
    const counts = { attachments: attachments.length, quotes: sent.length, first };
    chat.send(to, value, attachments, sent, sentFiles.filter((f) => !f.done && !f.error).map(({ id, name, size, width, height }) => ({ id, name, size, ...(width && height ? { width, height } : {}) }))).then(
      () => { drop(); track("message_sent", { ...counts, ok: true, ms: Math.round(performance.now() - at) }); },
      (failure: unknown) => {
        track("message_sent", { ...counts, ok: false });
        // One the station did not take waits in the outbox, which says so; one that never got there comes back to the
        // composer (unless something new is written there), and says why.
        const why = t("web-main.draft.notSent", { error: failure instanceof Error ? failure.message : String(failure) });
        if (refused(failure) && (now.current.key === from || from === NO_KEY)) {
          restore(why, true);
          return;
        }
        drop();
        if (refused(failure)) toast(why);
      },
    );
    return to;
  };

  return {
    text, setText, files, add, addDropped, setMode, asFiles, setAsFiles: (on: boolean) => setPrefs({ dropFiles: { [key]: on === byDefault ? null : on } }), remove, retry, quotes, addQuotes, comment, unquote, quote, focusQuote: shown.focus, quoteFocused,
    uploading, ready, starting: shown.starting, error: shown.error, setError, take, restore: () => restore(), send,
  };
}

/**
 * A send that never got into the outbox: the core refused it, or went away with it (its worker restarted or closed).
 * One the station failed stays in the outbox, which says so and offers to send it again.
 */
function refused(failure: unknown): boolean {
  return failure instanceof CoreError && ["invalid_params", "core_restarted", "closed"].includes(failure.code);
}
