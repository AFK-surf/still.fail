// Waiting, drawn one way everywhere (docs/ui-panels.md「等待」; Android ui/Waiting.kt the same). Three kinds:
// - a page or list read for the first time: `Waiting`, what will come drawn as it will be, by its own parts, of made-up
//   words, in its bones (`Bones`: its words bars, its pictures and icons shapes, its outline its own), breathing, no
//   words (the page's frame, its bar, title and composer, drawn as ever around it); what could not be read said over
//   them in red;
// - a row or button at work: `Spinner` in its place (DoingMark where it is a core call), in one of two sizes;
// - what has a size on its way (a file, an update): `Progress`.
// Words (a pill, a line) come only after a moment (LATER_MS), so what is there at once shows none; what failed says so
// at once, in red.
import { forwardRef, useContext, useLayoutEffect, useRef, useState, type HTMLAttributes, type ReactNode } from "react";
import { bonesOf, type Bone } from "./bones.ts";
import { InBones } from "./inBones.ts";
import { Words } from "./words.tsx";
import { t } from "./i18n.ts";
import * as css from "./waiting.css.ts";
import * as spinnerCss from "./styles/spinner.css.ts";

/**
 * The turning ring: `inline` (12) in a line of small text, else a button's icon's size (14). `label`: what it says to a
 * screen reader; none hides it (what is around it already says). It takes a tip's trigger props (Tip around it).
 */
export const Spinner = forwardRef<HTMLSpanElement, { inline?: boolean; className?: string | undefined; label?: string | undefined } & Omit<HTMLAttributes<HTMLSpanElement>, "className">>(
  function Spinner({ inline = false, className, label, ...rest }, ref) {
    const cls = `${spinnerCss.spinner}${inline ? ` ${spinnerCss.inline}` : ""}${className ? ` ${className}` : ""}`;
    return label ? <span ref={ref} {...rest} className={cls} role="status" aria-label={label} /> : <span ref={ref} {...rest} className={cls} aria-hidden="true" />;
  },
);

/** Words the app wrote, drawn as it says (./words.tsx). */
function Said({ text }: { text: string }) {
  const W = useContext(Words);
  // One run of words in its line (a pill or a line lays its parts out with gaps between them).
  return <span><W text={text} /></span>;
}

/**
 * What is waited on (a spinner before it), or with `error` what is wrong (in red, at once): a grey capsule. `over`: over
 * a picture (a player buffering, a screen connecting), frosted, in the middle of what holds it (positioned).
 */
export function WaitPill({ text, error = false, over = false, className, why }: { text: string; error?: boolean; over?: boolean; className?: string; /** Why, on hover (a failure's message). */ why?: string | null | undefined }) {
  const cls = `${css.pill}${over ? ` ${css.pillOver}` : ""}${className ? ` ${className}` : ""}`;
  return (
    <span className={cls} data-error={error || undefined} role="status" aria-live="polite" title={why ?? undefined}>
      {!error && <Spinner inline />}<Said text={text} />
    </span>
  );
}

/** A wait said in a line of its own words where a row or a section's content will be (a spinner before it). */
export function WaitLine({ text = t("common.reading"), error = false, className }: { text?: string; error?: boolean; className?: string }) {
  return (
    <div className={className ? `${css.line} ${className}` : css.line} data-error={error || undefined} role="status" aria-live="polite">
      {!error && <Spinner inline />}<Said text={text} />
    </div>
  );
}

/**
 * A line over what is there already, while more of it is on its way (the chats' `syncing`): it takes no room until it
 * has gone on a while (LATER_MS), so what is there in a moment does not move what is under it.
 */
export function LaterLine({ text, className }: { text: string; className?: string }) {
  const [shown, setShown] = useState(false);
  useLayoutEffect(() => {
    const at = setTimeout(() => setShown(true), css.LATER_MS);
    return () => clearTimeout(at);
  }, []);
  if (!shown) return null;
  return (
    <div className={className ? `${css.line} ${css.lineNow} ${className}` : `${css.line} ${css.lineNow}`} role="status" aria-live="polite">
      <Spinner inline /><Said text={text} />
    </div>
  );
}

/** What a page or list waits on, from the core's note (ListNote) or the page's own words. */
export interface WaitNote {
  /** Still reading: the placeholders breathe. */
  reading?: boolean | undefined;
  /** What it waits on (正在读取会话, 正在连接 Studio). */
  text?: string | null | undefined;
  /** What could not be read, each said in red (`message` why, on hover). */
  failing?: readonly { text: string; message?: string | null | undefined }[] | undefined;
}

export { InBones };

/** Made-up words `n` letters long, for what a page's bones are drawn of: only how long they are is seen, as a bar. */
export const sampleWords = (n: number): string => "字".repeat(n);

/**
 * What will come, in its bones (./bones.ts: its words bars, its pictures and icons shapes, on its own grounds, in the
 * line's grey), breathing; still and whole (`still`) as what they wait on failed. `children`: what it will show, drawn
 * by the parts that draw it when it comes, of made-up data (`sampleWords`), so that its outline is theirs. `fill`: it
 * takes the room left (a page's body).
 */
export function Bones({ children, still = false, fill = false }: { children: ReactNode; still?: boolean; fill?: boolean }) {
  const within = useContext(InBones);
  const box = useRef<HTMLDivElement | null>(null);
  const body = useRef<HTMLDivElement | null>(null);
  const [bones, setBones] = useState<readonly Bone[]>([]);
  useLayoutEffect(() => {
    const b = box.current, o = body.current;
    if (within || !b || !o) return;
    // measured again as what it holds is laid out anew: its width, its words changed, the fonts come
    let frame = 0;
    const measure = () => { cancelAnimationFrame(frame); frame = requestAnimationFrame(() => setBones(bonesOf(b, o))); };
    setBones(bonesOf(b, o));
    const sizes = new ResizeObserver(measure);
    sizes.observe(b);
    const changes = new MutationObserver(measure);
    changes.observe(o, { subtree: true, childList: true, characterData: true });
    void document.fonts?.ready.then(measure);
    return () => { cancelAnimationFrame(frame); sizes.disconnect(); changes.disconnect(); };
  }, [within]);
  // (in bones already, as they are: one breath)
  if (within) return <>{children}</>;
  return (
    <InBones.Provider value>
      <div ref={box} className={fill ? `${css.bones} ${css.bonesFill}` : css.bones} data-still={still || undefined} aria-hidden="true" inert>
        <div ref={body} className={css.boneBody}>{children}</div>
        <div className={css.boneMarks} data-placeholder="">
          {bones.map((b, i) => <span key={i} className={css.bone} style={{ left: b.x, top: b.y, width: b.w, height: b.h, borderRadius: b.r }} />)}
        </div>
      </div>
    </InBones.Provider>
  );
}

/**
 * A page's or list's content while it is read the first time: what will come in its bones (`sample`: what it will
 * show, made of made-up words by the parts that draw it, its rows, its cards, its messages), breathing; what it waits
 * on (`note`, else `text`, else 正在读取) said only to a screen reader; over it in red what could not be read (`error`,
 * `note.failing`), the bones then still. `fill`: it takes the room left (a page's body); otherwise it is as tall as
 * its bones. What `children` holds goes between the pills and the bones.
 */
export function Waiting({ sample, text, error, note, fill = false, children }: {
  sample: ReactNode; text?: string | undefined; error?: string | null | undefined;
  note?: WaitNote | null | undefined; fill?: boolean; children?: ReactNode;
}) {
  const failing: { text: string; message?: string | null | undefined }[] = [...(error ? [{ text: error }] : []), ...(note?.failing ?? [])];
  const reading = !error && (note ? note.reading !== false : true);
  const said = note?.text ?? text ?? t("common.reading");
  return (
    <div className={fill ? `${css.wait} ${css.fill}` : css.wait} {...(reading ? { role: "status", "aria-label": said } : {})}>
      {failing.length > 0 && <div className={css.pills}>
        {failing.map((f, i) => <WaitPill key={i} text={f.text} why={f.message} error />)}
      </div>}
      {children}
      <Bones still={!reading} fill={fill}>{sample}</Bones>
    </div>
  );
}

/**
 * A list with rows already, still waiting on some of it (a station not read yet, one that could not be): under its
 * rows one more of them in its bones (`sample`) for what is still read, and each failure in red. Nothing once it
 * waits on nothing.
 */
export function WaitMore({ note, sample, className }: { note: WaitNote | null | undefined; sample: ReactNode; className?: string }) {
  if (!note) return null;
  return <>
    {note.reading !== false && <div role="status" aria-label={note.text ?? t("common.reading")}><Bones>{sample}</Bones></div>}
    {note.failing?.map((f, i) => <WaitLine key={i} text={f.text} error {...(className ? { className } : {})} />)}
  </>;
}

/** How much has come of what has a size (0…1), or a bar that sweeps while that is not known (`part` null). */
export function Progress({ part, label, className }: { part: number | null; label?: string; className?: string }) {
  return (
    <span className={className ? `${css.track} ${className}` : css.track} role="progressbar" aria-label={label} aria-valuemin={0} aria-valuemax={100}
      aria-valuenow={part === null ? undefined : Math.round(part * 100)}>
      <span className={css.progress} style={part === null ? undefined : { width: `${Math.min(1, Math.max(0, part)) * 100}%` }} data-unknown={part === null || undefined} />
    </span>
  );
}

/** A determinate ring in the icon family's 24-unit grid; its parent supplies the accessible label. */
export function ProgressRing({ part, size = 20 }: { part: number; size?: number }) {
  const share = Math.min(1, Math.max(0, part));
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.75" strokeLinecap="round" aria-hidden="true">
      <circle cx="12" cy="12" r="8.5" opacity="0.18" />
      {share > 0 && <circle cx="12" cy="12" r="8.5" pathLength="100" strokeDasharray={`${share * 100} 100`} transform="rotate(-90 12 12)" />}
    </svg>
  );
}
