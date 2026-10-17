// A link to one of a station's screens in a message (an agent asking a person to take over: docs/remote-screens.md),
// as the core's `screenCard` topic says it: on a line of its own, a card as a file's (what the screen is by its mark,
// its title, the core's line about it), with the screen itself live above them where its station previews it (a tab
// of its browser); within a sentence, its title where the link was.
import { useEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { core, useTopic } from "../core/react.ts";
import type { ScreenCard as Card } from "../core/shapes.ts";
import { screenOfLink } from "../chatRefs.ts";
import { t } from "../i18n.ts";
import { ScreenFrames, type FrameConfig, type FrameHead } from "./frames.ts";
import * as chatCss from "../Chat.css.ts";
import * as css from "./ScreenLink.css.ts";

/** A preview's pace: a picture at most this often (the station sends the next once the last is acknowledged). */
const PEEK_MS = 500;
/** The picture a preview asks for, in device pixels at most: the card's width, twice over. */
const PEEK_SIZE = 640;

function useCard(href: string): Card | null {
  const of = screenOfLink(href);
  return useTopic<Card>(of ? { topic: "screenCard", station: of.station, screen: of.screen } : null).value ?? null;
}

/** A screen's kind at a glance, as a file's sheet is drawn (Chat.tsx FileTile): a display, or the globe for a browser tab. */
function ScreenTile({ kind }: { kind: string | undefined }) {
  return (
    <svg className={chatCss.fileTile} width="30" height="36" viewBox="0 0 30 36" aria-hidden="true">
      {kind === "browser" ? (
        <>
          <circle cx="15" cy="18" r="11.25" />
          <path d="M3.75 18H26.25M15 6.75C11.75 10 10.25 14 10.25 18S11.75 26 15 29.25M15 6.75C18.25 10 19.75 14 19.75 18S18.25 26 15 29.25" />
        </>
      ) : kind === "desktop" ? (
        <>
          <rect x="3.75" y="8" width="22.5" height="15.5" rx="2.5" />
          <path d="M15 23.5V28.5M10.5 28.5H19.5" />
        </>
      ) : null}
    </svg>
  );
}

const newName = () => (typeof crypto !== "undefined" && typeof crypto.randomUUID === "function" ? crypto.randomUUID() : `${Date.now().toString(36)}-${Math.random().toString(36).slice(2)}`);
const tell = (name: string, params: Record<string, unknown>) => { core().call(name, params).catch(() => undefined); };

/** Whether `el` is on the screen now, the page shown: a preview is open only then. */
function useShown(el: RefObject<HTMLElement | null>): boolean {
  const [inView, setInView] = useState(false);
  const [visible, setVisible] = useState(() => typeof document === "undefined" || document.visibilityState === "visible");
  useEffect(() => {
    const node = el.current;
    if (!node || typeof IntersectionObserver === "undefined") return;
    const watch = new IntersectionObserver(([entry]) => setInView(!!entry?.isIntersecting));
    watch.observe(node);
    const shown = () => setVisible(document.visibilityState === "visible");
    document.addEventListener("visibilitychange", shown);
    return () => { watch.disconnect(); document.removeEventListener("visibilitychange", shown); };
  }, [el]);
  return inView && visible;
}

/**
 * The screen live in its card (`screen.view` with `peek`: only looking, not among those on it, its tab not brought
 * forward), a picture every PEEK_MS while the card is on the screen; its mark until a picture comes (a tab behind
 * another casts none).
 */
function Peek({ station, screen, card }: { station: string; screen: string; card: Card }) {
  const box = useRef<HTMLSpanElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const shown = useShown(box);
  const [drawn, setDrawn] = useState(false);
  useEffect(() => {
    const c = canvas.current;
    if (!shown || !c) return;
    const name = newName();
    const abort = new AbortController();
    let open = true;
    // Each acknowledgement PEEK_MS after the one before: the station sends no faster.
    let at = 0;
    const timers = new Set<ReturnType<typeof setTimeout>>();
    const ack = (ts: number) => {
      at = Math.max(Date.now(), at + PEEK_MS);
      const timer = setTimeout(() => { timers.delete(timer); if (open) tell("screen.ack", { view: name, ts }); }, at - Date.now());
      timers.add(timer);
    };
    const frames = new ScreenFrames(c, { ack, keyframe: () => tell("screen.keyframe", { view: name }), drawn: () => setDrawn(true) });
    core().call("screen.view", { station, screen, view: name, codecs: ["jpeg"], maxWidth: PEEK_SIZE, maxHeight: PEEK_SIZE, peek: true }, (value, bytes) => {
      if (!open) return;
      const v = value as { config?: FrameConfig; frame?: FrameHead };
      if (v.frame) frames.frame(v.frame, bytes);
      else if (v.config) frames.config(v.config, bytes);
    }, abort.signal).catch(() => undefined);
    return () => {
      open = false;
      abort.abort();
      frames.close();
      for (const timer of timers) clearTimeout(timer);
    };
  }, [station, screen, shown]);
  // Its shape as its station lists it (a tab's viewport), within bounds: the card does not change size as it comes.
  const ratio = card.width > 0 && card.height > 0 ? Math.min(2, Math.max(0.75, card.width / card.height)) : 16 / 10;
  return (
    <span ref={box} className={css.peek} style={{ aspectRatio: String(ratio) }}>
      <canvas ref={canvas} className={css.peekPicture} data-drawn={drawn || undefined} />
      {!drawn && <span className={css.peekMark}><ScreenTile kind={card.kind} /></span>}
    </span>
  );
}

/** A link to a screen alone on its line: its card, opening its page (pages/ChatPage.tsx opens it in the app). `words`: the link's own, shown for its title. */
export function ScreenCard({ href, words }: { href: string; words: ReactNode | null }) {
  const card = useCard(href);
  const of = screenOfLink(href);
  const live = card?.peek && !card.gone && of ? { card, of } : null;
  const text = (
    <span className={chatCss.fileCardText}>
      <span className={chatCss.fileCardName}><span className={chatCss.fileCardStem}>{words ?? card?.title ?? " "}</span></span>
      <span className={`${chatCss.fileCardMeta} ${css.screenCardLine}`}>{card?.line ?? " "}</span>
    </span>
  );
  return (
    <a className={`${chatCss.fileCardOpen} ${css.screenCard}`} href={href} data-gone={card?.gone || undefined}>
      {live ? (
        <span className={`${chatCss.fileCard} ${css.peekCard}`} data-card="">
          <Peek station={live.of.station} screen={live.of.screen} card={live.card} />
          <span className={css.peekText}>{text}</span>
        </span>
      ) : (
        <span className={chatCss.fileCard} data-card="">
          <ScreenTile kind={card?.kind} />
          {text}
        </span>
      )}
    </a>
  );
}

/** A bare link to a screen within a sentence: the screen's title for its words. */
export function ScreenName({ href }: { href: string }) {
  const card = useCard(href);
  return <a href={href}>{card?.title ?? t("web-pages.screen.title")}</a>;
}
