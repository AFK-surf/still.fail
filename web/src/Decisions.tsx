// Decisions an agent left to people (a block post with options, client/core-ts/src/decisions.ts), as both screens draw
// them. In a chat: the post is a message like any other, its options right under it in one card, numbered, the
// recommended one last; once answered (or replaced), a quiet line saying how. On the decisions page (奏): one at a time, the post and
// what came just before it drawn as the chat draws them, its options under the post and the chat's composer floating
// over them at the foot; 待定 puts it at the back of the
// queue on this device, 不再提醒 stops asking this viewer. The phone swipes for those two (left, right); the wide
// screen lists them all and shows the one picked (DecisionDesk.tsx), with those two as buttons.
//
// A text card (`card.type` text) has a field to write in and a send button where the options would be
// (decision.reply); a login card (`login`), the login an agent started (MachineLogins.tsx LoginCard); a card of a type
// this page does not know, only a way to its chat, to answer there.
//
// Everything said goes through the core's calls (decision.answer / reply / defer / dismiss); what is under way shows
// on its button (doing.ts), what failed in a toast (useAct).
import { useLayoutEffect, useMemo, useRef, useState, type MouseEvent as ReactMouseEvent, type PointerEvent as ReactPointerEvent, type ReactNode } from "react";
import type { ChatMessage, DecisionItem, DecisionOption, DecisionsView, MessageCard } from "./core/shapes.ts";
import { useCall, useTopic } from "./core/react.ts";
import { CoreError, useApi, useStationViews } from "./api.ts";
import { scopeOf, StationContext, stationBase, useStation, type Station } from "./station.tsx";
import { doingMatches, failed, useDoingList } from "./doing.ts";
import { useAct } from "@stillfail/ui/toast.tsx";
import { ENTER, LEAVE_EASE_CSS, MOVE_EASE_CSS, MOVE_NEAR_MS, motionMs, play } from "@stillfail/ui/motion.ts";
import { listPaneOf, reserveRow } from "./listQueue.ts";
import { SaidInPlace, useSettling } from "./settling.tsx";
import { ComposerView, StaticMessage } from "./Chat.tsx";
import { DecisionsIdle } from "./DecisionsIdle.tsx";
import { VaultCard } from "./VaultApproval.tsx";
import { LoginCard } from "./MachineLogins.tsx";
import { useDraft, type Draft } from "./draft.ts";
import { MobileComposer, type HostComposer } from "./mobile/ChatHost.tsx";
import * as css from "./Decisions.css.ts";
import * as chatCss from "./Chat.css.ts";
import { t } from "./i18n.ts";
import { Check, Option1, Option2, Option3, Option4, Option5, Option6 } from "@stillfail/ui/icons.tsx";
import { Spinner, Waiting, type WaitNote } from "@stillfail/ui/waiting.tsx";
import { sampleDecisions } from "./samples.ts";

/** How far (of its width) the decision is swiped before letting go takes it, and how fast a fling has to be (px/ms). */
const TAKES = 0.35;
const FLING = 0.6;

/** Each option's number, drawn (a card has at most six; past that, set as text). */
const DIGITS = [Option1, Option2, Option3, Option4, Option5, Option6];

/** The options of one decision, in one card, numbered; pressing one answers with it (its label, quoting the post). */
export function DecisionOptions({ station, thread, seq, options, onPick, settled, className }: {
  station: string; thread: number; seq: number; options: DecisionOption[];
  /** Before the answer goes: the decisions page sends the decision on its way. */
  onPick?: (option: DecisionOption) => void;
  /** Answered, still drawn till they close (in a chat): none pressed any more, the one picked (its label) as it was. */
  settled?: string | null | undefined;
  className?: string;
}) {
  const call = useCall();
  const act = useAct();
  const doing = useDoingList();
  const sending = doing.find((d) => !failed(d) && doingMatches(d, "decision.answer", { station, thread, seq }));
  const pick = (o: DecisionOption, button: HTMLElement) => {
    if (sending || settled !== undefined) return;
    if (onPick) onPick(o);
    // In a chat, the answer (its row, in the outbox) comes in first, in the turn taken now, the options closing after
    // it; the list follows its end for it, as for words sent (Chat.tsx useToEnd).
    else {
      reserveRow(button, motionMs(ENTER.duration));
      listPaneOf(button)?.dispatchEvent(new Event("sent"));
    }
    act(call("decision.answer", { station, thread, seq, option: o.label }), t("web-main.decisions.answerWhat", { option: o.label }));
  };
  return (
    <div className={`${css.options} ${className ?? ""}`} role="group" aria-label={t("web-main.decisions.options")}>
      {options.map((o, i) => {
        const busy = sending?.params.option === o.label;
        const Digit = DIGITS[i];
        // (the one picked, answered: a check in its disc where its number was)
        const chosen = settled !== undefined && settled === o.label;
        return (
          <button key={o.label} type="button" className={css.choice} data-recommended={o.recommended || undefined} data-busy={busy || undefined}
            data-chosen={chosen || undefined}
            disabled={!!sending || settled !== undefined} aria-busy={busy || undefined} aria-description={o.recommended ? t("common.recommended") : undefined}
            onClick={(e) => pick(o, e.currentTarget)}>
            <span className={css.choiceNumber} aria-hidden="true">{chosen ? <Check size={12} /> : Digit ? <Digit size={20} /> : i + 1}</span>
            <span className={css.choiceLabel}>{o.label}</span>
            {o.detail && <span className={css.choiceDetail}>{o.detail}</span>}
            {busy && <Spinner inline className={css.choiceSpinner} />}
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
 * A text card's field and send button: Enter or the button sends what is written (`decision.reply`). It goes as a
 * message does: the field empties and `onSent` at once, the reply in its chat's outbox (sending, or not sent with a way
 * to send it again), not waiting on the station; refused by the core, the words come back and a toast says why.
 */
export function DecisionReply({ station, thread, seq, session, mobile, placeholder, onSent }: {
  station: string; thread: number; seq: number; session: string; mobile: boolean; placeholder?: string | undefined; onSent?: () => void;
  /** Not said any more (the reply goes at once, as a message does); kept for callers. */
  onSending?: (sending: boolean) => void;
}) {
  const call = useCall();
  const act = useAct();
  const api = useApi();
  const draftKey = `decision:${station}:${thread}:${seq}`;
  const shared = useDraft({ key: draftKey, station });
  const [focus, setFocus] = useState(0);
  const draft = { ...shared, focus, bumpFocus: () => setFocus((n) => n + 1) };
  const send = (written: Draft) => {
    if (!written.ready) return;
    const taken = written.take();
    onSent?.();
    const reply = call("decision.reply", {
      station, thread, seq, text: taken.text,
      attachments: taken.files.flatMap((f) => f.done ? [f.done] : []),
      uploads: taken.files.filter((f) => !f.done && !f.error).map(({ id, name, size }) => ({ id, name, size })),
      quotes: taken.quotes.map(({ id: _, ...q }) => q),
    });
    // Not taken by the core (the card no longer waits, the station gone): back in the field, if nothing was written since.
    act(reply.catch((e: unknown) => {
      if (e instanceof CoreError && e.code === "invalid_params" && !now.current.text.trim()) written.restore();
      throw e;
    }), t("web-main.decisions.replyWhat"));
  };
  const spec: HostComposer = { station, session, placeholder: placeholder || t("web-main.composer.placeholder"), offline: false, send };
  const latest = useRef<HostComposer | null>(spec);
  latest.current = spec;
  const now = useRef(draft);
  now.current = draft;
  const root = useRef<HTMLDivElement>(null);
  return (
    <div ref={root} className={css.reply} data-mobile={mobile || undefined} onPointerDown={(e) => e.stopPropagation()}>
      <div className={css.replyRoom} aria-hidden="true" />
      {mobile
        ? <MobileComposer shown={spec} draftKey={draftKey} latest={latest} draft={draft} now={now} root={root} inline />
        : <ComposerView draft={draft} thread={thread} sessionKey={session} draftKey={draftKey} submitDraft={send}
            placeholder={spec.placeholder} focusQuote={draft.focusQuote} onFocused={draft.quoteFocused} />}
    </div>
  );
}

/**
 * Under an agent's post with options, in its chat: the options while it waits for the viewer (none in a chat that
 * cannot be written to: `thread` null), else how it was settled, quietly, if the core says.
 */
export function MessageDecision({ message: m, thread, children }: { message: ChatMessage; thread: number | null;
  /** Under the options, going with them (its 忽略; not under a login card, which stays). */
  children?: ReactNode;
}) {
  const station = useStation().address;
  const d = m.decision;
  const open = !d?.resolved && !d?.dismissed;
  const box = useRef<HTMLDivElement>(null);
  // Settled, how it went in their place, its room going to its new height with whatever else changes (useSettling);
  // open again (an answer that failed), they are back at once.
  const [drawnOpen, setDrawnOpen] = useState(open);
  const shown = open || drawnOpen;
  useSettling(box, open, drawnOpen, setDrawnOpen);
  if (!m.card && !m.options?.length) return null;
  // A login card stays as its login goes (waiting, done, failed, cancelled): it says how it ended itself, once closed.
  if (m.card?.type === "login" && m.card.login) {
    return (
      <div ref={box} className={css.decision}>
        {open && m.card.assigneeText && <p className={css.settledLine}>{m.card.assigneeText}</p>}
        <LoginCard station={loginStation(station, m.card)} id={m.card.login} />
      </div>
    );
  }
  return (
    <div ref={box} className={css.decision}>
      {shown ? <>
        {/* Who decides; settled while it shows, it fades out where it is (the one picked is marked among the options,
            an answer in words is the viewer's message under them); let go, 已忽略 in its place. */}
        {m.card?.assigneeText && <SaidInPlace className={css.settledLine} text={d?.dismissed && d.text ? d.text : m.card.assigneeText} gone={!open && !d?.dismissed} />}
        {/* An agent's request for a vault item: approved here (VaultApproval.tsx), not answered in words. */}
        {m.card?.vault ? <VaultCard address={station} id={m.card.vault} />
          : thread !== null && cardType(m.card, m.options) === "options" && !!m.options?.length &&
          <DecisionOptions station={station} thread={thread} seq={m.seq} options={m.options} settled={open ? undefined : d?.chosen ?? null} />}
        {children}
      </> : d?.text ? <p className={css.settledLine}>{d.text}</p> : null}
    </div>
  );
}

/** Where a login card's login is: the chat's station, or another of its workspace (the card's `station`, its key). */
export function loginStation(chatStation: string, card: MessageCard): string {
  return card.station ? `${scopeOf(chatStation)}/${card.station}` : chatStation;
}

export const keyOf = (d: DecisionItem) => `${d.station}/${d.thread}/${d.seq}`;

/**
 * The decisions waiting for the viewer in a workspace (the core's `decisions` view: those set aside last, one answered
 * or dismissed here gone at once, back if that failed), as both pages go through them: one whose written reply is on
 * its way stays (`replying`). The pages stay when none is left, for the next to come.
 */
export function useDecisionQueue(workspace: string) {
  const view = useTopic<DecisionsView>({ topic: "decisions", workspace });
  const [replying, setReplying] = useState<DecisionItem | null>(null);
  // Only what places a station (its id, name, whether it is online): the same while those are.
  const stations = useStationViews(workspace);
  const call = useCall();
  const act = useAct();
  // The core lets go of one answered, dismissed or decided from here at once (back if that fails) and puts one set
  // aside last; here one being replied to stays in front until its reply is on its way.
  const items = useMemo(() => {
    const source = view.value?.items ?? [];
    return replying ? [replying, ...source.filter((d) => keyOf(d) !== keyOf(replying))] : source;
  }, [view.value, replying]);
  const where = (d: DecisionItem) => ({ station: d.station, thread: d.thread, seq: d.seq });
  // Kept by station while the stations are: a new one each render would draw everything under its StationContext again.
  const stationOf = useMemo(() => {
    const made = new Map<string, Station>();
    return (d: DecisionItem): Station => {
      const key = `${d.station}\n${d.stationName}`;
      let kept = made.get(key);
      if (!kept) {
        const s = stations?.find((x) => x.station === d.station);
        kept = { id: s?.id ?? d.station.split("/")[1] ?? "", name: s?.name ?? d.stationName, online: s?.online ?? true,
          address: d.station, base: stationBase(d.station), settings: `/w/${workspace}/settings` };
        made.set(key, kept);
      }
      return kept;
    };
  }, [stations, workspace]);
  // None to show while some of it is still read, or could not be: what it waits on (the core's), drawn in their place.
  const wait = view.value?.wait;
  const waiting: WaitNote | null = items.length > 0 ? null
    : wait ? (wait.reading || wait.failing.length > 0 ? wait : null)
    : view.error ? null : { reading: true };
  return {
    view, items, replying, setReplying, waiting,
    /** Whether it was set aside (待定). */
    isAside: (d: DecisionItem) => !!d.deferred,
    defer(d: DecisionItem) {
      act(call("decision.defer", where(d)), t("web-main.decisions.deferWhat"));
    },
    dismiss(d: DecisionItem) {
      act(call("decision.dismiss", where(d)), t("web-main.decisions.dismissWhat"));
    },
    /** The one the wide page shows from now on (the core's `shown`). */
    show(d: DecisionItem) {
      void call("decision.show", { workspace, ...where(d) }).catch(() => {});
    },
    /** The station a decision is on, for its messages (StationContext): the same object while the stations are. */
    station: stationOf,
  };
}

/**
 * A decision on its way off (answered: up; set aside: left; dismissed: right): a copy of `el` flies from where it is
 * now over what `place` shows next, then goes. Answered, it draws in to about 88% and is pulled up, faster and faster.
 */
export function flyOff(el: HTMLElement, place: HTMLElement, to: "left" | "right" | "up", scroller: string): void {
  const ghost = el.cloneNode(true) as HTMLElement;
  ghost.classList.add(css.ghost);
  ghost.classList.remove(css.arriving);
  ghost.setAttribute("aria-hidden", "true");
  ghost.inert = true;
  place.append(ghost);
  // A copy starts at its top: scrolled as the one it copies.
  const from = el.querySelector<HTMLElement>(scroller);
  const copy = ghost.querySelector<HTMLElement>(scroller);
  if (from && copy) copy.scrollTop = from.scrollTop;
  const start = el.style.transform || "translateX(0px)";
  const w = place.offsetWidth;
  const end = to === "up" ? `translateY(${-place.offsetHeight}px)` : `translateX(${to === "right" ? w + 24 : -(w + 24)}px)`;
  const frames = to === "up" ? [
    { transform: "translateY(0px) scale(1)", offset: 0 },
    { transform: `translateY(${-place.offsetHeight * 0.4}px) scale(.88)`, offset: 0.4 },
    { transform: `${end} scale(.88)`, offset: 1 },
  ] : [{ transform: start }, { transform: end }];
  if (to === "up") ghost.style.transformOrigin = "50% 0%";
  const finish = () => ghost.remove();
  void play(ghost, frames, { duration: to === "up" ? 360 : 260, easing: LEAVE_EASE_CSS, fill: "forwards" })
    .finished.then(finish, finish);
}

/**
 * The decisions waiting for the viewer in a workspace, one at a time (the phone's 奏): left 待定, right 不再提醒, by
 * swiping. `inline`: the messages' avatars in line with their names. `onOpen` opens the decision's chat.
 */
export function DecisionDeck({ workspace, inline, onOpen, className }: {
  workspace: string; inline: boolean; onOpen: (path: string) => void; className?: string;
}) {
  const queue = useDecisionQueue(workspace);
  const { view, items, replying, setReplying } = queue;
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
    if (el && place) flyOff(el, place, to, `.${css.scroll}`);
    if (el) { el.style.transform = ""; delete el.dataset.dragging; }
    setArriving(to !== "up");
    setTurn((t) => t + 1);
  };

  const defer = () => {
    if (!front || replying) return;
    leave("left");
    queue.defer(front);
  };
  const dismiss = () => {
    if (!front || replying) return;
    leave("right");
    queue.dismiss(front);
  };
  const answered = () => leave("up");

  const drag = useSwipe(card, under, { left: defer, right: dismiss });

  let body: ReactNode;
  if (!front) {
    // None while stations are still read: one made up, in its bones; read and none: what was done today.
    body = queue.waiting ? <Waiting note={queue.waiting} sample={<DecisionSample d={SAMPLE_DECISION} />} />
      : view.value ? <DecisionsIdle view={view.value} onOpen={onOpen} />
      : view.error ? <p className={css.empty}>{view.error.message}</p> : null;
  } else {
    const d = front;
    const path = `${stationBase(d.station)}/chats/${encodeURIComponent(d.session)}`;
    body = (
      <StationContext.Provider value={queue.station(d)}>
        <div key={`${keyOf(d)}#${turn}`} ref={card} className={`${css.card} ${arriving ? css.arriving : ""}`} {...drag}>
          <div className={css.scroll}>
            <div className={css.column}>
              <div className={css.head}>
                <button type="button" className={css.chatLink} onClick={() => onOpen(path)}>{d.title}</button>
                <span className={css.count}>1 / {items.length}</span>
              </div>
              <DecisionMessages d={d} inline={inline} />
              <DecisionPicks d={d} onAnswered={answered} onOpen={() => onOpen(path)} />
            </div>
          </div>
          <DecisionFoot>
            <div className={css.footColumn}>
              <DecisionAnswer d={d} mobile onAnswered={answered} onReplying={(sending) => setReplying(sending ? d : null)} />
              <div className={css.hint} aria-hidden="true"><span>← {t("web-main.decisions.defer")}</span><span>{t("web-main.decisions.dismiss")} →</span></div>
            </div>
          </DecisionFoot>
        </div>
      </StationContext.Provider>
    );
  }
  return (
    <div ref={host} className={`${css.deck} ${className ?? ""}`}>
      {front && (
        <div ref={under} className={css.under} aria-hidden="true">
          <span className={css.underSide} data-side="right">{t("web-main.decisions.dismiss")}</span>
          <span className={css.underSide} data-side="left">{t("web-main.decisions.defer")}</span>
        </div>
      )}
      {body}
    </div>
  );
}

/** A decision made up, for what the pages show while the decisions are read (in its bones). */
const SAMPLE_DECISION = sampleDecisions()[0]!;

/** A decision's card (`d`) as the pages draw it while they read the decisions, in its bones: its post, its options. */
export function DecisionSample({ d }: { d: DecisionItem }) {
  return (
    <div className={css.card}>
      <div className={css.scroll}>
        <div className={css.column}>
          <DecisionMessages d={d} inline={false} />
          <DecisionPicks d={d} onAnswered={() => undefined} onOpen={() => undefined} />
        </div>
      </div>
    </div>
  );
}

/** Who has to decide, then the decision's post and what came just before it, as its chat draws them. */
export function DecisionMessages({ d, inline }: { d: DecisionItem; inline: boolean }) {
  const keeper = d.message.by.agent ?? d.session;
  return <>
    {d.card?.assigneeText && <p className={css.settledLine}>{d.card.assigneeText}</p>}
    <div className={`${chatCss.chatMessages} ${inline ? chatCss.inlineHeads : ""}`} style={{ display: "flex", flexDirection: "column", gap: "20px" }}>
      {[...d.before, d.message].map((m) => <StaticMessage key={m.seq} message={m} keeper={keeper} />)}
    </div>
  </>;
}

/**
 * Under the post, as in its chat: its options (options), or a way to its chat (a type this page does not know).
 * `onAnswered` once one is picked.
 */
export function DecisionPicks({ d, onAnswered, onOpen }: { d: DecisionItem; onAnswered: () => void; onOpen: () => void }) {
  if (d.card?.vault) return <VaultCard address={d.station} id={d.card.vault} onDecided={onAnswered} />;
  const type = cardType(d.card, d.options);
  if (type === "options") return <DecisionOptions station={d.station} thread={d.thread} seq={d.seq} options={d.card?.options ?? d.options} onPick={onAnswered} />;
  if (type === "text") return null;
  if (type === "login" && d.card?.login) return <LoginCard station={loginStation(d.station, d.card)} id={d.card.login} />;
  return <button type="button" className={css.elsewhere} onClick={onOpen}>{t("web-main.decisions.elsewhere")}</button>;
}

/**
 * The reply to write, at the page's foot (options and text cards): the chat's composer. `onAnswered` once it is sent;
 * `onReplying` while it is on its way.
 */
export function DecisionAnswer({ d, mobile, onAnswered, onReplying }: {
  d: DecisionItem; mobile: boolean; onAnswered: () => void; onReplying: (sending: boolean) => void;
}) {
  const type = cardType(d.card, d.options);
  // A vault request is approved, not replied to.
  if ((type !== "options" && type !== "text") || d.card?.vault) return null;
  return <DecisionReply key={keyOf(d)} session={d.session} mobile={mobile} station={d.station} thread={d.thread} seq={d.seq}
    placeholder={type === "text" ? d.card?.placeholder : undefined} onSent={onAnswered} onSending={onReplying} />;
}

/**
 * The page's foot, floating over the decision's messages as the chat's composer does over its own: they scroll on
 * under it, kept clear at their end of its height and of the room an expanded composer takes over the options
 * (`--foot-height` on the card).
 */
export function DecisionFoot({ children }: { children: ReactNode }) {
  const foot = useRef<HTMLDivElement>(null);
  useLayoutEffect(() => {
    const el = foot.current;
    const card = el?.parentElement;
    if (!el || !card) return;
    const put = () => {
      const reply = el.querySelector<HTMLElement>(`.${css.reply}`);
      const room = reply?.querySelector<HTMLElement>(`.${css.replyRoom}`);
      const more = reply && room ? Math.max(0, room.offsetHeight - reply.offsetHeight) : 0;
      card.style.setProperty("--foot-height", `${el.offsetHeight + more}px`);
    };
    put();
    const seen = new ResizeObserver(put);
    seen.observe(el);
    return () => seen.disconnect();
  }, []);
  return <div ref={foot} className={css.foot}>{children}</div>;
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
    if (from) {
      const back = play(el, [{ transform: from }, { transform: "translateX(0px)" }], { duration: MOVE_NEAR_MS, easing: MOVE_EASE_CSS });
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
