// What a chat's pieces of work wait on someone to decide (the core's `asks`, work.rs), right over its composer: one
// card at a time, the first the core puts first (those waiting on the viewer, set aside last). Its answers are the
// core's: one with words (`text`) is sent as the viewer's message (`item.answer`); 待定 sets it aside (`item.defer`); what
// is written in its own field is said of it (`item.answer` with `reply`). Both screens draw the same card (Chat.tsx's panel, the phone's
// chat page); the phone takes 随便 and 待定 by swiping it (right, left) instead of by buttons.
//
// Motion goes by where things arrive: the card that is answered leaves from where it is (a copy of it flies off, from
// where the finger let it go), and the next one, laid out at once where it rests, rises there from the edge peeking
// under it.
import { useLayoutEffect, useRef, useState, type MouseEvent as ReactMouseEvent, type PointerEvent as ReactPointerEvent, type RefObject } from "react";
import type { WorkAnswer, WorkItem } from "./core/shapes.ts";
import { useCall } from "./core/react.ts";
import { reducedMotion } from "./motion.ts";
import { ArrowUp, ChevronRight } from "./icons.tsx";
import * as markCss from "./ChatMark.css.ts";
import * as css from "./Asks.css.ts";

/** How far (of its width) a card is swiped before letting go takes it, and how fast a fling has to be (px/ms). */
const TAKES = 0.35;
const FLING = 0.6;
const EASE = "cubic-bezier(.2, .7, .2, 1)";

export function AskCards({ asks, station, thread, swipe = false, onError, className }: {
  asks: WorkItem[] | undefined;
  /** The chat's station (its address) and thread (none before its station has made it). */
  station: string; thread: number | null;
  /** A touch screen's card: 随便 and 待定 by swiping it, not by buttons. */
  swipe?: boolean;
  onError(text: string): void;
  /** Where it sits over its page's composer (each page's own). */
  className: string;
}) {
  const call = useCall();
  // The one picked with 1 / N ›, while it still waits; else the first.
  const [picked, setPicked] = useState<string | null>(null);
  // Each time the card in front leaves, the next rises (even when it is the same one again: set aside, the only one).
  const [turn, setTurn] = useState(0);
  // What is being written on the card in front.
  const [reply, setReply] = useState("");
  // Copies of cards on their way off: the last one answered still flies after there is none left to show.
  const [flying, setFlying] = useState(0);
  // What is answered here the core leaves out (the agent's until it declares it again).
  const shown = asks ?? [];
  const front = shown.find((a) => a.key === picked) ?? shown[0];
  const at = front ? shown.indexOf(front) : 0;
  const n = shown.length;

  const wrap = useRef<HTMLDivElement>(null);
  const stack = useRef<HTMLDivElement>(null);
  const card = useRef<HTMLDivElement>(null);
  const under = useRef<HTMLDivElement>(null);

  // The list above keeps its end clear of the card (its page's `--asks-height`): as tall as it is, and the gap.
  useLayoutEffect(() => {
    const el = wrap.current;
    const page = el?.parentElement;
    if (!el || !page) return;
    const set = () => page.style.setProperty("--asks-height", `${el.offsetHeight}px`);
    set();
    const observer = new ResizeObserver(set);
    observer.observe(el);
    return () => { observer.disconnect(); page.style.removeProperty("--asks-height"); };
  }, [!!front || flying > 0]); // eslint-disable-line react-hooks/exhaustive-deps

  // The card in front rises from the edge under it when it takes the place of another; the first one comes up from the
  // composer.
  const was = useRef<string | null>(null);
  const turned = useRef(turn);
  useLayoutEffect(() => {
    const el = card.current;
    const key = front?.key ?? null;
    const before = was.current;
    const left = turned.current !== turn;
    was.current = key;
    turned.current = turn;
    if (!el || key === null || (key === before && !left)) return;
    el.style.transform = "";
    delete el.dataset.dragging;
    const fade = under.current;
    if (reducedMotion()) { hideUnder(fade); return; }
    if (before === null) {
      el.animate([{ transform: "translateY(12px)", opacity: 0 }, { transform: "none", opacity: 1 }], { duration: 260, easing: EASE });
      return;
    }
    // From the peeking edge: as wide as it, at its foot.
    const w = el.offsetWidth;
    const s = w > 0 ? (w - 24) / w : 1;
    el.animate([{ transform: `translateY(6px) scale(${s})`, opacity: 0.6 }, { transform: "none", opacity: 1 }], { duration: 320, easing: EASE });
    // What a swipe showed under it goes as the next one covers it.
    if (fade?.dataset.side) void fade.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 320, easing: EASE }).finished.then(() => hideUnder(fade), () => {});
  }, [front?.key, turn]); // eslint-disable-line react-hooks/exhaustive-deps

  // What swiping does, as the card in front offers it (read when a swipe ends).
  const does = useRef<SwipeDoes>({ right: null, left: null });
  const drag = useSwipeHandlers(card, under, does);

  if (!front && flying === 0) return null;

  /** The card in front leaves: a copy of it goes off that way (`side`, from where it is now), or back under the stack. */
  const leave = (side: 1 | -1 | 0) => {
    const el = card.current;
    const host = stack.current;
    if (el && host && !reducedMotion()) {
      const ghost = el.cloneNode(true) as HTMLElement;
      ghost.classList.add(css.ghost);
      ghost.setAttribute("aria-hidden", "true");
      ghost.style.top = `${el.offsetTop}px`;
      ghost.style.height = `${el.offsetHeight}px`;
      host.append(ghost);
      // The place stays as tall while it goes, even with nothing after it.
      host.style.minHeight = `${el.offsetHeight}px`;
      setFlying((f) => f + 1);
      const gone = () => {
        ghost.remove();
        setFlying((f) => f - 1);
        if (!host.querySelector(`.${css.ghost}`)) {
          host.style.minHeight = "";
          if (!card.current) hideUnder(under.current);
        }
      };
      const from = el.style.transform || "none";
      const w = host.offsetWidth;
      const to = side === 0 ? { transform: "translateY(6px) scale(.94)", opacity: 0 } : { transform: `translateX(${side * (w + 48)}px) rotate(${side * 8}deg)`, opacity: 1 };
      void ghost.animate([{ transform: from, opacity: 1 }, to], { duration: side === 0 ? 220 : 280, easing: side === 0 ? EASE : "cubic-bezier(.4, 0, .9, .6)", fill: "forwards" })
        .finished.then(gone, gone);
    }
    setTurn((t) => t + 1);
  };

  const next = () => {
    if (n < 2 || !front) return;
    leave(0);
    setPicked(shown[(at + 1) % n]!.key);
  };

  const answer = (a: WorkAnswer, side: 1 | -1 = 1) => {
    const item = front;
    if (!item) return;
    if (a.kind === "defer") {
      leave(side === 1 ? -1 : side);
      // The core puts it last; the next one is in front meanwhile.
      setPicked(n > 1 ? shown[(at + 1) % n]!.key : null);
      void call("item.defer", { station, session: item.session, key: item.key })
        .catch((e: Error) => onError(`没能待定「${item.title}」：${e.message}`));
      return;
    }
    if (!a.text) return;
    leave(side);
    setPicked(null);
    void call("item.answer", { station, session: item.session, ...(thread !== null ? { thread } : {}), key: item.key, answer: a.text })
      .catch((e: Error) => onError(`没能回复「${item.title}」：${e.message}`));
  };

  const send = () => {
    const item = front;
    const words = reply.trim();
    if (!item || !words) return;
    leave(1);
    setPicked(null);
    setReply("");
    void call("item.answer", { station, session: item.session, ...(thread !== null ? { thread } : {}), key: item.key, reply: words })
      .catch((e: Error) => { setReply(words); onError(`没能回复「${item.title}」：${e.message}`); });
  };

  const delegate = front?.answers.find((a) => a.kind === "delegate");
  const defer = front?.answers.find((a) => a.kind === "defer");
  does.current = { right: swipe && delegate ? () => answer(delegate, 1) : null, left: swipe && defer ? () => answer(defer, -1) : null };
  // On a touch screen these two are the swipes; their buttons' place says so.
  const buttons = front?.answers.filter((a) => !(swipe && (a.kind === "delegate" || a.kind === "defer"))) ?? [];
  const hint = swipe && (defer || delegate) ? [defer && "← 待定", delegate && "随便 →"].filter(Boolean).join("　") : null;

  return (
    <div ref={wrap} className={`${css.asks} ${className}`}>
      <div ref={stack} className={css.stack}>
        {/* More waiting behind it: the next one's edge, under its foot. */}
        {n > 1 && <div className={css.peek} aria-hidden="true" />}
        {swipe && (
          <div ref={under} className={css.under} aria-hidden="true">
            <span className={css.underRight}><b>→ 随便</b><small>agent 自己判断</small></span>
            <span className={css.underLeft}><small>排到最后，圈留着</small><b>待定 ←</b></span>
          </div>
        )}
        {front && <div ref={card} className={css.card} role="group" aria-label={`${front.lead}：${front.title}`} {...(swipe ? drag : {})}>
          <div className={css.top}>
            <span className={markCss.chatMarkInline} data-tone={front.mine ? "wait" : "other"} />
            <span className={css.lead}>{front.lead}</span>
            {n > 1 && <button type="button" className={css.count} onClick={next} aria-label="下一件">{at + 1} / {n}<ChevronRight size={12} /></button>}
          </div>
          <div className={css.title}>{front.title}</div>
          {front.line && <div className={css.line}>{front.line}</div>}
          <div className={css.answers}>
            {buttons.map((a) => (
              <button key={`${a.kind}:${a.label}`} type="button" className={css.answer} data-kind={a.kind} onClick={() => answer(a, a.kind === "defer" ? -1 : 1)}>{a.label}</button>
            ))}
            {hint && <span className={css.hint}>{hint}</span>}
          </div>
          {/* Anything else, said of it right here. */}
          <form className={css.reply} onSubmit={(e) => { e.preventDefault(); send(); }}>
            <input className={css.replyInput} value={reply} onChange={(e) => setReply(e.target.value)} placeholder="说点别的…" enterKeyHint="send" aria-label={`回复「${front.title}」`} />
            {reply.trim() && <button type="submit" className={css.replySend} aria-label="发送"><ArrowUp size={14} /></button>}
          </form>
        </div>}
      </div>
    </div>
  );
}

function hideUnder(el: HTMLElement | null) {
  if (el) delete el.dataset.side;
}

/**
 * Swiping the card on a touch screen: it follows the finger across (a little turned), what letting go would do showing
 * under it; let go far enough or flung, that is done (the card flies off from there); otherwise it springs back.
 * Going up or down first is the page's (nothing happens here).
 */
interface SwipeDoes { right: (() => void) | null; left: (() => void) | null }

function useSwipeHandlers(card: RefObject<HTMLDivElement | null>, under: RefObject<HTMLDivElement | null>, doing: RefObject<SwipeDoes>) {
  const go = useRef<{ id: number; x: number; y: number; dragging: boolean; last: { x: number; t: number }[] } | null>(null);
  // A swipe just ended: the click that may follow it is not a press on the button it began on.
  const swiped = useRef(false);
  const place = (dx: number) => {
    const el = card.current;
    if (!el) return;
    const w = el.offsetWidth || 1;
    el.style.transform = dx === 0 ? "" : `translateX(${Math.round(dx)}px) rotate(${(dx / w) * 4}deg)`;
    const does = doing.current;
    const side = dx > 0 ? (does.right ? "right" : "") : dx < 0 ? (does.left ? "left" : "") : "";
    if (under.current) { if (side) under.current.dataset.side = side; else delete under.current.dataset.side; }
  };
  const end = (e: ReactPointerEvent<HTMLDivElement>, cancelled: boolean) => {
    const g = go.current;
    const el = card.current;
    if (!g || g.id !== e.pointerId) return;
    go.current = null;
    if (!g.dragging || !el) return;
    swiped.current = true;
    const dx = e.clientX - g.x;
    const w = el.offsetWidth || 1;
    const first = g.last[0];
    const v = first && e.timeStamp > first.t ? (e.clientX - first.x) / (e.timeStamp - first.t) : 0;
    const side = dx > 0 ? 1 : -1;
    const takes = !cancelled && (Math.abs(dx) > w * TAKES || (Math.abs(v) > FLING && Math.sign(v) === side));
    const action = side === 1 ? doing.current.right : doing.current.left;
    if (takes && action) { action(); return; }
    // Back where it rests.
    const from = el.style.transform;
    el.style.transform = "";
    delete el.dataset.dragging;
    if (under.current) delete under.current.dataset.side;
    if (from && !reducedMotion()) el.animate([{ transform: from }, { transform: "translateX(0px) rotate(0deg)" }], { duration: 300, easing: "cubic-bezier(.3, 1.3, .5, 1)" });
  };
  return {
    onPointerDown: (e: ReactPointerEvent<HTMLDivElement>) => {
      if (e.pointerType === "mouse" && e.button !== 0) return;
      // Writing in its field is not swiping it.
      if ((e.target as HTMLElement).closest("form")) return;
      swiped.current = false;
      go.current = { id: e.pointerId, x: e.clientX, y: e.clientY, dragging: false, last: [{ x: e.clientX, t: e.timeStamp }] };
    },
    onPointerMove: (e: ReactPointerEvent<HTMLDivElement>) => {
      const g = go.current;
      const el = card.current;
      if (!g || g.id !== e.pointerId || !el) return;
      const dx = e.clientX - g.x, dy = e.clientY - g.y;
      if (!g.dragging) {
        if (Math.abs(dy) > 8 && Math.abs(dy) >= Math.abs(dx)) { go.current = null; return; }
        if (Math.abs(dx) < 8) return;
        g.dragging = true;
        el.setPointerCapture(e.pointerId);
        el.dataset.dragging = "";
        for (const a of el.getAnimations()) a.cancel();
      }
      g.last.push({ x: e.clientX, t: e.timeStamp });
      // Its speed over the last 80 ms.
      while (g.last.length > 2 && e.timeStamp - g.last[0]!.t > 80) g.last.shift();
      // Towards a side it cannot go, it comes along only a little.
      const can = dx > 0 ? doing.current.right : doing.current.left;
      place(can ? dx : dx / 4);
    },
    onPointerUp: (e: ReactPointerEvent<HTMLDivElement>) => end(e, false),
    onPointerCancel: (e: ReactPointerEvent<HTMLDivElement>) => end(e, true),
    // A swipe is not a press on the button it began on.
    onClickCapture: (e: ReactMouseEvent) => {
      if (swiped.current) { swiped.current = false; e.preventDefault(); e.stopPropagation(); }
    },
  };
}
