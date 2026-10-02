// Where something was set going (doing.ts): a spinner while it is under way, then, when it failed, a small red mark that
// says why on hover for the few seconds the core keeps it, in the same place, so a row or button whose menu has closed
// still says so after the toast has gone. Nothing otherwise.
import type { ReactNode } from "react";
import { doingMatches, failed, useDoingList } from "./doing.ts";
import { Tip } from "./ui.tsx";
import * as css from "./DoingMark.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";
import { t } from "./i18n.ts";

type Words = Record<string, string | number | boolean | null | undefined>;

/** Where one of `calls` about what `on` names is: under way, or failed a moment ago and why. */
export interface DoingState { running: boolean; error?: string | undefined; note?: string | undefined }

/** One of `calls` about what `on` names: under way, or why it failed a moment ago (shown a few seconds). */
export function useDoingState(calls: string | readonly string[], on: Words = {}): DoingState {
  const list = useDoingList().filter((item) => doingMatches(item, calls, on));
  const failing = list.findLast(failed);
  // A write its station went quiet on is asked again once it is back: the spinner says so.
  const note = list.find((item) => item.stage === "rechecking")?.note;
  return { running: list.some((item) => !failed(item)), error: failing ? (failing.error ?? t("web-main.doing.failed")) : undefined, note };
}

interface MarkProps {
  /** On the spinner (its size, where it sits). */
  className?: string;
  /** The failure mark's size (px). */
  size?: number;
  /** What is in its place otherwise (an icon a button shows), undefined for nothing. */
  idle?: ReactNode;
  /** What the spinner says to a screen reader; none hides it (the button around it already says). */
  label?: string;
  /** Where the failure's tip opens. */
  side?: "top" | "bottom" | "left" | "right";
  /** Inside something with a tip of its own (an icon button): no tip of the mark's, that one says why instead. */
  bare?: boolean;
}

/** The spinner, or the failure mark, for a state the caller already has (several calls, or one its menu reads). */
export function DoingShown({ state, className, size = 12, idle = null, label, side, bare }: MarkProps & { state: DoingState }) {
  if (state.running) {
    const cls = className ? `${waitingCss.spinner} ${className}` : waitingCss.spinner;
    const spinner = label || state.note ? <span className={cls} role="status" aria-label={state.note ?? label} /> : <span className={cls} aria-hidden="true" />;
    return state.note && !bare ? <Tip label={state.note} {...(side ? { side } : {})}>{spinner}</Tip> : spinner;
  }
  if (state.error !== undefined) {
    const mark = <span className={css.failedMark} style={{ width: size, height: size, fontSize: size - 4 }} role="img" aria-label={t("web-main.doing.failedWhy", { error: state.error })}>!</span>;
    return bare ? mark : <Tip label={state.error} {...(side ? { side } : {})}>{mark}</Tip>;
  }
  return <>{idle}</>;
}

/** `<DoingMark calls="job.stop" on={{ station, id }} />`: the spinner while under way, the failure mark a moment after. */
export function DoingMark({ calls, on, ...rest }: MarkProps & { calls: string | readonly string[]; on?: Words }) {
  return <DoingShown state={useDoingState(calls, on)} {...rest} />;
}
