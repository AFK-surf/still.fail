// What is being written to a chat, the same on a wide screen (Chat.tsx's Composer) and a phone (mobile/ChatHost.tsx):
// its text, the passages it quotes, and files on their way to the station. Each chat has its own (a `key`): moving to
// another chat, or leaving the page, puts it away, and coming back brings it back. Sending empties it at once (the
// message waits in the chat's outbox until the station has it); if the chat it goes to cannot be made, it comes back.
import { useEffect, useLayoutEffect, useRef, useState, type MutableRefObject } from "react";
import { useChatSend, type Attachment, type ChatTo, type Quote } from "./api.ts";
import { track } from "./telemetry.ts";

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

/** Drafts put away, by chat. */
const kept = new Map<string, { text: string; files: Pending[]; quotes: DraftQuote[] }>();

let nextId = 1;

export function useDraft({ key, carry, upload, quotes: held }: {
  /** Whose draft it is. With none (a new chat, before it is made), what is written goes on into the first key it gets. */
  key: string | undefined;
  /** A key whose draft goes on from what is written now, instead of its own (a new chat becoming its chat). */
  carry?: MutableRefObject<string | null>;
  /** Sends a file to the station. */
  upload(file: File): Promise<Attachment>;
  /** The quotes, where the page holds them (it offers them from its messages): otherwise the draft does. */
  quotes?: [DraftQuote[], Update<DraftQuote[]>];
}): Draft {
  const chat = useChatSend();
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
  useLayoutEffect(() => {
    const before = shown.current;
    if (before === key) return;
    shown.current = key;
    if (carry && key !== undefined && carry.current === key) { carry.current = null; return; }
    if (before === undefined) return;
    // A new chat moved to another station: what is written goes with it; files stay with the station they went up to.
    if (before.startsWith("new:") && key?.startsWith("new:")) {
      const { files } = now.current;
      if (files.length) kept.set(before, { text: "", files, quotes: [] });
      else kept.delete(before);
      const theirs = kept.get(key)?.files ?? [];
      kept.delete(key);
      setFiles(theirs); setError(null);
      return;
    }
    put(before);
    const next = key === undefined ? undefined : kept.get(key);
    if (key !== undefined) kept.delete(key);
    setText(next?.text ?? ""); setFiles(next?.files ?? []); if (!held) setOwnQuotes(next?.quotes ?? []); setError(null);
  }, [key]); // eslint-disable-line react-hooks/exhaustive-deps
  // Made for a chat: its draft comes back; leaving the page puts it away.
  useLayoutEffect(() => {
    const at = shown.current;
    const next = at === undefined ? undefined : kept.get(at);
    if (at !== undefined && next) {
      kept.delete(at);
      setText(next.text); setFiles(next.files); if (!held) setOwnQuotes(next.quotes);
    }
    return () => put(shown.current);
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

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
    const taken = { text: text.trim(), files, quotes };
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
    const sent = quotes.map(({ author, text: t, comment, ts, role }) => ({ author, text: t, comment: comment.trim(), ...(ts ? { ts } : {}), ...(role ? { role } : {}) }));
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
