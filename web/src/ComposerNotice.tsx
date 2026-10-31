import type { ReactNode } from "react";
import { Check } from "@stillfail/ui/icons.tsx";
import * as css from "./ComposerNotice.css.ts";

/**
 * A notice over a chat's composer (the cache over, archived, its station down): a capsule of its own over it, as wide and
 * round as the composer and on its glass; its mark where the composer's ＋ is, its words where the composer's are, quiet,
 * what it offers at its end, why that failed under its words. The app's is the same (mbui sfpages composer_notice).
 */
export function ComposerNotice({ mark, children, offer, error }: { mark: ReactNode; children: ReactNode; offer?: ReactNode; error?: string | undefined }) {
  return <div className={css.notice} role="status">
    <span className={css.mark} aria-hidden="true">{mark}</span>
    <span className={css.words}>{children}{error && <span className={css.failed} role="alert">{error}</span>}</span>
    {offer}
  </div>;
}

/** What a notice offers, at its end: its words' colour, a step heavier; quiet while it cannot be done. */
export function NoticeOffer({ onClick, disabled, children }: { onClick: () => void; disabled: boolean; children: ReactNode }) {
  return <button type="button" className={css.offer} onClick={onClick} disabled={disabled}>{children}</button>;
}

/** A choice a notice offers, at its end: the option taken marked ✓ in its words' colour, the others quiet, pressed to
 * take them (not while `held`). The app's is the same (mbui sfpages composer_notice `choices`). */
export function NoticeChoice({ options, held }: { options: { label: string; taken: boolean; take: () => void }[]; held: boolean }) {
  return <span className={css.choices} role="radiogroup">
    {options.map((o) => <button key={o.label} type="button" role="radio" aria-checked={o.taken} className={o.taken ? css.taken : css.choice}
      onClick={() => { if (!o.taken && !held) o.take(); }} disabled={held && !o.taken}>
      {o.taken && <Check size={12} />}{o.label}
    </button>)}
  </span>;
}

/** The notices over the composer, one over another, 8 apart. */
export function ComposerNotices({ className, children }: { className?: string; children: ReactNode }) {
  return <div className={`${css.notices}${className ? ` ${className}` : ""}`}>{children}</div>;
}
