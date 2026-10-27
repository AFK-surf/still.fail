import type { ReactNode } from "react";
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

/** The notices over the composer, one over another, 8 apart. */
export function ComposerNotices({ className, children }: { className?: string; children: ReactNode }) {
  return <div className={`${css.notices}${className ? ` ${className}` : ""}`}>{children}</div>;
}
