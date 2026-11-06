// A link to one of a station's screens in a message (an agent asking a person to take over: docs/remote-screens.md),
// as the core's `screenCard` topic says it: on a line of its own, a card as a file's (what the screen is by its mark,
// its title, the core's line about it), with the screen itself live above them where its station previews it (a tab
// of its browser); within a sentence, its title where the link was. On a chat's page the card also opens the screen
// beside the chat (OpenScreen: a tab of its side panel, `screen:[…]`), so it is seen and driven while the chat goes on.
import { createContext, useContext, useEffect, useRef, useState, type ReactNode, type RefObject } from "react";
import { Monitor, PanelOpen, Phone, Web } from "@stillfail/ui/icons.tsx";
import { Tip } from "../ui.tsx";
import { core, useTopic } from "../core/react.ts";
import type { ScreenCard as Card } from "../core/shapes.ts";
import { screenOfLink } from "../chatRefs.ts";
import { t } from "../i18n.ts";
import { ScreenFrames, Slots, decodable, peekAckAt, type Codec, type FrameConfig, type FrameHead } from "./frames.ts";
import * as chatCss from "../Chat.css.ts";
import * as css from "./ScreenLink.css.ts";

/** A preview's pace: a picture at most this often (the station sends the next once the last is acknowledged). */
const PEEK_MS = 500;
/** The picture a preview asks for, in device pixels at most: the card's width, twice over. */
const PEEK_SIZE = 640;
/**
 * A preview refused (its station previews as many as it can now), ended, or let go for a decoder asks again after this,
 * while its card is on the screen.
 */
const PEEK_AGAIN_MS = 5_000;
/**
 * The previews this page decodes as a video at once, two at most (an Android device's, which sends nothing else: WebCodecs,
 * with the hardware's decoders, which a phone has few of); one more is let go, its mark shown, and asks again later.
 */
const videoPeeks = new Slots(2);

/**
 * What a preview takes: JPEG, and H.264 where WebCodecs plays it (no H.265: a card is small and slow). A source that has
 * JPEG sends it a preview (station/src/screens/source.ts `codecFor`), so only one with nothing else sends it H.264.
 */
let peekCodecs: Promise<Codec[]> | null = null;
const peekCodecsHere = () => (peekCodecs ??= decodable(true));

/** Opens a station's screen beside the chat (pages/ChatPage.tsx): none where there is no side panel (a phone's chat). */
export const OpenScreen = createContext<((station: string, screen: string) => void) | null>(null);

/** A screen's tab in a chat's side panel (client/core-ts/src/chat-tabs.ts `screen:[…]`): its station's address and its id. */
export function screenTab(station: string, screen: string): string {
  return `screen:${JSON.stringify([station, screen])}`;
}
/** The screen a side panel's tab is, from its key; null for any other tab. */
export function screenOfTab(key: string): { station: string; screen: string } | null {
  if (!key.startsWith("screen:")) return null;
  try {
    const v: unknown = JSON.parse(key.slice("screen:".length));
    return Array.isArray(v) && typeof v[0] === "string" && typeof v[1] === "string" ? { station: v[0], screen: v[1] } : null;
  } catch {
    return null;
  }
}

/** What a screen is, as a link's card says it (the core's `screenCard`): its kind and title, wherever it is named. */
export function useScreenCard(station: string, screen: string): Card | null {
  return useTopic<Card>({ topic: "screenCard", station, screen }).value ?? null;
}

function useCard(href: string): Card | null {
  const of = screenOfLink(href);
  return useTopic<Card>(of ? { topic: "screenCard", station: of.station, screen: of.screen } : null).value ?? null;
}

/** A screen's kind at a glance, as a file's sheet is drawn (Chat.tsx FileTile): a display, the globe for a browser tab, a phone for a simulator. */
function ScreenTile({ kind }: { kind: string | undefined }) {
  return (
    <svg className={chatCss.fileTile} width="24" height="24" viewBox="0 0 24 24" aria-hidden="true">
      {kind === "browser" ? <Web size={24} stroke="inherit" />
        : kind === "desktop" ? <Monitor size={24} stroke="inherit" />
        : kind === "simulator" ? <Phone size={24} stroke="inherit" /> : null}
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
 * forward), a picture every PEEK_MS while the card is on the screen (a video's as fast as its station sends it); its
 * mark until a picture comes (a tab behind another casts none). JPEG where the source has it, else H.264 (an Android
 * device's), two of those at once on the page (`videoPeeks`); one refused or ended asks again PEEK_AGAIN_MS on.
 */
function Peek({ station, screen, card }: { station: string; screen: string; card: Card }) {
  const box = useRef<HTMLSpanElement>(null);
  const canvas = useRef<HTMLCanvasElement>(null);
  const shown = useShown(box);
  const [drawn, setDrawn] = useState(false);
  useEffect(() => {
    const c = canvas.current;
    if (!shown || !c) return;
    let stopped = false;
    let again: ReturnType<typeof setTimeout> | undefined;
    let endView: (() => void) | null = null;
    const open = async () => {
      const codecs = await peekCodecsHere();
      if (stopped) return;
      const name = newName();
      const abort = new AbortController();
      let live = true;
      let video = false;
      // A JPEG's acknowledgement PEEK_MS after the one before (the station sends no faster); a video's as it is shown
      // (its station paces it: peekAckAt).
      let codec: string | undefined;
      let at = 0;
      const timers = new Set<ReturnType<typeof setTimeout>>();
      const ack = (ts: number) => {
        const now = Date.now();
        at = peekAckAt(codec, now, at, PEEK_MS);
        if (at <= now) { tell("screen.ack", { view: name, ts }); return; }
        const timer = setTimeout(() => { timers.delete(timer); if (live) tell("screen.ack", { view: name, ts }); }, at - now);
        timers.add(timer);
      };
      const frames = new ScreenFrames(c, { ack, keyframe: () => tell("screen.keyframe", { view: name }), drawn: () => setDrawn(true) });
      const end = () => {
        if (!live) return;
        live = false;
        abort.abort();
        frames.close();
        for (const timer of timers) clearTimeout(timer);
        if (video) videoPeeks.free();
      };
      endView = end;
      // (once for this view: refused, ended, or let go for a decoder)
      const ended = () => {
        const was = live;
        end();
        if (was && !stopped) again = setTimeout(() => void open(), PEEK_AGAIN_MS);
      };
      core().call("screen.view", { station, screen, view: name, codecs, maxWidth: PEEK_SIZE, maxHeight: PEEK_SIZE, peek: true }, (value, bytes) => {
        if (!live) return;
        const v = value as { config?: FrameConfig; frame?: FrameHead };
        if (v.frame) frames.frame(v.frame, bytes);
        else if (v.config) {
          if (v.config.codec !== "jpeg" && !video) {
            if (!videoPeeks.take()) { ended(); return; }
            video = true;
          }
          codec = v.config.codec;
          frames.config(v.config, bytes);
        }
      }, abort.signal).catch(() => undefined).finally(ended);
    };
    void open();
    return () => {
      stopped = true;
      clearTimeout(again);
      endView?.();
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

/**
 * A link to a screen alone on its line: its card, opening its page (pages/ChatPage.tsx opens it in the app); on a chat's
 * page, a button over its corner opens it beside the chat instead. `words`: the link's own, shown for its title.
 */
export function ScreenCard({ href, words }: { href: string; words: ReactNode | null }) {
  const card = useCard(href);
  const of = screenOfLink(href);
  const beside = useContext(OpenScreen);
  const live = card?.peek && !card.gone && of ? { card, of } : null;
  const text = (
    <span className={chatCss.fileCardText}>
      <span className={chatCss.fileCardName}><span className={chatCss.fileCardStem}>{words ?? card?.title ?? " "}</span></span>
      <span className={`${chatCss.fileCardMeta} ${css.screenCardLine}`}>{card?.line ?? " "}</span>
    </span>
  );
  const link = (
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
  if (!beside || !of || card?.gone) return link;
  return (
    <span className={css.cardWith}>
      {link}
      <Tip label={t("web-main.viz.side")}>
        <button type="button" className={css.side} data-over={live ? "" : undefined} aria-label={t("web-main.viz.side")} onClick={() => beside(of.station, of.screen)}>
          <PanelOpen size={14} strokeWidth={1.75} />
        </button>
      </Tip>
    </span>
  );
}

/** A bare link to a screen within a sentence: the screen's title for its words. */
export function ScreenName({ href }: { href: string }) {
  const card = useCard(href);
  return <a href={href}>{card?.title ?? t("web-pages.screen.title")}</a>;
}
