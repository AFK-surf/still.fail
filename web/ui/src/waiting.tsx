// Waiting, drawn one way everywhere (docs/ui-panels.md「等待」; Android ui/Waiting.kt the same). Three kinds:
// - a page or list read for the first time: `Waiting`, placeholders shaped as what will come and a pill over them
//   saying what is waited on (the page's frame, its bar, title and composer, drawn as ever around it);
// - a row or button at work: `Spinner` in its place (DoingMark where it is a core call), in one of two sizes;
// - what has a size on its way (a file, an update): `Progress`.
// Words come only after a moment (LATER_MS), so what is there at once shows none; what failed says so at once, in red.
import { forwardRef, type HTMLAttributes, type ReactNode } from "react";
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

/**
 * What is waited on (a spinner before it), or with `error` what is wrong (in red, at once): a grey capsule. `over`: over
 * a picture (a player buffering, a screen connecting), frosted, in the middle of what holds it (positioned).
 */
export function WaitPill({ text, error = false, over = false, className, why }: { text: string; error?: boolean; over?: boolean; className?: string; /** Why, on hover (a failure's message). */ why?: string | null | undefined }) {
  const cls = `${css.pill}${over ? ` ${css.pillOver}` : ""}${className ? ` ${className}` : ""}`;
  return (
    <span className={cls} data-error={error || undefined} role="status" aria-live="polite" title={why ?? undefined}>
      {!error && <Spinner inline />}{text}
    </span>
  );
}

/** A wait said in a line of its own words where a row or a section's content will be (a spinner before it). */
export function WaitLine({ text = t("common.reading"), error = false, className }: { text?: string; error?: boolean; className?: string }) {
  return (
    <div className={className ? `${css.line} ${className}` : css.line} data-error={error || undefined} role="status" aria-live="polite">
      {!error && <Spinner inline />}{text}
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

export type WaitShape = "rows" | "messages" | "cards";

const TITLES = [150, 110, 170, 130, 96, 160, 120];
const LINES = [230, 190, 250, 170, 210, 200, 180];
const MESSAGES: [boolean, number, number][] = [[false, 220, 40], [false, 160, 58], [true, 180, 40], [false, 240, 76], [true, 120, 40], [false, 200, 40]];
const CARDS = [120, 88, 152, 104];

/** The shapes of what will come: rows (a list's: a title and a line), messages (a chat's) or cards (a settings page's). */
export function WaitShapes({ shape = "rows", count, dense = false, still = false }: { shape?: WaitShape; count?: number; dense?: boolean; still?: boolean }) {
  if (shape === "messages") {
    return (
      <div className={`${css.shapes} ${css.messages}`} data-still={still || undefined} aria-hidden="true">
        {MESSAGES.map(([mine, w, h], i) => (
          <div key={i} className={css.message} data-mine={mine || undefined}>
            {!mine && <span className={css.face} />}
            <span className={css.bubble} style={{ width: w, height: h }} />
          </div>
        ))}
      </div>
    );
  }
  if (shape === "cards") {
    return (
      <div className={`${css.shapes} ${css.cards}`} data-still={still || undefined} aria-hidden="true">
        {Array.from({ length: count ?? 3 }, (_, i) => <span key={i} className={css.card} style={{ height: CARDS[i % CARDS.length] }} />)}
      </div>
    );
  }
  return (
    <div className={css.shapes} data-still={still || undefined} aria-hidden="true">
      {Array.from({ length: count ?? 7 }, (_, i) => (
        <div key={i} className={css.row} data-dense={dense || undefined}>
          <div className={css.rowLines}>
            <span className={css.rowTitle} style={{ width: (dense ? 0.6 : 1) * TITLES[i % TITLES.length]! }} />
            <span className={css.rowLine} style={{ width: (dense ? 0.6 : 1) * LINES[i % LINES.length]! }} />
          </div>
          {!dense && <span className={css.rowPicture} />}
        </div>
      ))}
    </div>
  );
}

/**
 * A page's or list's content while it is read the first time: its shapes, and over them a pill saying what it waits on
 * (`note`, else `text`, else 正在读取), or in red what could not be read (`error`, `note.failing`), the shapes then still.
 * `fill`: it takes the room left (a page's body); otherwise it is as tall as its shapes (a list in a column).
 */
export function Waiting({ shape = "rows", count, dense, text, error, note, fill = false, children }: {
  shape?: WaitShape; count?: number; dense?: boolean; text?: string | undefined; error?: string | null | undefined;
  note?: WaitNote | null | undefined; fill?: boolean; children?: ReactNode;
}) {
  const failing: { text: string; message?: string | null | undefined }[] = [...(error ? [{ text: error }] : []), ...(note?.failing ?? [])];
  const reading = !error && (note ? note.reading !== false : true);
  const said = note?.text ?? text ?? t("common.reading");
  return (
    <div className={fill ? `${css.wait} ${css.fill}` : css.wait}>
      <div className={css.pills}>
        {reading && <WaitPill text={said} />}
        {failing.map((f, i) => <WaitPill key={i} text={f.text} why={f.message} error />)}
      </div>
      {children}
      <WaitShapes shape={shape} {...(count !== undefined ? { count } : {})} {...(dense !== undefined ? { dense } : {})} still={!reading} />
    </div>
  );
}

/**
 * A list with rows already, still waiting on some of it (a station not read yet, one that could not be): under its
 * rows, a line saying what it waits on, and each failure in red. Nothing once it waits on nothing.
 */
export function WaitMore({ note, className }: { note: WaitNote | null | undefined; className?: string }) {
  if (!note) return null;
  return <>
    {note.reading !== false && <WaitLine text={note.text ?? t("common.reading")} {...(className ? { className } : {})} />}
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
