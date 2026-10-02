// A new chat and a chat are one page: what is above changes (a new chat's scene, then the chat it made), the composer
// at its foot is one, kept, with what is typed, the focus and a composition under way, as a new chat becomes its chat
// (the shell keeps a page that is replaced by another, app.tsx). What the composer writes to is the page's: it says so
// (`useHost().use`), and the composer asks it when a message goes.
import { ArchiveNotice } from "../ArchiveNotice.tsx";
import { createContext, useContext, useLayoutEffect, useRef, useState, type RefObject } from "react";
import { useParams } from "react-router";
import { StationContext, type Station } from "../station.tsx";
import { useApp } from "./app.tsx";
import { ChatScreen, openAttach, openedAs, useComposerBar, type Draft } from "./Chat.tsx";
import { ComposerExtras } from "../Chat.tsx";
import { useDraft } from "../draft.ts";
import { useMorph } from "../morph.ts";
import { useStationCall, type Attachment } from "../api.ts";
import { NewChatScreen } from "./NewChat.tsx";
import { Loading } from "./parts.tsx";
import * as css from "./ChatHost.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as rootCss from "./styles/root.css.ts";
import { t } from "../i18n.ts";

/** What the composer writes to, as the page above it says. */
export interface HostComposer {
  /** The station its files and messages go to (its address). */
  station: string;
  /** The session its chat's files are kept by (null: none yet, a new chat). */
  session?: string | null;
  placeholder: string;
  /** Nothing can be sent (its station offline), and it says why. */
  offline: boolean;
  archived?: boolean;
  restore?(): Promise<unknown>;
  /** Sends what the draft holds now (given at the moment it is sent: never a draft from an earlier render). */
  send(draft: Draft): void;
  /** Typing (a chat's agent is warmed). */
  type?(): void;
}

interface Host { draft: Draft; use(spec: HostComposer): void }
const HostContext = createContext<Host | null>(null);

/** The page's composer: its draft, and where the page says what it writes to. */
export function useHost(): Host {
  const host = useContext(HostContext);
  if (!host) throw new Error("a chat page outside its host");
  return host;
}

/**
 * Whose draft a chat's page writes (a station's address, the chat's key), as the wide screen's page names it
 * (pages/ChatPage.tsx): what a preview over it offers its marks to, and what is written stays when the screen turns wide.
 */
export function draftKeyOf(station: string, chat: string): string {
  return `${station}:${openedAs(chat)}`;
}

type Shown = Pick<HostComposer, "station" | "session" | "placeholder" | "offline" | "archived">;

export function ChatHost({ stations }: { stations: Station[] | undefined }) {
  const { station: id, chat } = useParams();
  // The callbacks as the page last gave them; what it shows, as state (changing only when it does).
  const latest = useRef<HostComposer | null>(null);
  const [shown, setShown] = useState<Shown | null>(null);
  const use = (spec: HostComposer) => {
    latest.current = spec;
    setShown((was) => (was && was.station === spec.station && was.session === (spec.session ?? null) && was.placeholder === spec.placeholder && was.offline === spec.offline && was.archived === spec.archived ? was
      : { station: spec.station, session: spec.session ?? null, placeholder: spec.placeholder, offline: spec.offline, ...(spec.archived !== undefined ? { archived: spec.archived } : {}) }));
  };
  const station = id === undefined ? undefined : stations?.find((s) => s.id === id);
  // The host is outside the chat's StationContext: what it writes goes to the station the page says (a new chat's, as
  // picked), else the chat's, by its address, not the context's.
  const writesTo = stations?.find((s) => s.address === shown?.station) ?? station;
  // Each chat keeps what is written to it; a new chat's goes on into the chat it makes. Files go to the station the
  // page writes to (its composer says which).
  const upload = useRef<(file: File) => Promise<Attachment>>(() => Promise.reject(new Error(t("web-mobile.chat.noStationUpload"))));
  const draftKey = chat === undefined || station === undefined ? undefined : draftKeyOf(station.address, chat);
  const shared = useDraft({ key: draftKey, station: shown?.station ?? station?.address, upload: (file) => upload.current(file) });
  const [focus, setFocus] = useState(0);
  const draft: Draft = { ...shared, focus, bumpFocus: () => setFocus((n) => n + 1) };
  const now = useRef(draft);
  now.current = draft;
  const root = useRef<HTMLDivElement>(null);
  const body = id === undefined ? <NewChatScreen />
    : !stations ? <Loading text={t("web-mobile.reading")} />
    : !station ? <Loading text={t("web-mobile.noStation")} />
    : <StationContext.Provider value={station}><ChatScreen /></StationContext.Provider>;
  const composer = shown && <MobileComposer shown={shown} draftKey={draftKey} latest={latest} draft={draft} now={now} root={root} upload={upload} />;
  return (
    <HostContext.Provider value={{ draft, use }}>
      <div className={css.mChatHost} ref={root}>
        {body}
        {/* Once shown, it stays (the page above changing hands it on); in its station (the chats its @ offers). */}
        {writesTo ? <StationContext.Provider value={writesTo}>{composer}</StationContext.Provider> : composer}
      </div>
    </HostContext.Provider>
  );
}

/** The composer: a floating capsule at the page's foot, with the files and quotes going with the message, as the wide screen's composer shows them. */
export function MobileComposer({ shown, draftKey, latest, draft, now, root, upload: uploader, inline = false }: {
  shown: Shown; draftKey: string | undefined; latest: RefObject<HostComposer | null>; draft: Draft; now: RefObject<Draft>;
  root: RefObject<HTMLDivElement | null>; upload: RefObject<(file: File) => Promise<Attachment>>; inline?: boolean;
}) {
  const app = useApp();
  const call = useStationCall(shown.station);
  uploader.current = (file) => call.upload(file);
  const upload = draft.add;
  const locked = shown.offline || !!shown.archived || draft.starting;
  const capsule = useRef<HTMLDivElement>(null);
  // What is above keeps its end clear of the capsule, whatever its height.
  useLayoutEffect(() => {
    const el = capsule.current;
    const page = root.current;
    if (!el || !page) return;
    const set = () => page.style.setProperty("--m-bottom", `${el.offsetHeight}px`);
    set();
    const observer = new ResizeObserver(set);
    observer.observe(el);
    return () => observer.disconnect();
  }, [root]);
  const { menu, bar, expanded } = useComposerBar({
    draft, draftKey, sessionKey: shown.session ?? null, placeholder: shown.placeholder, locked,
    onPlus: () => openAttach(app, upload), onType: () => latest.current?.type?.(), onSend: () => latest.current?.send(now.current),
  });
  // Growing or shrinking (a line more, a file, a quote, sent and emptied) in one motion, as the wide screen's
  // (morph.ts): after the text box has taken its height (useComposerBar), so that it is read with it.
  const frame = useRef<HTMLDivElement>(null);
  useMorph(frame, `${expanded}|${draft.text}|${draft.files.length}|${draft.quotes.length}|${draft.error}|${shown.offline}|${shown.archived}`);
  return (
    <div className={`${inline ? css.mInlineComposer : `${css.mComposer} ${css.mHostComposer}`} ${rootCss.wide}`} ref={capsule}>
      {menu}
      {/* Files dropped in go with the message, as ＋ adds them (pasted ones, the text box takes); offline, nothing goes to the station. */}
      <div ref={frame} className={`${pagesCss.mFloating} ${css.mComposerCapsule}`} data-made-composer onClick={(e) => { if (e.target === e.currentTarget) draft.bumpFocus(); }}
        onDragOver={(e) => { if (e.dataTransfer.types.includes("Files") && !locked) e.preventDefault(); }}
        onDrop={(e) => { if (e.dataTransfer.files.length) { e.preventDefault(); if (!locked) upload(e.dataTransfer.files); } }}>
        {shown.archived && <ArchiveNotice className={css.mComposerOffline} offline={shown.offline} restore={() => latest.current?.restore?.() ?? Promise.resolve()} />}
        {shown.offline && <p className={css.mComposerOffline}>{t("web-mobile.chat.offline")}</p>}
        <ComposerExtras draft={draft} focusQuote={draft.focusQuote} onFocused={draft.quoteFocused} onDone={draft.bumpFocus} />
        {bar}
        {draft.error && <p className={`${partsCss.mError} ${css.mComposerError}`}>{draft.error}</p>}
      </div>
    </div>
  );
}
