// The one bar every file opened shows across its top on a wide screen with a mouse: a picture's, a PDF's or code's
// preview (FilePreview.tsx), a text read (drive/Reader.tsx), a video played (drive/Player.tsx). Always there, laid
// along the window's top: the way back on the left (where to, by name), the file's name and a line about it in the
// middle, its tools on the right as icons, download last. Its ground is the file's (`--viewer-ground`, the paper
// under a text), its ink and line with it. On a phone each keeps its own floating bars.
import type { ReactNode } from "react";
import { ChevronLeft, Download } from "../icons.tsx";
import { Tip } from "../ui.tsx";
import * as pagesCss from "../styles/pages.css.ts";
import * as css from "./ViewerBar.css.ts";
import { t } from "../i18n.ts";

export function ViewerBar({ back, name, meta, tools, title }: {
  /** Where its way back goes, by name, and going there (or closing it). */
  back: { label: string; onClick: () => void };
  name: ReactNode;
  /** The line under the name: its size, its kind, which of how many, how far read. */
  meta?: ReactNode;
  /** Its tools, as `ViewerTool`s, download last. */
  tools?: ReactNode;
  /** Where the full path shows (on hover over the name). */
  title?: string | undefined;
}) {
  return (
    <header className={css.bar}>
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
      <button type="button" className={`${pagesCss.iconBtn} ${css.tool}`} aria-label={label} aria-pressed={on || undefined} data-on={on || undefined} onClick={onClick}>{children}</button>
    </Tip>
  );
}

/** Download, as every bar has it last: a link to what is here already (`href`), or a function that saves it. */
export function ViewerDownload({ href, name, onSave }: { href?: string | undefined; name: string; onSave?: (() => void) | undefined }) {
  const label = t("web-main.preview.download");
  if (onSave || !href) return <ViewerTool label={label} onClick={() => onSave?.()}><Download size={18} /></ViewerTool>;
  return <Tip label={label}><a className={`${pagesCss.iconBtn} ${css.tool}`} href={href} download={name} aria-label={label}><Download size={18} /></a></Tip>;
}
