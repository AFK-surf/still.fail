// A numbered note as a narrow screen shows it, wherever it is made: a passage of a message's (Annotate.tsx) or a mark on
// an image (../annotate/ImageMarks.tsx). Being written, in a frosted box like the chat's composer; written, as a card
// in a row at the foot. The Android app's are its Annotate.kt NoteBox and Card.
import { useEffect, useLayoutEffect, useRef, type CSSProperties } from "react";
import { Check, Trash } from "../icons.tsx";
import * as css from "./Annotate.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import { t } from "../i18n.ts";

/** A note: its number, what it is about (a line under what is said), what is said, its pin's colour (none: the accent). */
export interface NoteView { n: number; text: string; comment: string; color?: string | undefined }

/**
 * Saying something about it, its number and what it is over what is written. `className`/`style`: where it goes (by
 * default under its passage, `style.top`); `reveal`: scrolled into sight as it opens.
 */
export function NoteBox({ note, className = css.mNote, style, reveal = true, onComment, onDone, onRemove }: {
  note: NoteView; className?: string; style?: CSSProperties; reveal?: boolean; onComment(comment: string): void; onDone(): void; onRemove(): void;
}) {
  const input = useRef<HTMLTextAreaElement>(null);
  useEffect(() => {
    const el = input.current;
    if (!el) return;
    el.focus({ preventScroll: true });
    el.setSelectionRange(el.value.length, el.value.length);
    if (reveal) el.closest("div")?.parentElement?.scrollIntoView({ block: "nearest", behavior: "smooth" });
  }, [reveal]);
  useLayoutEffect(() => {
    const el = input.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${el.scrollHeight}px`;
  }, [note.comment]);
  return (
    <div className={`${className} ${pagesCss.mFloating}`} style={style} onPointerDown={(e) => e.stopPropagation()}>
      <div className={css.mNoteQuote}><span className={css.mNotePin} style={note.color ? { background: note.color } : undefined}>{note.n}</span><q>{note.text}</q></div>
      <div className={css.mNoteBar}>
        <button type="button" className={css.mNoteBtn} aria-label={t("web-mobile.notes.remove")} onClick={onRemove}><Trash size={17} /></button>
        <textarea ref={input} className={css.mNoteInput} rows={1} value={note.comment} placeholder={t("web-mobile.notes.placeholder")} aria-label={t("web-mobile.notes.label", { n: note.n })}
          onChange={(e) => onComment(e.target.value)}
          onKeyDown={(e) => {
            // Its keys are its own (not an image viewer's zoom or steps).
            e.stopPropagation();
            if (e.key === "Enter" && !e.shiftKey && !e.nativeEvent.isComposing && window.matchMedia("(hover: hover)").matches) { e.preventDefault(); onDone(); }
          }} />
        <button type="button" className={css.mNoteDone} aria-label={t("web-mobile.notes.done")} onClick={onDone}><Check size={18} /></button>
      </div>
    </div>
  );
}

/** A note written, as a card in the foot's row: its number and what is said, over what it is about. */
export function NoteCard({ note, open, onClick }: { note: NoteView; open: boolean; onClick(): void }) {
  return (
    <button type="button" className={`${css.mCard} ${pagesCss.mFloating}`} data-open={open || undefined} onClick={onClick}>
      <span className={css.mCardHead}>
        <span className={css.mCardPin} style={note.color ? { background: note.color } : undefined}>{note.n}</span>
        {/* Cut short with an ellipsis (a bare text in a flex row is only clipped). */}
        <span className={css.mCardSaid} data-empty={!note.comment.trim() || undefined}>{note.comment.trim() || t("web-mobile.notes.quoteOnly")}</span>
      </span>
      <q className={css.mCardQuote}>{note.text}</q>
    </button>
  );
}
