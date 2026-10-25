import { useLayoutEffect, useRef } from "react";
import type { ChatItem } from "./api.ts";
import type { WorkspaceMark } from "./core/shapes.ts";
import { play, restingLoop } from "@stillfail/ui/motion.ts";
import { StatusText, Tip } from "./ui.tsx";
import { jumpTo } from "./jumpTo.ts";
import * as css from "./ChatMark.css.ts";
import { t } from "./i18n.ts";
import { Bell, Check, Wait, Watch } from "@stillfail/ui/icons.tsx";

export type ChatTone = "busy" | "done" | "alert" | "wait" | "other";

const TONES: readonly string[] = ["busy", "done", "alert", "wait", "other"];

/**
 * What a chat's row says of it: the core's mark when it gives one (`tone`, with its pieces of work: a blue ring when
 * something waits on the viewer, a grey one when only on others). From a core before it: red when it wants someone now
 * (blocked, failed), yellow while at work, blue when it ended well with something unread; nothing otherwise.
 */
export function chatTone(item: ChatItem): ChatTone | undefined {
  if (item.tone !== undefined) return TONES.includes(item.tone) ? item.tone as ChatTone : undefined;
  if (item.state === "block" || item.state === "failed") return "alert";
  if (item.state === "run") return "busy";
  return item.unread ? "done" : undefined;
}


/**
 * The mark each chat has and since when, to know one that has just come: every list the chat is in pops it (all and
 * mine), also as its row is drawn anew on the way to its new place.
 */
const shown = new Map<string, { tone: ChatTone | undefined; since: number }>();

/**
 * A chat's state as a mark at its picture's corner (the picture is `position: relative`; it sets `--mark-around`), or
 * `inline`, a dot in the line before its title. A mark
 * that comes while the chat is in view (a new message, work begun) pops in; ones there when the list is first drawn do not.
 */
export function ChatMark({ item, inline }: { item: ChatItem; inline?: boolean }) {
  const tone = chatTone(item);
  const mark = useRef<HTMLSpanElement>(null);
  const key = `${item.station}/${item.id}`;
  useLayoutEffect(() => {
    let had = shown.get(key);
    if (!had) shown.set(key, had = { tone, since: -Infinity });
    else if (had.tone !== tone) shown.set(key, had = { tone, since: performance.now() });
    if (!tone || performance.now() - had.since > 300 || !mark.current) return;
    play(mark.current, [{ transform: "scale(0)" }, { transform: "scale(1.3)", offset: 0.6 }, { transform: "scale(1)" }], { duration: 320, easing: "ease-out" });
  }, [key, tone]);
  return tone ? <span ref={mark} className={inline ? css.chatMarkInline : css.chatMark} data-tone={tone} role="img" aria-label={t(`web-main.chatMark.${tone}`)} /> : null;
}

/**
 * What a workspace has waiting, after its name where workspaces are switched (the core's `workspaceMarks`): a red dot
 * and how many of the chats its person takes part in want them, a blue one and how many are unread; nothing for none.
 */
export function MarkCounts({ mark }: { mark: WorkspaceMark | undefined }) {
  if (!mark?.tone) return null;
  return (
    <span className={css.markCounts} role="img" aria-label={mark.label ?? ""}>
      {mark.alert > 0 && <span className={css.markCount}><span className={css.chatMarkInline} data-tone="alert" />{mark.alert}</span>}
      {(mark.wait ?? 0) > 0 && <span className={css.markCount}><span className={css.chatMarkInline} data-tone="wait" />{mark.wait}</span>}
      {mark.unread > 0 && <span className={css.markCount}><span className={css.chatMarkInline} data-tone="done" />{mark.unread}</span>}
    </span>
  );
}

/**
 * A row's second line from where its chat stands (the core's `stateText`; a core before it: its decision's `decision.text`),
 * by what the core says leads it (`lead`, `leadText`, `rest`: ChatItem's stateLead…): 奏 · … (Decision · …) in ink, its
 * lead word bold; needs-the-viewer in ink too; 出错：…, 在等：…, 已完成 as quiet as the last message would be. `slot` (every
 * chat list, as Android's): a lead said as an icon (a bell, the waiting arc, a check; watching a radar before its words;
 * the two still going, waiting and watching, move: waiting's dots breathe in turn, the radar's arcs light up in turn, going
 * out) stands in the title's mark's column, centred under it, and what follows starts where the title does. `alert` (a
 * message that did not go, the row's `unsent`): in red.
 */
export function WaitingText({ text, lead, leadText, rest, className, slot = false, alert = false }: { text: string; lead?: string | null | undefined; leadText?: string | null | undefined; rest?: string | null | undefined; className: string; slot?: boolean; alert?: boolean }) {
  const turn = lead === "decision" || lead === "need";
  const icon = slot && (lead === "need" || lead === "done" || lead === "wait" || lead === "watch") ? lead : null;
  if (icon) {
    const motion = icon === "watch" ? "watch" : icon === "wait" ? "wait" : undefined;
    const label = icon === "watch" ? text : t(icon === "need" ? "web-main.chatMark.alert" : icon === "done" ? "web-main.status.done" : "web-main.status.waiting");
    const after = rest ?? "";
    const Moving = icon === "watch" ? Watch : Wait;
    return (
      <span className={`${className} ${css.leadLine}`} data-turn={turn || undefined} data-alert={alert || undefined} data-state-line="" aria-label={text}>
        <Tip label={label}><span className={css.leadSlot} role="img" aria-label={label} data-motion={motion}>
          {icon === "need" ? <Bell size={14} /> : icon === "done" ? <Check size={14} strokeWidth={1.7} /> : icon === "watch" ? <Watch size={14} strokeWidth={1.7} /> : <Wait size={14} strokeWidth={1.7} />}
          {/* What moves, each part on a copy of its own (ChatMark.css.ts leadSlot). */}
          {motion && MOVING[motion].map(([n, plays]) => <span key={n} ref={plays} data-part={n}><Moving size={14} strokeWidth={1.7} /></span>)}
        </span></Tip>
        {after && <span className={css.leadRest}>{after}</span>}
      </span>
    );
  }
  const word = lead === "decision" && leadText && text.startsWith(leadText) ? leadText : "";
  return (
    <span className={className} data-turn={turn || undefined} data-alert={alert || undefined} data-state-line="">
      {word && <b className={css.waitingLead}>{word}</b>}<StatusText text={text.slice(word.length)} lead={word ? null : lead} rest={rest} />
    </span>
  );
}

/** The parts of the icons that move, by their place among the icon's children: waiting's three dots; watching's dot and arcs. */
/**
 * The lead icons' motions on one beat of 3.1s (motion.ts restingLoop: played while they move, nothing at all between;
 * as CSS loops, the compositor drew every frame of their rests too, 2026-10-24): waiting's dots breathe in turn, 0.3s
 * apart, in the first half; watching's dot beats, then its arcs light up, inner then outer. From and back to how they
 * stand between (ChatMark.css.ts leadSlot).
 */
const BEAT = 3100;
const BREATHE: Keyframe[] = [{ opacity: 0.35, easing: "ease-in-out" }, { opacity: 1, offset: 23 / 52, easing: "ease-in-out" }, { opacity: 0.35 }];
const PULSE: Keyframe[] = [{ transform: "scale(1)", easing: "ease-out" }, { transform: "scale(1.35)", offset: 8 / 22, easing: "ease-out" }, { transform: "scale(1)" }];
const LIT: Keyframe[] = [{ opacity: 0.3, easing: "ease-out" }, { opacity: 1, offset: 10 / 32, easing: "ease-out" }, { opacity: 0.3 }];
const onBeat = (frames: Keyframe[], at: number, share: number) => (el: HTMLElement | null) =>
  (el ? restingLoop(el, frames, { period: BEAT, at, duration: BEAT * share }) : undefined);
/** Each moving part (its place among the icon's children) with what plays it. */
const MOVING = {
  wait: [[2, onBeat(BREATHE, 0, 0.52)], [3, onBeat(BREATHE, 300, 0.52)], [4, onBeat(BREATHE, 600, 0.52)]],
  watch: [[1, onBeat(PULSE, 0, 0.22)], [2, onBeat(LIT, 180, 0.32)], [3, onBeat(LIT, 420, 0.32)]],
} as const;

/**
 * A row pressed on its state line (WaitingText) when the core says which message the state is about (`stateAbout`):
 * its chat, as it opens, goes to that message (jumpTo.ts). Pressed elsewhere, about none (a line that asks for a
 * decision is: the chat itself leads to what waits, Chat.tsx ToAsk), or with something unread (the chat opens at the
 * unread line, the message read on from there): nothing here.
 */
export function jumpFromLine(item: ChatItem, target: EventTarget): void {
  if (item.stateAbout == null || item.unread || item.thread == null || !(target instanceof Element) || !target.closest("[data-state-line]")) return;
  jumpTo({ station: item.station, thread: item.thread, seq: item.stateAbout });
}

/** What a row's second line says of where its chat stands, if anything (an older core: only a decision's line). */
export function stateLine(item: ChatItem): string | undefined {
  return item.stateText ?? item.decision?.text;
}
