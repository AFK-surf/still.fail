// 奏 on the wide screen: one of the sidebar's lists (beside 全部, 我参与的 and 监控中, sliding to it as they do), every
// decision waiting for the viewer, those set aside (待定) last; the one picked fills the 奏 page as the phone's card
// does, its options and the chat's composer at its foot. The sidebar stays on 奏 while another page is open (a new
// chat). ⌥↑ ⌥↓ go up and down the list (the chats' keys); 待定 and 不再提醒 are in the bar.
//
// How it moves: opened from 奏 in the sidebar's foot, the list comes out of that row (each row drawn where it rests,
// moved back there first). Answered, the decision is drawn in and pulled up and the next is under it (flyOff, as on the
// phone), its row closing over the one gone (listMotion.ts); set aside, it goes left and its row down to 待定; dismissed,
// it goes right.
import { createContext, useContext, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { useLocation, useNavigate } from "react-router";
import { animate } from "motion";
import type { DecisionItem } from "./core/shapes.ts";
import { DecisionAnswer, DecisionMessages, flyOff, keyOf, useDecisionQueue } from "./Decisions.tsx";
import { DecisionsIdle } from "./DecisionsIdle.tsx";
import { StationContext, stationBase } from "./station.tsx";
import { useShortcut } from "./keymap.ts";
import { useListMotion } from "./listMotion.ts";
import { LOCAL_MS, MOVE, reducedMotion } from "./motion.ts";
import { Time } from "./ui.tsx";
import * as css from "./DecisionDesk.css.ts";
import * as deckCss from "./Decisions.css.ts";
import * as nav from "./Sidebar.css.ts";
import * as sidebarCss from "./styles/sidebar.css.ts";
import { t } from "./i18n.ts";

/** Where 奏 was in the sidebar's foot when it was pressed, for the list to come out of (DecisionsEntry). */
let openedFrom: { top: number; at: number } | null = null;
export function openedAt(el: HTMLElement): void {
  openedFrom = { top: el.getBoundingClientRect().top, at: performance.now() };
}
/** Whether 奏 in the sidebar's foot was just pressed: its rows come out of it, and the sidebar does not slide. */
export const openedRecently = (): boolean => !!openedFrom && performance.now() - openedFrom.at < 1000;

/**
 * The question a decision asks, uncut (the row clamps it to two lines): what its agent said it needs, else its post's
 * first line; from a core before `question`, its line without 奏 · (Decision · in English).
 */
const question = (d: DecisionItem) => d.question || d.text.replace(/^(?:奏|Decision) · /, "") || d.title;

type Desk = ReturnType<typeof useDesk>;
const DeskContext = createContext<Desk | null>(null);

/**
 * The decisions waiting for the viewer in `workspace` and the one picked, kept for the workspace's whole page: the
 * sidebar lists them (DecisionRows, one of its lists) while the page shows another, and the 奏 page shows the one picked
 * (DecisionPage).
 */
export function DecisionDeskProvider({ workspace, children }: { workspace: string; children: ReactNode }) {
  const desk = useDesk(workspace);
  return <DeskContext.Provider value={desk}>{children}</DeskContext.Provider>;
}

function useDeskContext(): Desk {
  const desk = useContext(DeskContext);
  if (!desk) throw new Error("DecisionDeskProvider missing");
  return desk;
}

function useDesk(workspace: string) {
  const queue = useDecisionQueue(workspace);
  const { items, replying } = queue;
  // The one picked, by key; once it is gone, the one now where it was.
  const [picked, setPicked] = useState<string | null>(null);
  const was = useRef(0);
  const found = items.findIndex((d) => keyOf(d) === picked);
  const index = found >= 0 ? found : Math.min(was.current, items.length - 1);
  const d = index >= 0 ? items[index] : undefined;
  was.current = Math.max(index, 0);
  const [turn, setTurn] = useState(0);
  const [arriving, setArriving] = useState(false);
  const host = useRef<HTMLDivElement>(null);
  const card = useRef<HTMLDivElement>(null);

  const pick = (next: DecisionItem | undefined, arrive = false) => {
    if (!next) return;
    setPicked(keyOf(next));
    setArriving(arrive);
    setTurn((t) => t + 1);
  };
  /** The one in its place once `from` has gone (or moved to the back): the next, else the one before. */
  const after = (from: DecisionItem) => {
    const rest = items.filter((x) => keyOf(x) !== keyOf(from));
    return rest[Math.min(index, rest.length - 1)];
  };
  const leave = (to: "left" | "right" | "up") => {
    if (card.current && host.current) flyOff(card.current, host.current, to, `.${deckCss.scroll}`);
  };
  return {
    queue, items, index, d, turn, arriving, host, card, pick,
    defer() {
      if (!d || replying) return;
      leave("left");
      // Set aside, it goes to the back: the next is the one now in its place (itself if it is the only one).
      pick(after(d) ?? d, true);
      queue.defer(d);
    },
    dismiss() {
      if (!d || replying) return;
      leave("right");
      pick(after(d), true);
      queue.dismiss(d);
    },
    answered(one: DecisionItem) {
      leave("up");
      pick(after(one));
      queue.answered(one);
    },
    step(by: number) {
      if (!items.length) return false;
      pick(items[Math.max(0, Math.min(items.length - 1, index + by))]);
      return true;
    },
  };
}

/**
 * 奏 as one of the sidebar's lists (Sidebar.tsx ChatList), beside the chats': every decision waiting for the viewer,
 * those set aside last. Picking one shows it on the 奏 page (`page`), going there from another; while it is the list in
 * view (`active`), ⌥↑ ⌥↓ go up and down it.
 */
export function DecisionRows({ active, page }: { active: boolean; page: string }) {
  const { queue, items, d, pick, step } = useDeskContext();
  const { view } = queue;
  const navigate = useNavigate();
  const here = useLocation().pathname === page;
  const list = useRef<HTMLDivElement>(null);
  useListMotion(list);
  useOpening(list, active);
  const choose = (x: DecisionItem) => {
    pick(x);
    if (!here) navigate(page);
  };
  useShortcut("chat.prev", active ? () => { if (!step(-1)) return false; if (!here) navigate(page); } : null);
  useShortcut("chat.next", active ? () => { if (!step(1)) return false; if (!here) navigate(page); } : null);
  const firstAside = items.findIndex((x) => queue.isAside(x));
  return (
    <div ref={list} className={nav.navScroll} role="list" aria-label={t("web-main.decisions.title")} aria-hidden={!active || undefined} inert={!active || undefined}>
      {items.map((x, i) => (
        <div key={keyOf(x)} data-flip={keyOf(x)} role="listitem" className={css.item}>
          {i === firstAside && <div className={css.group}>{t("web-main.decisions.defer")}</div>}
          <button type="button" className={css.row} aria-current={(here && x === d) || undefined} data-aside={queue.isAside(x) || undefined}
            onMouseDown={(e) => e.preventDefault()} onClick={() => choose(x)}>
            <span className={css.question}>{question(x)}</span>
            <span className={css.meta}>
              <span className={css.metaWhere}>{x.title} · {x.stationName}</span>
              <Time className={css.metaTime} stamp={x.message.time?.createdAt} fixed />
            </span>
          </button>
        </div>
      ))}
      {view.value && !view.value.loading && items.length === 0 && <div className={css.emptyList}>{t("web-main.decisions.empty")}</div>}
    </div>
  );
}

/** The 奏 page: the decision picked in the sidebar's 奏, as the phone's card shows it, its options and the chat's composer at its foot. */
export function DecisionPage({ onOpen }: { onOpen: (path: string) => void }) {
  const { queue, d, turn, arriving, host, card, defer, dismiss, answered } = useDeskContext();
  const { view, replying, setReplying } = queue;

  // The newest of its messages in view: the post over its options.
  useLayoutEffect(() => {
    const scroller = card.current?.querySelector<HTMLElement>(`.${deckCss.scroll}`);
    if (scroller) scroller.scrollTop = scroller.scrollHeight;
  }, [d && keyOf(d), turn]); // eslint-disable-line react-hooks/exhaustive-deps

  const path = d ? `${stationBase(d.station)}/chats/${encodeURIComponent(d.session)}` : "";
  const empty = view.value || view.error ? (view.error && !view.value ? view.error.message : t("web-main.reading")) : null;
  return (
    <div className={css.page}>
      <header className={sidebarCss.pageBar}>
        <div className={css.barLead}>
          {d && <>
            <button type="button" className={css.barChat} onClick={() => onOpen(path)} title={t("web-main.decisions.openChat")}>{d.title}</button>
            <span className={css.barStation}>{d.stationName}</span>
          </>}
        </div>
        <div className={css.barActions}>
          {d && <>
            <button type="button" className={css.barButton} onClick={defer} disabled={!!replying}>{t("web-main.decisions.defer")}</button>
            <button type="button" className={css.barButton} onClick={dismiss} disabled={!!replying}>{t("web-main.decisions.dismiss")}</button>
          </>}
        </div>
      </header>
      <div ref={host} className={deckCss.deck}>
        {d ? (
          <StationContext.Provider value={queue.station(d)}>
            <div key={`${keyOf(d)}#${turn}`} ref={card} className={`${deckCss.card} ${arriving ? deckCss.arriving : ""}`}>
              <div className={deckCss.scroll}>
                <div className={deckCss.column}>
                  <DecisionMessages d={d} inline={false} />
                </div>
              </div>
              <div className={deckCss.foot}>
                <div className={deckCss.footColumn}>
                  <DecisionAnswer d={d} mobile={false} onAnswered={() => answered(d)} onReplying={(sending) => setReplying(sending ? d : null)} onOpen={() => onOpen(path)} />
                </div>
              </div>
            </div>
          </StationContext.Provider>
        ) : view.value && !view.value.loading ? <DecisionsIdle view={view.value} onOpen={onOpen} />
          : empty && <p className={deckCss.empty}>{empty}</p>}
      </div>
    </div>
  );
}

/**
 * Opened from 奏 in the sidebar's foot (a moment ago): as the list comes into view, its rows come out of that row, each
 * drawn where it rests and moved there from it, one a little after another (the sidebar does not slide to it then:
 * `openedRecently`).
 */
function useOpening(list: React.RefObject<HTMLDivElement | null>, active: boolean) {
  useLayoutEffect(() => {
    if (!active || !openedFrom) return;
    const box = list.current;
    const rows = box ? [...box.querySelectorAll<HTMLElement>(":scope > [data-flip]")] : [];
    const from = openedFrom;
    // Only with the rows here already as the page shows (the core's copy): ones that had to come from a station, at no
    // time known, show where they rest when they come.
    if (!rows.length && performance.now() - from.at <= LOCAL_MS) return;
    const recent = openedRecently();
    openedFrom = null;
    if (!rows.length || !recent || reducedMotion()) return;
    rows.forEach((row, i) => {
      const dy = from.top - row.getBoundingClientRect().top;
      row.style.transform = `translateY(${dy}px)`;
      row.style.opacity = "0";
      void animate(row, { transform: [`translateY(${dy}px)`, "translateY(0px)"], opacity: [0, 1] },
        { ...MOVE, delay: i * 0.03, opacity: { duration: 0.16, delay: i * 0.03 } })
        .finished.then(() => { row.style.transform = ""; row.style.opacity = ""; }, () => {});
    });
  });
}
