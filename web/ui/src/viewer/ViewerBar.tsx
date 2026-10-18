// The one bar every file opened shows across its top on a wide screen with a mouse: a picture's, a PDF's or code's
// preview (FilePreview.tsx), a text read (drive/Reader.tsx), a video played (drive/Player.tsx). Always there, laid
// along the window's top: the way back on the left (where to, by name), the file's name and a line about it in the
// middle, its tools on the right as icons, download last. Its ground is the file's (`--viewer-ground`, the paper
// under a text), its ink and line with it. On a phone each keeps its own floating bars.
import { useCallback, useRef, useState, type ReactNode, type UIEvent, type PointerEvent } from "react";
import { ChevronLeft, Download } from "../icons.tsx";
import { Tip } from "../parts.tsx";
import * as css from "./ViewerBar.css.ts";
import { t } from "../i18n.ts";
import * as pageCss from "../styles/page.css.ts";

export function ViewerBar({ back, name, meta, tools, title, hidden = false }: {
  /** Where its way back goes, by name, and going there (or closing it). */
  back: { label: string; onClick: () => void };
  name: ReactNode;
  /** The line under the name: its size, its kind, which of how many, how far read. */
  meta?: ReactNode;
  /** Its tools, as `ViewerTool`s, download last. */
  tools?: ReactNode;
  /** Where the full path shows (on hover over the name). */
  title?: string | undefined;
  /** Gone up out of the way (the file played on, or read on down): it comes back as the pointer comes to the top. */
  hidden?: boolean;
}) {
  return (
    <header className={css.bar} data-hidden={hidden || undefined} inert={hidden}>
      <button type="button" className={css.back} onClick={back.onClick} aria-label={back.label}><ChevronLeft size={20} /><span>{back.label}</span></button>
      <span className={css.center} title={title}>
        <b className={css.name}>{name}</b>
        {meta && <small className={css.meta}>{meta}</small>}
      </span>
      <span className={css.tools}>{tools}</span>
    </header>
  );
}

/** One of a bar's tools: an icon, named on hover; `on` while what it opens is open. */
export function ViewerTool({ label, on = false, onClick, children }: { label: string; on?: boolean; onClick: () => void; children: ReactNode }) {
  return (
    <Tip label={label}>
      <button type="button" className={`${pageCss.iconBtn} ${css.tool}`} aria-label={label} aria-pressed={on || undefined} data-on={on || undefined} onClick={onClick}>{children}</button>
    </Tip>
  );
}

/** Download, as every bar has it last: a link to what is here already (`href`), or a function that saves it. */
export function ViewerDownload({ href, name, onSave }: { href?: string | undefined; name: string; onSave?: (() => void) | undefined }) {
  const label = t("web-main.preview.download");
  if (onSave || !href) return <ViewerTool label={label} onClick={() => onSave?.()}><Download size={18} /></ViewerTool>;
  return <Tip label={label}><a className={`${pageCss.iconBtn} ${css.tool}`} href={href} download={name} aria-label={label}><Download size={18} /></a></Tip>;
}

/**
 * When a bar over a file read down (a text, a PDF, code) is out of the way: gone as it is read on down, back as it is
 * read back up, or as the pointer comes to the window's top. `onScroll` and `onPointerMove` are what tell it (a
 * capture on what holds the scroller does).
 */
export function useBarOnScroll(): { hidden: boolean; onScroll: (e: UIEvent) => void; onPointerMove: (e: PointerEvent) => void } {
  const [hidden, setHidden] = useState(false);
  const last = useRef(new WeakMap<EventTarget, number>());
  const onScroll = useCallback((e: UIEvent) => {
    const el = e.target as HTMLElement;
    const was = last.current.get(el) ?? 0;
    const now = el.scrollTop;
    last.current.set(el, now);
    // Near its top, always there; on down, gone; back up, back.
    if (now < TOP_KEPT) setHidden(false);
    else if (now - was > MOVED) setHidden(true);
    else if (was - now > MOVED) setHidden(false);
  }, []);
  const onPointerMove = useCallback((e: PointerEvent) => { if (e.pointerType === "mouse" && e.clientY < VIEWER_BAR_REACH) setHidden(false); }, []);
  return { hidden, onScroll, onPointerMove };
}

/**
 * Whether the pointer, last seen at `e`, is on the bar (or just coming to it): within VIEWER_BAR_REACH of the window's
 * top. A viewer whose bar fades as the pointer rests keeps it while so. In the desktop app the bar drags the window, and
 * over it the page hears nothing of the pointer (it seems to rest there, or to have left the page): where it was last
 * seen tells.
 */
export const byBar = (e: { clientY: number }) => e.clientY < VIEWER_BAR_REACH;

/** Read down this far before the bar goes; this much of a scroll at once says which way. */
const TOP_KEPT = 48;
const MOVED = 6;
/** The pointer this near the window's top brings the bar back. */
export const VIEWER_BAR_REACH = 72;
