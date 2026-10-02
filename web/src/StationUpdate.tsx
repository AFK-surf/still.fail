import type { LinkShown } from "./core/shapes.ts";
import * as css from "./StationUpdate.css.ts";

/** The core supplies the same update notice to every chat client. */
export function StationUpdate({ notice }: { notice?: LinkShown | null | undefined }) {
  if (!notice) return null;
  return <aside className={css.notice} data-tone={notice.tone} role="status">
    <span className={css.title}>{notice.text}</span>
    {notice.detail && <span>{notice.detail}</span>}
  </aside>;
}
