// A chat's own find (⌘F, in place of the browser's: its list makes only the rows that show, so the browser would find
// only in those). The core looks in all the chat's messages (`chat.find`: those not in the window shown too, and with
// `bring` those not on the device), answering which messages have the words and how many times; the list goes to the
// one the reader is at (the window moved about it first where it is outside: `chat.around`), and the words are marked
// in the rows drawn, by CSS custom highlights (nothing is laid out anew). While the bar is open the list does not
// follow its end (virtual/model.ts `reads`).
import { useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { createPortal } from "react-dom";
import { useChatSend, type ChatFound, type ChatMessage } from "./api.ts";
import { ChevronDown, ChevronUp, Close } from "./icons.tsx";
import { t } from "./i18n.ts";
import { useShortcut } from "./keymap.ts";
import { placeStrokes, strokeLayer } from "./strokes.ts";
import { Tip } from "./ui.tsx";
import type { VirtualList } from "./virtual/list.tsx";
import * as css from "./ChatFind.css.ts";
import * as conversationCss from "./styles/conversation.css.ts";
import * as chatCss from "./styles/chat.css.ts";

/** The one the reader is at: the `k`th time the words are in message `seq`. */
interface At { seq: number; k: number }

/** How far below what covers the pane's top what was found is put at least (some of what is before it shows). */
const LEAD = 72;
/** How long after the last key the chat is looked in. */
const TYPING_MS = 120;

type Highlights = Map<string, unknown>;
const highlights = (): Highlights | null => ("highlights" in CSS ? (CSS as unknown as { highlights: Highlights }).highlights : null);

/** Where `words` (lower case) are in a message's words as its row draws them, in the order they are read. */
function rangesIn(row: Element, words: string[]): Range[] {
  const ranges: Range[] = [];
  for (const part of row.querySelectorAll(`.${conversationCss.markdown}, .${chatCss.msgPlain}`)) {
    const walker = document.createTreeWalker(part, NodeFilter.SHOW_TEXT);
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      const node = n as Text;
      const lower = node.data.toLowerCase();
      if (lower.length !== node.data.length) continue;
      for (const w of words) {
        for (let i = lower.indexOf(w); i >= 0; i = lower.indexOf(w, i + w.length)) {
          const range = document.createRange();
          range.setStart(node, i);
          range.setEnd(node, i + w.length);
          ranges.push(range);
        }
      }
    }
  }
  return ranges.sort((a, b) => a.compareBoundaryPoints(Range.START_TO_START, b));
}

const rowOf = (pane: Element, seq: number) => pane.querySelector<HTMLElement>(`[data-vk="m:${seq}"]`);

/**
 * The find of the chat on `thread`, whose list is `list` (drawn by `virtual` from `messages`): `show` opens its bar
 * (`bar`: it draws itself in the page's bar, else over the list). `foot` and `head`: how much of the pane's bottom and
 * top something covers (the composer; a bar floating over the list): what is found is put clear of both. Null: what
 * the list's padding leaves for them there (the phone's list runs under its bar and its composer).
 */
export function useChatFind(list: RefObject<HTMLElement | null>, virtual: VirtualList, thread: number | null, messages: ChatMessage[], foot: number | null, head: number | null = 0): { open: boolean; show(): void; bar: ReactNode } {
  const api = useChatSend();
  const [open, setOpen] = useState(false);
  const [query, setQuery] = useState("");
  const [found, setFound] = useState<ChatFound | null>(null);
  const [at, setAt] = useState<At | null>(null);
  const [bringing, setBringing] = useState(false);
  const [asked, setAsked] = useState(0);
  const input = useRef<HTMLInputElement>(null);
  const latest = useRef(virtual);
  latest.current = virtual;

  // Where the bar goes: the page's bar, in place of its buttons, so it covers nothing of the chat; over the list where
  // the page has no such place.
  const [slot, setSlot] = useState<Element | null>(null);
  const show = useCallback(() => {
    let place: Element | null = null;
    for (let n = list.current?.parentElement ?? null; n && !place; n = n.parentElement) place = n.querySelector("[data-find-slot]");
    setSlot(place);
    // What is selected in the page is what is looked for, as the browser's find has it.
    const selected = getSelection()?.toString().trim() ?? "";
    if (selected !== "" && selected.length <= 80 && !selected.includes("\n")) setQuery(selected);
    setOpen(true);
    setAsked((n) => n + 1);
  }, [list]);
  // Closed, what was looked for is forgotten: opened again, the bar is empty and the list stays where it is.
  const close = useCallback(() => { setOpen(false); setQuery(""); setFound(null); setAt(null); }, []);
  // Another chat: its own find.
  useEffect(() => close(), [thread, close]);

  useEffect(() => {
    if (!open) return;
    input.current?.focus();
    input.current?.select();
  }, [open, asked]);

  // The list stays where the reader is while they look.
  useEffect(() => {
    if (!open) return;
    latest.current.reads(true);
    return () => latest.current.reads(false);
  }, [open]);

  // Looked for as it is typed: at once in what the device holds, then with what it does not.
  useEffect(() => {
    if (!open || thread === null) return;
    const q = query.trim();
    if (q === "") { setFound(null); setAt(null); setBringing(false); return; }
    let stale = false;
    /** Where the reader starts: what is found in the messages drawn, else the nearest before them, else the first. */
    const start = (hits: ChatFound["hits"]): At | null => {
      const { model } = latest.current;
      const showing = model.showing();
      const shown: number[] = [];
      for (let i = showing?.first ?? 0; showing && i <= showing.last; i++) { const key = model.keyAt(i); if (key?.startsWith("m:")) shown.push(Number(key.slice(2))); }
      const [from, to] = [Math.min(...shown), Math.max(...shown)];
      const hit = hits.find((h) => h.seq >= from && h.seq <= to) ?? hits.findLast((h) => h.seq < from) ?? hits[0];
      return hit ? { seq: hit.seq, k: 0 } : null;
    };
    const timer = setTimeout(() => {
      void (async () => {
        try {
          const held = await api.find(thread, q);
          if (stale) return;
          setFound(held);
          setAt(start(held.hits));
          if (held.whole) return;
          setBringing(true);
          const all = await api.find(thread, q, true);
          if (stale) return;
          setFound(all);
          setAt((was) => (was && all.hits.some((h) => h.seq === was.seq) ? was : start(all.hits)));
        } catch {
          // Its station away, or the core's an older one: what was found stays as it is.
        } finally {
          if (!stale) setBringing(false);
        }
      })();
    }, TYPING_MS);
    return () => { stale = true; clearTimeout(timer); };
  }, [open, query, thread, api]);

  const words = found?.words;
  const hits = found?.hits;
  const shown = open && !!words?.length;

  // To the one the reader is at: its message into the chat's window if it is outside, its row made, and the words
  // brought into view where they are not.
  const here = at !== null && messages.some((m) => m.seq === at.seq);
  const around = useRef<number | null>(null);
  // Its row not made (the window just moved about it, or it is far off): the list goes to it before the page is drawn,
  // so no frame shows where the list was.
  useLayoutEffect(() => {
    if (!shown || !at || !here) return;
    const pane = list.current;
    if (pane && !rowOf(pane, at.seq)) latest.current.goto(`m:${at.seq}`, "start", (head ?? 0) + LEAD);
  }, [shown, at, here, list, head]);
  useEffect(() => {
    if (!shown || !at || thread === null) return;
    if (!here) {
      if (around.current !== at.seq) { around.current = at.seq; void api.around(thread, at.seq).catch(() => undefined); }
      return;
    }
    around.current = null;
    const key = `m:${at.seq}`;
    let tries = 0;
    let frame = requestAnimationFrame(function look() {
      const pane = list.current;
      if (!pane) return;
      const row = rowOf(pane, at.seq);
      if (!row) {
        // Asked again: the browser, its content just replaced, may have scrolled the pane meanwhile, which the list
        // takes for the reader's doing.
        if (tries % 4 === 0) latest.current.goto(key, "start", (head ?? 0) + LEAD);
        if (tries++ < 30) frame = requestAnimationFrame(look);
        return;
      }
      const ranges = rangesIn(row, words!);
      const box = pane.getBoundingClientRect();
      const padding = foot === null || head === null ? getComputedStyle(pane) : null;
      const foot_ = foot ?? (parseFloat(padding!.paddingBottom) || 0);
      const head_ = head ?? (parseFloat(padding!.paddingTop) || 0);
      const top = row.getBoundingClientRect().top;
      const hit = ranges[Math.min(at.k, ranges.length - 1)]?.getBoundingClientRect();
      const [from, to] = hit ? [hit.top, hit.bottom] : [top, top + 24];
      // Clear of what covers the pane's ends; where it is not, about two fifths down what is left of the pane.
      if (from < box.top + head_ + 24 || to > box.bottom - foot_ - 24) latest.current.goto(key, "at", Math.max(head_ + LEAD, head_ + (box.height - head_ - foot_) * 0.4) - (from - top));
    });
    return () => cancelAnimationFrame(frame);
  }, [shown, at, here, thread]); // eslint-disable-line react-hooks/exhaustive-deps

  // The words marked in the rows drawn, the one the reader is at apart: again as rows are made and let go. Their
  // strokes are placed once the page is drawn (where the words are is read then, for the rows made only), and again as
  // a row resizes.
  const drawn = virtual.layout.rows.map((r) => r.key).join(" ");
  const stroked = useRef<At | null>(null);
  const layers = useRef(new Map<HTMLElement, HTMLElement>());
  useEffect(() => {
    if (!shown) return;
    const kept = layers.current;
    return () => { for (const layer of kept.values()) layer.remove(); kept.clear(); stroked.current = null; };
  }, [shown]);
  useEffect(() => {
    const marks = highlights();
    const pane = list.current;
    if (!shown || !marks || !pane) return;
    const Highlight = (window as unknown as { Highlight: new (...r: Range[]) => { priority: number } }).Highlight;
    const all: Range[] = [];
    let current: Range | undefined;
    const rows: { row: HTMLElement; ranges: Range[] }[] = [];
    for (const row of pane.querySelectorAll<HTMLElement>('[data-vk^="m:"]')) {
      const ranges = rangesIn(row, words!);
      if (!ranges.length) continue;
      if (at && row.dataset.vk === `m:${at.seq}`) current = ranges[Math.min(at.k, ranges.length - 1)];
      for (const r of ranges) if (r !== current) all.push(r);
      rows.push({ row, ranges });
    }
    marks.set("find-hit", new Highlight(...all));
    const one = new Highlight(...(current ? [current] : []));
    one.priority = 1;
    marks.set("find-current", one);
    // The one the reader came to just now is drawn in; drawn again (a row made, one resized), it is there.
    // The strokes there stay until these are placed (a row made as the reader scrolls does not blink the others').
    const kept = layers.current;
    const place = (only?: Set<Element>) => {
      for (const { row, ranges } of rows) {
        if (only && !only.has(row)) continue;
        let layer = kept.get(row);
        if (!layer?.isConnected) { layer = strokeLayer(row); layer.dataset.find = ""; kept.set(row, layer); }
        placeStrokes(layer, row, ranges, (svg, range) => {
          if (range !== current) return;
          svg.dataset.current = "";
          if (!only && stroked.current !== at) svg.dataset.fresh = "";
        });
      }
      if (only) return;
      stroked.current = at;
      for (const [row, layer] of kept) if (!rows.some((r) => r.row === row)) { layer.remove(); kept.delete(row); }
    };
    const frame = requestAnimationFrame(() => place());
    let first = true;
    const observer = new ResizeObserver((entries) => {
      if (first) { first = false; return; }
      place(new Set(entries.map((e) => e.target)));
    });
    for (const { row } of rows) observer.observe(row);
    return () => {
      cancelAnimationFrame(frame);
      observer.disconnect();
      marks.delete("find-hit");
      marks.delete("find-current");
    };
  }, [shown, words, at, drawn, messages, list]);

  /** The next one (`by` 1) or the one before (-1), round from an end to the other. */
  const step = (by: 1 | -1) => {
    if (!hits?.length) return;
    const i = at ? hits.findIndex((h) => h.seq === at.seq) : -1;
    if (i < 0 || !at) { setAt({ seq: hits[by > 0 ? 0 : hits.length - 1]!.seq, k: 0 }); return; }
    // As many times as its row has them, where it is drawn (its text's marks, a link's address, are not words in it).
    const times = (h: { seq: number; count: number }) => {
      const row = list.current ? rowOf(list.current, h.seq) : null;
      const n = row ? rangesIn(row, words!).length : 0;
      return n > 0 ? Math.min(n, h.count) : h.count;
    };
    const k = at.k + by;
    if (k >= 0 && k < times(hits[i]!)) { setAt({ seq: at.seq, k }); return; }
    const next = hits[(i + by + hits.length) % hits.length]!;
    setAt({ seq: next.seq, k: by > 0 ? 0 : Math.max(0, times(next) - 1) });
  };

  useShortcut("panel.close", open ? close : null);

  const total = hits?.reduce((n, h) => n + h.count, 0) ?? 0;
  const i = at && hits ? hits.findIndex((h) => h.seq === at.seq) : -1;
  const position = i < 0 || !hits ? 0 : hits.slice(0, i).reduce((n, h) => n + h.count, 0) + Math.min(at!.k, hits[i]!.count - 1) + 1;
  const made = !open ? null : (
    <div className={css.bar} role="search" data-chat-find="" data-over={slot ? undefined : ""}>
      {found && !found.whole && (
        <p className={css.note} role="status">{t(bringing ? "web-main.find.bringing" : "web-main.find.partial", { held: found.held, of: found.of })}</p>
      )}
      <div className={css.field}>
        <input ref={input} className={css.input} type="text" value={query} placeholder={t("web-main.find.placeholder")} aria-label={t("web-main.find.placeholder")}
          spellCheck={false} autoComplete="off"
          onChange={(e) => setQuery(e.target.value)}
          onKeyDown={(e) => {
            if (e.nativeEvent.isComposing) return;
            if (e.key === "Enter") { e.preventDefault(); step(e.shiftKey ? -1 : 1); }
            else if (e.key === "Escape") { e.preventDefault(); e.stopPropagation(); close(); }
          }} />
        {/* Nothing found yet while the rest is read is not "nothing found". */}
        {found && !(bringing && total === 0) && <span className={css.count} role="status">{total > 0 ? `${position}/${total}` : t("web-main.find.none")}</span>}
        <Tip label={t("web-main.find.prev")} side="bottom">
          <button type="button" className={css.button} aria-label={t("web-main.find.prev")} disabled={total === 0} onClick={() => step(-1)}><ChevronUp size={16} /></button>
        </Tip>
        <Tip label={t("web-main.find.next")} side="bottom">
          <button type="button" className={css.button} aria-label={t("web-main.find.next")} disabled={total === 0} onClick={() => step(1)}><ChevronDown size={16} /></button>
        </Tip>
        <Tip label={t("web-main.find.close")} side="bottom">
          <button type="button" className={css.button} aria-label={t("web-main.find.close")} onClick={close}><Close size={16} /></button>
        </Tip>
      </div>
    </div>
  );
  const bar = made && slot ? createPortal(made, slot) : made;
  return { open, show, bar };
}
