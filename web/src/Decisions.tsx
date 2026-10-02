// Decisions an agent left to people (a block post with options, client/core/src/decisions.rs), as both screens draw
// them. In a chat: the post is a message like any other, its options right under it, one per line, the recommended one
// last; once answered (or replaced), a quiet line saying how. On the decisions page (奏): one at a time, the post and
// what came just before it drawn as the chat draws them, its options pinned at the foot; 待定 puts it at the back of the
// queue on this device, 不再提醒 stops asking this viewer. The phone swipes for those two (left, right); the wide
// screen has them as words in the hint line, and ← →.
//
// A text card (`card.type` text) has a field to write in and a send button where the options would be
// (decision.reply); a card of a type this page does not know, only a way to its chat, to answer there.
//
// Everything said goes through the core's calls (decision.answer / reply / defer / dismiss); what is under way shows
// on its button (doing.ts), what failed in a toast (useAct).
import { useEffect, useLayoutEffect, useMemo, useRef, useState, type MouseEvent as ReactMouseEvent, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import type { ChatMessage, DecisionItem, DecisionOption, DecisionsView, MessageCard } from "./core/shapes.ts";
import { useCall, useTopic } from "./core/react.ts";
import { useApi, useStations } from "./api.ts";
import { StationContext, stationBase, useStation, type Station } from "./station.tsx";
import { doingMatches, failed, useDoing, useDoingList } from "./doing.ts";
import { useAct } from "./toast.tsx";
import { reducedMotion } from "./motion.ts";
import { ComposerView, StaticMessage } from "./Chat.tsx";
import { useDraft, type Draft } from "./draft.ts";
import { MobileComposer, type HostComposer } from "./mobile/ChatHost.tsx";
import * as css from "./Decisions.css.ts";
import * as chatCss from "./Chat.css.ts";
import * as waitingCss from "./styles/waiting.css.ts";

/** How far (of its width) the decision is swiped before letting go takes it, and how fast a fling has to be (px/ms). */
const TAKES = 0.35;
const FLING = 0.6;

/** The options of one decision, one per line; pressing one answers with it (its label, quoting the post). */
export function DecisionOptions({ station, thread, seq, options, onPick, className }: {
  station: string; thread: number; seq: number; options: DecisionOption[];
  /** Before the answer goes: the decisions page sends the decision on its way. */
  onPick?: (option: DecisionOption) => void;
  className?: string;
}) {
  const call = useCall();
  const act = useAct();
  const doing = useDoingList();
  const sending = doing.find((d) => !failed(d) && doingMatches(d, "decision.answer", { station, thread, seq }));
  const pick = (o: DecisionOption) => {
    if (sending) return;
    onPick?.(o);
    act(call("decision.answer", { station, thread, seq, option: o.label }), `回复「${o.label}」`);
  };
  return (
    <div className={`${css.options} ${className ?? ""}`} role="group" aria-label="选项">
      {options.map((o) => {
        const busy = sending?.params.option === o.label;
        return (
          <button key={o.label} type="button" className={css.option} data-recommended={o.recommended || undefined} data-busy={busy || undefined}
            disabled={!!sending} aria-busy={busy || undefined} onClick={() => pick(o)}>
            <span className={css.optionLabel}>{o.label}</span>
            {o.detail && <span className={css.optionDetail}>{o.detail}</span>}
            {busy && <span className={`${waitingCss.spinner} ${css.optionSpinner}`} aria-hidden="true" />}
          </button>
        );
      })}
    </div>
  );
}

/** What kind of card it is: its `type`, or (a core before cards) options when it has some. */
export function cardType(card: MessageCard | undefined, options: readonly DecisionOption[] | undefined): string | undefined {
  return card?.type ?? (options?.length ? "options" : undefined);
}

/**
 * A text card's field and send button: Enter or the button sends what is written (`decision.reply`), a spinner on the
 * button meanwhile; failed, the words stay and a toast says why. `onSent` once it went through.
 */
export function DecisionReply({ station, thread, seq, session, mobile, placeholder, onSent, onSending }: {
  station: string; thread: number; seq: number; session: string; mobile: boolean; placeholder?: string | undefined; onSent?: () => void; onSending?: (sending: boolean) => void;
}) {
  const call = useCall();
  const act = useAct();
  const [asked, setAsked] = useState(false);
  const replying = useRef(false);
  const sending = useDoing("decision.reply", { station, thread, seq }) || asked;
  const api = useApi();
  const draftKey = `decision:${station}:${thread}:${seq}`;
  const upload = useRef((file: File) => api.uploadFile(file));
  const shared = useDraft({ key: draftKey, station, upload: (file) => upload.current(file) });
  const [focus, setFocus] = useState(0);
  const draft = { ...shared, starting: sending, ready: shared.ready && !sending, focus, bumpFocus: () => setFocus((n) => n + 1) };
  const send = (written: Draft) => {
    if (!written.ready || replying.current) return;
    replying.current = true;
    setAsked(true);
    onSending?.(true);
    const reply = call("decision.reply", {
      station, thread, seq, text: written.text.trim(),
      attachments: written.files.flatMap((f) => f.done ? [f.done] : []),
      quotes: written.quotes.map(({ id: _, ...q }) => q),
    });
    act(reply, "回复");
    reply.then(() => { written.take(); onSent?.(); }, () => undefined).finally(() => { replying.current = false; setAsked(false); onSending?.(false); });
  };
  const spec: HostComposer = { station, session, placeholder: placeholder || "发消息", offline: false, send };
  const latest = useRef<HostComposer | null>(spec);
  latest.current = spec;
  const now = useRef(draft);
  now.current = draft;
  const root = useRef<HTMLDivElement>(null);
  return (
    <div ref={root} onPointerDown={(e) => e.stopPropagation()}>
      {mobile
        ? <MobileComposer shown={spec} draftKey={draftKey} latest={latest} draft={draft} now={now} root={root} upload={upload} inline />
        : <ComposerView draft={draft} thread={thread} sessionKey={session} draftKey={draftKey} submitDraft={send}
            placeholder={spec.placeholder} locked={sending} focusQuote={draft.focusQuote} onFocused={draft.quoteFocused} />}
    </div>
  );
}

/**
 * Under an agent's post with options, in its chat: the options while it waits for the viewer (none in a chat that
 * cannot be written to: `thread` null), else how it was settled, quietly, if the core says.
 */
export function MessageDecision({ message: m, thread }: { message: ChatMessage; thread: number | null }) {
  const station = useStation().address;
  if (!m.card && !m.options?.length) return null;
  const d = m.decision;
  const open = !d?.resolved && !d?.dismissed;
  if (open) return <>
    {m.card?.assigneeText && <p className={css.settledLine}>{m.card.assigneeText}</p>}
    {thread !== null && cardType(m.card, m.options) === "options" && !!m.options?.length &&
      <DecisionOptions station={station} thread={thread} seq={m.seq} options={m.options} />}
  </>;
  return d?.text ? <p className={css.settledLine}>{d.text}</p> : null;
}

const keyOf = (d: DecisionItem) => `${d.station}/${d.thread}/${d.seq}`;

/**
 * The decisions waiting for the viewer in a workspace, one at a time (the core's `decisions` view: those set aside last).
 * `swipe`: the phone's (left 待定, right 不再提醒); otherwise those two are words in the hint line, and ← → on the
 * keyboard. `inline`: the messages' avatars in line with their names (the phone's). `onOpen` opens the decision's chat.
 */
export function DecisionDeck({ workspace, swipe, inline, onOpen, onEmpty, className }: {
  workspace: string; swipe: boolean; inline: boolean; onOpen: (path: string) => void; onEmpty?: (() => void) | undefined; className?: string;
}) {
  const view = useTopic<DecisionsView>({ topic: "decisions", workspace });
  // Let the core confirm that nothing remains: a locally hidden card can still come back on failure.
  const empty = !!view.value && !view.value.loading && view.value.count === 0 && !view.error;
  const returned = useRef(false);
  const [leaving, setLeaving] = useState(0);
  const [replying, setReplying] = useState<DecisionItem | null>(null);
  useEffect(() => {
    if (empty && !leaving && !replying && onEmpty && !returned.current) {
      returned.current = true;
      onEmpty();
    }
  }, [empty, leaving, replying, onEmpty]);
  const stations = useStations(workspace).value;
  const call = useCall();
  const act = useAct();
  // Answered or dismissed here: gone at once, before the core's list says so (back if the call failed).
  const [gone, setGone] = useState<ReadonlySet<string>>(new Set());
  // Set aside here: at the back at once, as the core will have them.
  const [aside, setAside] = useState<readonly string[]>([]);
  const items = useMemo(() => {
    const source = view.value?.items ?? [];
    const held = replying ? [replying, ...source.filter((d) => keyOf(d) !== keyOf(replying))] : source;
    const left = held.filter((d) => !gone.has(keyOf(d)));
    const at = (d: DecisionItem) => aside.indexOf(keyOf(d));
    return [...left.filter((d) => at(d) < 0), ...left.filter((d) => at(d) >= 0).sort((a, b) => at(a) - at(b))];
  }, [view.value, gone, aside, replying]);
  const front = items[0];
  // Each time one leaves another comes, even the same again (set aside, the only one).
  const [turn, setTurn] = useState(0);
  const [arriving, setArriving] = useState(false);

  const host = useRef<HTMLDivElement>(null);
  const card = useRef<HTMLDivElement>(null);
  const under = useRef<HTMLDivElement>(null);

  // The newest of its messages in view: the post over its options.
  useLayoutEffect(() => {
    const scroller = card.current?.querySelector<HTMLElement>(`.${css.scroll}`);
    if (scroller) scroller.scrollTop = scroller.scrollHeight;
  }, [front && keyOf(front), turn]); // eslint-disable-line react-hooks/exhaustive-deps

  /** The decision in view goes (a copy of it flies off that way, from where it is now), the next one rising in its place. */
  const leave = (to: "left" | "right" | "up") => {
    const el = card.current;
    const place = host.current;
    if (under.current) delete under.current.dataset.side;
    if (el && place && !reducedMotion()) {
      const ghost = el.cloneNode(true) as HTMLElement;
      ghost.classList.add(css.ghost);
      ghost.classList.remove(css.arriving);
      ghost.setAttribute("aria-hidden", "true");
      ghost.inert = true;
      place.append(ghost);
      // A copy starts at its top: scrolled as the one it copies.
      const from = el.querySelector<HTMLElement>(`.${css.scroll}`);
      const copy = ghost.querySelector<HTMLElement>(`.${css.scroll}`);
      if (from && copy) copy.scrollTop = from.scrollTop;
      const start = el.style.transform || "translateX(0px)";
      const w = place.offsetWidth;
      const end = to === "up" ? `translateY(${-place.offsetHeight}px)` : `translateX(${to === "right" ? w + 24 : -(w + 24)}px)`;
      setLeaving((n) => n + 1);
      const frames = to === "up" ? [
        { transform: "translateY(0px) scale(1)", offset: 0 },
        { transform: `translateY(${-place.offsetHeight * 0.4}px) scale(.88)`, offset: 0.4 },
        { transform: `${end} scale(.88)`, offset: 1 },
      ] : [{ transform: start }, { transform: end }];
      if (to === "up") ghost.style.transformOrigin = "50% 0%";
      void ghost.animate(frames, { duration: to === "up" ? 360 : 260, easing: to === "up" ? "cubic-bezier(.55, 0, .85, .35)" : "cubic-bezier(.4, 0, .9, .6)", fill: "forwards" })
        .finished.then(() => { ghost.remove(); setLeaving((n) => n - 1); }, () => { ghost.remove(); setLeaving((n) => n - 1); });
    }
    if (el) { el.style.transform = ""; delete el.dataset.dragging; }
    setArriving(to !== "up");
    setTurn((t) => t + 1);
  };

  const drop = (d: DecisionItem) => setGone((was) => new Set(was).add(keyOf(d)));
  const back = (d: DecisionItem) => setGone((was) => { const now = new Set(was); now.delete(keyOf(d)); return now; });
  const where = (d: DecisionItem) => ({ station: d.station, thread: d.thread, seq: d.seq });

  const defer = () => {
    if (!front || replying) return;
    leave("left");
    const key = keyOf(front);
    setAside((was) => [...was.filter((k) => k !== key), key]);
    act(call("decision.defer", where(front)), "待定");
  };
  const dismiss = () => {
    const d = front;
    if (!d || replying) return;
    leave("right");
    drop(d);
    act(call("decision.dismiss", where(d)).catch((e: unknown) => { back(d); throw e; }), "不再提醒");
  };
  const answered = (d: DecisionItem) => { leave("up"); drop(d); };

  // The wide screen's keys: ← 待定, → 不再提醒 (not while writing somewhere).
  const latest = useRef({ defer, dismiss });
  latest.current = { defer, dismiss };
  useEffect(() => {
    if (swipe) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.defaultPrevented || e.metaKey || e.ctrlKey || e.altKey || e.shiftKey) return;
      const t = e.target as HTMLElement | null;
      if (t && (t.closest("input, textarea, select, [contenteditable=\"\"], [contenteditable=\"true\"]"))) return;
      if (e.key === "ArrowLeft") { e.preventDefault(); latest.current.defer(); }
      else if (e.key === "ArrowRight") { e.preventDefault(); latest.current.dismiss(); }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [swipe]);

  const drag = useSwipe(card, under, { left: defer, right: dismiss });

  const station = useMemo<Station | null>(() => {
    if (!front) return null;
    const s = stations?.find((x) => x.station === front.station);
    return { id: s?.id ?? front.station.split("/")[1] ?? "", name: s?.name ?? front.stationName, online: s?.online ?? true,
      address: front.station, base: stationBase(front.station), settings: `/w/${workspace}/settings` };
  }, [front, stations, workspace]);

  let body: ReactNode;
  if (!front || !station) {
    body = view.value || view.error
      ? <p className={css.empty}>{view.error && !view.value ? view.error.message : view.value?.loading ? "正在读取…" : "没有等你决定的事"}</p>
      : null;
  } else {
    const d = front;
    const path = `${stationBase(d.station)}/chats/${encodeURIComponent(d.session)}`;
    const owner = () => d.message.by.agent ?? d.session;
    body = (
      <StationContext.Provider value={station}>
        <div key={`${keyOf(d)}#${turn}`} ref={card} className={`${css.card} ${arriving ? css.arriving : ""}`} {...(swipe ? drag : {})}>
          <div className={css.scroll}>
            <div className={css.column}>
              <div className={css.head}>
                <button type="button" className={css.chatLink} onClick={() => onOpen(path)}>{d.title}</button>
                <span className={css.count}>1 / {items.length}</span>
              </div>
              {d.card?.assigneeText && <p className={css.settledLine}>{d.card.assigneeText}</p>}
              <div className={`${chatCss.chatMessages} ${inline ? chatCss.inlineHeads : ""}`} style={{ display: "flex", flexDirection: "column", gap: "20px" }}>
                {[...d.before, d.message].map((m) => <StaticMessage key={m.seq} message={m} owner={owner} />)}
              </div>
            </div>
          </div>
          <div className={css.foot}>
            <div className={css.footColumn}>
              {(() => {
                const type = cardType(d.card, d.options);
                if (type === "options") return <>
                  <DecisionOptions station={d.station} thread={d.thread} seq={d.seq} options={d.card?.options ?? d.options} onPick={() => answered(d)} />
                  <DecisionReply key={keyOf(d)} session={d.session} mobile={swipe} station={d.station} thread={d.thread} seq={d.seq} onSent={() => answered(d)} onSending={(sending) => setReplying(sending ? d : null)} />
                </>;
                if (type === "text") return <DecisionReply key={keyOf(d)} session={d.session} mobile={swipe} station={d.station} thread={d.thread} seq={d.seq} placeholder={d.card?.placeholder} onSent={() => answered(d)} onSending={(sending) => setReplying(sending ? d : null)} />;
                return <button type="button" className={css.elsewhere} onClick={() => onOpen(path)}>去 chat 里回</button>;
              })()}
              {swipe
                ? <div className={css.hint} aria-hidden="true"><span>← 待定</span><span>不再提醒 →</span></div>
                : (
                  <div className={css.hint}>
                    <button type="button" className={css.hintButton} onClick={defer} title="←">待定</button>
                    <button type="button" className={css.hintButton} onClick={dismiss} title="→">不再提醒</button>
                  </div>
                )}
            </div>
          </div>
        </div>
      </StationContext.Provider>
    );
  }
  return (
    <div ref={host} className={`${css.deck} ${className ?? ""}`}>
      {swipe && front && (
        <div ref={under} className={css.under} aria-hidden="true">
          <span className={css.underSide} data-side="right">不再提醒</span>
          <span className={css.underSide} data-side="left">待定</span>
        </div>
      )}
      {body}
    </div>
  );
}

/**
 * Swiping the decision across with a finger: it follows (what letting go does shows under it, on the side it uncovers);
 * let go far enough or flung, that is done; otherwise it springs back. Going up or down first is its scroller's.
 */
function useSwipe(card: React.RefObject<HTMLDivElement | null>, under: React.RefObject<HTMLDivElement | null>, does: { left: () => void; right: () => void }) {
  const go = useRef<{ id: number; x: number; y: number; dragging: boolean; last: { x: number; t: number }[] } | null>(null);
  const latest = useRef(does);
  latest.current = does;
  // A swipe just ended: the click that may follow is not a press on the button it began on.
  const swiped = useRef(false);
  const place = (dx: number) => {
    const el = card.current;
    if (!el) return;
    el.style.transform = dx === 0 ? "" : `translateX(${Math.round(dx)}px)`;
    // Swiped right, its left is uncovered (不再提醒 there); swiped left, its right (待定).
    if (under.current) { if (dx !== 0) under.current.dataset.side = dx > 0 ? "right" : "left"; else delete under.current.dataset.side; }
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
    if (takes) { if (side === 1) latest.current.right(); else latest.current.left(); return; }
    // Back where it rests.
    const from = el.style.transform;
    el.style.transform = "";
    delete el.dataset.dragging;
    if (under.current) delete under.current.dataset.side;
    if (from && !reducedMotion()) {
      const back = el.animate([{ transform: from }, { transform: "translateX(0px)" }], { duration: 320, easing: "cubic-bezier(.3, 1.25, .5, 1)" });
      // What it uncovered stays until it is covered again.
      if (under.current) { const u = under.current; u.dataset.side = dx > 0 ? "right" : "left"; void back.finished.finally(() => { if (!go.current) delete u.dataset.side; }); }
    }
  };
  return {
    onPointerDown: (e: ReactPointerEvent<HTMLDivElement>) => {
      if (e.pointerType === "mouse" && e.button !== 0) return;
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
      place(dx);
    },
    onPointerUp: (e: ReactPointerEvent<HTMLDivElement>) => end(e, false),
    onPointerCancel: (e: ReactPointerEvent<HTMLDivElement>) => end(e, true),
    onClickCapture: (e: ReactMouseEvent) => {
      if (swiped.current) { swiped.current = false; e.preventDefault(); e.stopPropagation(); }
    },
  };
}
