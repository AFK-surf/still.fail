// What is being written to a chat, the same on a wide screen (Chat.tsx's Composer) and a phone (mobile/ChatHost.tsx):
// its text, the passages it quotes, and files on their way to the station. Each chat has its own (a `key`): moving to
// another chat, or leaving the page, puts it away, and coming back brings it back. Sending empties it at once (the
// message waits in the chat's outbox until the station has it); if the chat it goes to cannot be made, it comes back.
// The core keeps each on the device (its `draft` topic, `draft.put`), so it outlives the page; what is on its way up
// stays with the page.
import { createContext, useEffect, useLayoutEffect, useRef, useState, type MutableRefObject } from "react";
import { useChatSend, type Attachment, type ChatTo, type Quote } from "./api.ts";
import { core } from "./core/react.ts";
import type { DraftView } from "./core/shapes.ts";
import { track } from "./telemetry.ts";
import { expandRefs } from "./chatRefs.ts";

export const MAX_FILE = 50 * 1024 * 1024;

/** A file on its way to the station: uploading, uploaded, or failed. `preview`: an image's local picture, until it leaves the draft. */
export interface Pending { id: number; name: string; size: number; done: Attachment | null; error: string | null; preview?: string }

/** A passage quoted in the message being written, with what is said about it. */
export interface DraftQuote extends Quote { id: string }

type Update<T> = (update: (all: T) => T) => void;

export interface Draft {
  text: string; setText(text: string): void;
  files: Pending[];
  /** Files picked, pasted or dropped: each goes to the station at once (and waits there in no chat, until a message takes it). */
  add(files: FileList | File[]): void;
  remove(id: number): void;
  quotes: DraftQuote[]; setQuotes: Update<DraftQuote[]>;
  /** Quotes a passage; its comment line then asks for the focus (`focusQuote`, until `quoteFocused`). */
  quote(q: Omit<Quote, "comment">): void;
  focusQuote: string | null; quoteFocused(): void;
  /** A file still going up: nothing can be sent until it is there. */
  uploading: boolean;
  /** Something to send, and nothing holding it: text, a file that is up, or a quote. */
  ready: boolean;
  /** A new chat being made for the message. */
  starting: boolean;
  error: string | null; setError(error: string | null): void;
  /** Takes what is written away and hands it back (the text trimmed), for a page that sends it its own way. */
  take(): { text: string; files: Pending[]; quotes: DraftQuote[] };
  /** Puts back what `take` took (sending it failed). */
  restore(kept: { text: string; files: Pending[]; quotes: DraftQuote[] }): void;
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
export interface Offer { files: File[]; quotes: DraftQuote[]; text?: string }

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

/** Drafts put away, by chat. */
const kept = new Map<string, { text: string; files: Pending[]; quotes: DraftQuote[] }>();

let nextId = 1;

/** The chat a draft's key names, as the core keeps it: `new:<station>` a new chat there, else `<station>:<chat>`. */
function keptAt(key: string): { station: string; chat: string } | null {
  if (key.startsWith("new:")) return { station: key.slice(4), chat: "new" };
  const at = key.indexOf(":");
  return at > 0 ? { station: key.slice(0, at), chat: key.slice(at + 1) } : null;
}

/** Writes waiting, by key: the latest of each goes to the core a moment after the last change. */
const writes = new Map<string, { draft: DraftView; timer: ReturnType<typeof setTimeout> }>();

/** Has the core keep `key`'s draft as it is now (`now`: at once rather than a moment later). */
function persist(key: string, draft: { text: string; files: Pending[]; quotes: DraftQuote[] } | undefined, now = false): void {
  const at = keptAt(key);
  if (!at) return;
  const view: DraftView = {
    text: draft?.text ?? "",
    quotes: (draft?.quotes ?? []).map(({ id: _, ...q }) => q),
    files: (draft?.files ?? []).flatMap((f) => (f.done ? [f.done] : [])),
  };
  const before = writes.get(key);
  if (before) clearTimeout(before.timer);
  const write = () => {
    writes.delete(key);
    // A core from before drafts refuses it: the draft is then the page's only, as it was.
    core().call("draft.put", { ...at, ...view }).catch(() => undefined);
  };
  if (now) write();
  else writes.set(key, { draft: view, timer: setTimeout(write, 300) });
}

/** Leaving the page: what waits goes now. */
if (typeof window !== "undefined") {
  window.addEventListener("pagehide", () => {
    for (const [key, { draft, timer }] of writes) {
      clearTimeout(timer);
      writes.delete(key);
      const at = keptAt(key);
      if (at) core().call("draft.put", { ...at, ...draft }).catch(() => undefined);
    }
  });
}

/** `key`'s draft as the core keeps it (null: none, or a core that keeps none). */
function readKept(key: string): Promise<DraftView | null> {
  const at = keptAt(key);
  if (!at) return Promise.resolve(null);
  return new Promise((resolve) => {
    let stop: (() => void) | null = null;
    let done = false;
    const finish = (value: DraftView | null) => {
      if (done) return;
      done = true;
      resolve(value);
      // Unsubscribed on the next turn: the answer may come while subscribing.
      queueMicrotask(() => stop?.());
    };
    stop = core().subscribe({ topic: "draft", ...at }, (value) => finish(value as DraftView), () => finish(null));
    if (done) stop();
  });
}

export function useDraft({ key, station, carry, upload, quotes: held }: {
  /** Whose draft it is. With none (a new chat, before it is made), what is written goes on into the first key it gets. */
  key: string | undefined;
  /** The address of the station its chat is on, when the draft lives outside that station's context (the phone's host). */
  station?: string | undefined;
  /** A key whose draft goes on from what is written now, instead of its own (a new chat becoming its chat). */
  carry?: MutableRefObject<string | null>;
  /** Sends a file to the station. */
  upload(file: File): Promise<Attachment>;
  /** The quotes, where the page holds them (it offers them from its messages): otherwise the draft does. */
  quotes?: [DraftQuote[], Update<DraftQuote[]>];
}): Draft {
  const chat = useChatSend(station);
  const [text, setText] = useState("");
  const [files, setFiles] = useState<Pending[]>([]);
  const [ownQuotes, setOwnQuotes] = useState<DraftQuote[]>([]);
  const [quotes, setQuotes] = held ?? [ownQuotes, setOwnQuotes];
  const [focusQuote, setFocusQuote] = useState<string | null>(null);
  const [starting, setStarting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const sender = useRef(upload);
  sender.current = upload;

  // Another chat: what is written is put away for the one before, and the next one's comes back.
  const now = useRef({ text, files, quotes: held ? [] : quotes });
  now.current = { text, files, quotes: held ? [] : quotes };
  const put = (at: string | undefined) => {
    const { text, files, quotes } = now.current;
    if (at !== undefined && (text || files.length || quotes.length)) kept.set(at, { text, files, quotes });
  };
  const shown = useRef(key);
  /** The key whose kept draft has been read (or that nothing was kept for): only then is what is written kept for it. */
  const loaded = useRef<string | undefined>(undefined);
  /** Has the core keep what `at` has now, if what it kept was read (else it stays as it was). */
  const leave = (at: string) => {
    if (loaded.current === at) persist(at, kept.get(at), true);
  };
  /** Brings back what the core kept for `at`, unless something has been written here meanwhile. */
  const fromCore = (at: string) => {
    loaded.current = undefined;
    void readKept(at).then((view) => {
      if (shown.current !== at) return;
      const { text, files, quotes } = now.current;
      if (view && !text && !files.length && !quotes.length) {
        if (view.text) setText(view.text);
        if (view.files.length) setFiles(view.files.map((done) => ({ id: nextId++, name: done.name, size: done.size, done, error: null })));
        if (view.quotes.length && !held) setOwnQuotes(view.quotes.map((q, i) => ({ ...q, id: `${Date.now()}-${i}` })));
      }
      loaded.current = at;
      // Written meanwhile: that is what is kept now.
      if (text || files.length || quotes.length) persist(at, now.current);
    });
  };
  useLayoutEffect(() => {
    const before = shown.current;
    if (before === key) return;
    shown.current = key;
    if (carry && key !== undefined && carry.current === key) {
      carry.current = null;
      // What it has now is the chat's; the new chat's is empty.
      if (before !== undefined && loaded.current === before) persist(before, undefined, true);
      loaded.current = key;
      return;
    }
    // The first key: what was written before it goes on into it; with nothing written, its own draft comes back (the
    // page knew its chat only once its station was known).
    if (before === undefined) {
      const next = key === undefined ? undefined : kept.get(key);
      const { text, files, quotes } = now.current;
      if (next && !text && !files.length && !quotes.length) {
        kept.delete(key!);
        setText(next.text); setFiles(next.files); if (!held) setOwnQuotes(next.quotes);
      }
      if (key !== undefined) {
        if (next || text || files.length || quotes.length) loaded.current = key;
        else fromCore(key);
      }
      return;
    }
    // A new chat moved to another station: what is written goes with it; files stay with the station they went up to.
    if (before.startsWith("new:") && key?.startsWith("new:")) {
      const { files } = now.current;
      if (files.length) kept.set(before, { text: "", files, quotes: [] });
      else kept.delete(before);
      const theirs = kept.get(key)?.files ?? [];
      kept.delete(key);
      setFiles(theirs); setError(null);
      leave(before);
      loaded.current = key;
      return;
    }
    put(before);
    leave(before);
    const next = key === undefined ? undefined : kept.get(key);
    if (key !== undefined) kept.delete(key);
    setText(next?.text ?? ""); setFiles(next?.files ?? []); if (!held) setOwnQuotes(next?.quotes ?? []); setError(null);
    if (key !== undefined) {
      if (next) loaded.current = key;
      else fromCore(key);
    }
  }, [key]); // eslint-disable-line react-hooks/exhaustive-deps
  // Made for a chat: its draft comes back; leaving the page puts it away.
  useLayoutEffect(() => {
    const at = shown.current;
    const next = at === undefined ? undefined : kept.get(at);
    if (at !== undefined && next) {
      kept.delete(at);
      setText(next.text); setFiles(next.files); if (!held) setOwnQuotes(next.quotes);
      loaded.current = at;
    } else if (at !== undefined) fromCore(at);
    return () => {
      put(shown.current);
      if (shown.current !== undefined) leave(shown.current);
    };
  }, []); // eslint-disable-line react-hooks/exhaustive-deps
  // What is written goes to the core as it changes, once what it kept has been read (not to write over it before).
  useEffect(() => {
    const at = shown.current;
    if (at === undefined || loaded.current !== at) return;
    persist(at, { text, files, quotes: held ? [] : quotes });
  }, [text, files, quotes]); // eslint-disable-line react-hooks/exhaustive-deps

  const add = (picked: FileList | File[]) => {
    for (const file of Array.from(picked)) {
      const id = nextId++;
      const tooBig = file.size > MAX_FILE;
      // Images show at once from the local file; the picture lives until the file leaves the draft.
      const preview = file.type.startsWith("image/") ? URL.createObjectURL(file) : undefined;
      setFiles((all) => [...all, { id, name: file.name, size: file.size, done: null, error: tooBig ? "超过 50 MB" : null, ...(preview ? { preview } : {}) }]);
      if (tooBig) continue;
      sender.current(file).then(
        (done) => setFiles((all) => all.map((f) => (f.id === id ? { ...f, done } : f))),
        (error: unknown) => setFiles((all) => all.map((f) => (f.id === id ? { ...f, error: error instanceof Error ? error.message : "上传失败" } : f))),
      );
    }
  };
  const remove = (id: number) => setFiles((all) => all.filter((f) => {
    if (f.id === id && f.preview) URL.revokeObjectURL(f.preview);
    return f.id !== id;
  }));
  const quote = (q: Omit<Quote, "comment">) => {
    const id = `${Date.now()}`;
    setQuotes((all) => [...all, { ...q, comment: "", id }]);
    setFocusQuote(id);
  };

  const uploading = files.some((f) => !f.done && !f.error);
  const ready = (Boolean(text.trim()) || files.some((f) => f.done) || quotes.length > 0) && !uploading && !starting;
  const take = () => {
    const taken = { text: expandRefs(text.trim()), files, quotes };
    setText(""); setFiles([]); setQuotes(() => []); setError(null);
    return taken;
  };
  const restore = (back: { text: string; files: Pending[]; quotes: DraftQuote[] }) => {
    setText(back.text); setFiles(back.files); setQuotes(() => back.quotes);
  };
  const send: Draft["send"] = async (open, { first = false, onSending } = {}) => {
    const back = { text, files, quotes };
    const { text: value } = take();
    const attachments = files.flatMap((f) => (f.done ? [f.done] : []));
    const sent = quotes.map(({ author, text: t, comment, ts, role, file }) => ({ author, text: t, comment: comment.trim(), ...(ts ? { ts } : {}), ...(role ? { role } : {}), ...(file ? { file } : {}) }));
    if (first) onSending?.(value);
    let to: ChatTo;
    try {
      setStarting(first);
      to = await open();
    } catch (failure) {
      // No chat to send into (a new one could not be made): the draft comes back.
      restore(back);
      onSending?.(null);
      setError(failure instanceof Error ? failure.message : String(failure));
      return null;
    } finally {
      setStarting(false);
    }
    for (const f of files) if (f.preview) URL.revokeObjectURL(f.preview);
    const at = performance.now();
    const counts = { attachments: attachments.length, quotes: sent.length, first };
    void chat.send(to, value, attachments, sent).then(
      () => track("message_sent", { ...counts, ok: true, ms: Math.round(performance.now() - at) }),
      () => track("message_sent", { ...counts, ok: false }),
    );
    return to;
  };
  // Pictures of files no longer in any draft go with them.
  useEffect(() => () => {
    for (const f of now.current.files) if (f.preview && !isKept(f)) URL.revokeObjectURL(f.preview);
  }, []);

  return {
    text, setText, files, add, remove, quotes, setQuotes, quote, focusQuote, quoteFocused: () => setFocusQuote(null),
    uploading, ready, starting, error, setError, take, restore, send,
  };
}

function isKept(file: Pending): boolean {
  for (const d of kept.values()) if (d.files.includes(file)) return true;
  return false;
}
