// A new chat and a chat are one page: what is above changes (a new chat's scene, then the chat it made), the composer
// at its foot is one, kept, with what is typed, the focus and a composition under way, as a new chat becomes its chat
// (the shell keeps a page that is replaced by another, app.tsx). What the composer writes to is the page's: it says so
// (`useHost().use`), and the composer asks it when a message goes.
import { Unplug } from "@stillfail/ui/icons.tsx";
import { ArchiveNotice } from "../ArchiveNotice.tsx";
import { CacheColdNotice } from "../CacheColdNotice.tsx";
import { ComposerNotice, ComposerNotices } from "../ComposerNotice.tsx";
import { createContext, useCallback, useContext, useLayoutEffect, useMemo, useRef, useState, type RefObject } from "react";
import { useParams } from "react-router";
import { StationContext, type Station } from "../station.tsx";
import { useApp } from "./app.tsx";
import { ChatScreen, ChatWaiting, composerShown, openAttach, openedAs, sendSharing, useComposerBar, type Draft } from "./Chat.tsx";
import { ComposerExtras } from "../Chat.tsx";
import { openRefSheet, openStationFiles } from "./StationFiles.tsx";
import { useDraft } from "../draft.ts";
import { settling, useMorph } from "../morph.ts";
import { useStationCall, type Attachment } from "../api.ts";
import { NewChatScreen } from "./NewChat.tsx";
import { Picture } from "../picture.ts";
import { useTopic } from "../core/react.ts";
import * as css from "./ChatHost.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";
import * as rootCss from "./styles/root.css.ts";
import { t } from "../i18n.ts";
import { whenRowIn } from "../madeChat.ts";
import type { ChatCacheCold, ChatCcTo, ChatView } from "../core/shapes.ts";

// The composer's height, set at its page's root (MobileComposer), as that element's own; the room it leaves a chat's
// list, a length worked out there and inherited (ChatHost.css.ts): one changing with the other only past a few lines.
// A browser without registered properties inherits both as they are, as before.
for (const property of [
  { name: "--m-bottom", syntax: "<length>", inherits: false, initialValue: "72px" },
  { name: "--m-composer-room", syntax: "<length>", inherits: true, initialValue: "0px" },
]) {
  try { globalThis.CSS?.registerProperty?.(property); } catch { /* registered already (a module loaded again) */ }
}

/** What the composer writes to, as the page above it says. */
export interface HostComposer {
  /** The station its files and messages go to (its address). */
  station: string;
  /** The session its chat's files are kept by (null: none yet, a new chat). */
  session?: string | null;
  placeholder: string;
  /** Its station taken for down, and it says why (`offlineNote`, the core's words): what is written waits in the outbox
   * until it is reached, and no file is taken in (files go up to the station first). */
  offline: boolean;
  offlineNote?: string;
  archived?: boolean;
  restore?(): Promise<unknown>;
  /** Its agent's prompt cache over (ChatView `cacheCold`), and whether it goes on afresh as it is next started. */
  cacheCold?: ChatCacheCold;
  setAfresh?(session: string, afresh: boolean): Promise<unknown>;
  /** Sends what the draft holds now (given at the moment it is sent: never a draft from an earlier render). */
  send(draft: Draft): void;
  /** Typing (a chat's agent is warmed). */
  type?(): void;
  /** Its chat's Slack and Feishu threads, where what is sent can be copied (`chat.cc`): ＋'s menu ticks each. */
  cc?: { to: ChatCcTo[]; toggle(to: ChatCcTo): void };
}

/** The same while the page is (what is typed changes `now` alone): the page above is not drawn again at each key. */
interface Host { now: RefObject<Draft>; use(spec: HostComposer): void }
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

type Shown = Pick<HostComposer, "station" | "session" | "placeholder" | "offline" | "offlineNote" | "archived" | "cacheCold">;

export function ChatHost({ stations }: { stations: Station[] | undefined }) {
  const { station: id, chat } = useParams();
  // The callbacks as the page last gave them; what it shows, as state (changing only when it does).
  const latest = useRef<HostComposer | null>(null);
  const [shown, setShown] = useState<Shown | null>(null);
  const use = useCallback((spec: HostComposer) => {
    latest.current = spec;
    setShown((was) => (was && was.station === spec.station && was.session === (spec.session ?? null) && was.placeholder === spec.placeholder && was.offline === spec.offline && was.offlineNote === spec.offlineNote && was.archived === spec.archived && was.cacheCold?.session === spec.cacheCold?.session && was.cacheCold?.text === spec.cacheCold?.text && was.cacheCold?.afresh === spec.cacheCold?.afresh ? was
      : { station: spec.station, session: spec.session ?? null, placeholder: spec.placeholder, offline: spec.offline, ...(spec.offlineNote !== undefined ? { offlineNote: spec.offlineNote } : {}), ...(spec.archived !== undefined ? { archived: spec.archived } : {}), ...(spec.cacheCold !== undefined ? { cacheCold: spec.cacheCold } : {}) }));
  }, []);
  const station = id === undefined ? undefined : stations?.find((s) => s.id === id);
  // The host is outside the chat's StationContext: what it writes goes to the station the page says (a new chat's, as
  // picked), else the chat's, by its address, not the context's.
  const writesTo = stations?.find((s) => s.address === shown?.station) ?? station;
  // Each chat keeps what is written to it; a new chat's goes on into the chat it makes. Files go to the station the
  // page writes to (its composer says which).
  const draftKey = chat === undefined || station === undefined ? undefined : draftKeyOf(station.address, chat);
  const shared = useDraft({ key: draftKey, station: shown?.station ?? station?.address });
  const [focus, setFocus] = useState(0);
  const draft: Draft = { ...shared, focus, bumpFocus: () => setFocus((n) => n + 1) };
  const now = useRef(draft);
  now.current = draft;
  const root = useRef<HTMLDivElement>(null);
  const host = useMemo<Host>(() => ({ now, use }), [use]);
  // The same element while the page is the same, so typing (this drawing again) leaves it as it is.
  const body = useMemo(() => id === undefined ? <NewChatScreen />
    : !stations ? <ChatWaiting text={t("common.readingStations")} />
    : !station ? <ChatWaiting gone={t("web-mobile.noStation")} />
    : <StationContext.Provider value={station}><ChatScreen /></StationContext.Provider>, [id, stations, station]);
  // Drawn as a picture (../picture.ts), its page's effects never run to say what the composer writes to: as its chat says.
  const pictured = useTopic<ChatView>(useContext(Picture) && station && chat !== undefined ? { topic: "chat", station: station.address, session: openedAs(chat) } : null).value;
  const seen = shown ?? (pictured && station ? composerShown(pictured, station.address) : null);
  const composer = seen && <MobileComposer shown={seen} draftKey={draftKey} latest={latest} draft={draft} now={now} root={root} />;
  return (
    <HostContext.Provider value={host}>
      <div className={css.mChatHost} ref={root} data-new={id === undefined || undefined}>
        {body}
        {/* Once shown, it stays (the page above changing hands it on); in its station (the chats its @ offers). */}
        {writesTo ? <StationContext.Provider value={writesTo}>{composer}</StationContext.Provider> : composer}
      </div>
    </HostContext.Provider>
  );
}

/** The composer: a floating capsule at the page's foot, with the files and quotes going with the message, as the wide screen's composer shows them. */
export function MobileComposer({ shown, draftKey, latest, draft, now, root }: {
  shown: Shown; draftKey: string | undefined; latest: RefObject<HostComposer | null>; draft: Draft; now: RefObject<Draft>;
  root: RefObject<HTMLDivElement | null>;
}) {
  const app = useApp();
  const upload = draft.add;
  const locked = !!shown.archived || draft.starting;
  const noFiles = locked || shown.offline;
  const capsule = useRef<HTMLDivElement>(null);
  // The capsule itself, the box that changes shape (useMorph, below).
  const frame = useRef<HTMLDivElement>(null);
  // What is above keeps its end clear of the capsule, whatever its height.
  useLayoutEffect(() => {
    const el = capsule.current;
    const page = root.current;
    if (!el || !page) return;
    // Every element of the page inherits it: each change has the whole page's style worked out anew (a long chat's, all
    // its messages). So it changes once the capsule has its new shape, not at every frame of its motion there (morph.ts).
    let waiting = false;
    let held: (() => void) | null = null;
    const put = () => {
      held = null;
      const height = `${el.offsetHeight}px`;
      if (page.style.getPropertyValue("--m-bottom") !== height) page.style.setProperty("--m-bottom", height);
    };
    // Shorter as what was just sent leaves it, it keeps the list's foot until the message's row is in the list (madeChat.ts
    // whenRowIn), and gives it up in that frame: given up before, the list's end drops at once, and rises as the row comes.
    const set = () => {
      waiting = false;
      held?.();
      if (el.offsetHeight < (parseFloat(page.style.getPropertyValue("--m-bottom")) || 0)) held = whenRowIn(put);
      else put();
    };
    put();
    const observer = new ResizeObserver(() => {
      // A new chat's choices sit just above the composer: they must follow its height while it moves, or the
      // growing box covers them. There is no long message list to invalidate on that page.
      const moving = !page.hasAttribute("data-new") && frame.current ? settling(frame.current) : null;
      if (!moving) return set();
      if (waiting) return;
      waiting = true;
      void moving.then(set, set);
    });
    observer.observe(el);
    return () => { observer.disconnect(); held?.(); };
  }, [root]);
  const { menu, bar, expanded } = useComposerBar({
    draft, draftKey, sessionKey: shown.session ?? null, placeholder: shown.placeholder, locked, noFiles,
    onPlus: (plus) => openAttach(app, plus, upload, () => openStationFiles(app, shown.station, (items) => now.current.addDropped(items)), latest.current?.cc), onType: () => latest.current?.type?.(), onSend: () => {
      // What it refers to of other workspaces is shared first, when the viewer says (Chat.tsx sendSharing).
      const spec = latest.current;
      if (spec) sendSharing(app, spec.station, now.current.text, () => spec.send(now.current));
    },
  });
  // Growing or shrinking (a line more, a file, a quote, sent and emptied) in one motion, as the wide screen's
  // (morph.ts): after the text box has taken its height (useComposerBar), so that it is read with it.
  useMorph(frame, `${expanded}|${draft.text}|${draft.files.length}|${draft.quotes.length}|${draft.error}|${shown.offline}|${shown.archived}`);
  return (
    <div className={`${css.mComposer} ${css.mHostComposer} ${rootCss.wide}`} ref={capsule}>
      {menu}
      {(shown.archived || shown.cacheCold || shown.offline) && <ComposerNotices>
        {shown.archived && <ArchiveNotice offline={shown.offline} restore={() => latest.current?.restore?.() ?? Promise.resolve()} />}
        {shown.cacheCold && !shown.archived && <CacheColdNotice cold={shown.cacheCold} offline={shown.offline} setAfresh={(session, afresh) => latest.current?.setAfresh?.(session, afresh) ?? Promise.resolve()} />}
        {shown.offline && <ComposerNotice mark={<Unplug size={16} />}>{shown.offlineNote ?? t("web-mobile.chat.offline")}</ComposerNotice>}
      </ComposerNotices>}
      {/* Files dropped in go with the message, as ＋ adds them (pasted ones, the text box takes); offline, nothing goes to the station. */}
      <div ref={frame} className={`${pagesCss.mFloating} ${css.mComposerCapsule}`} data-made-composer onClick={(e) => { if (e.target === e.currentTarget) draft.bumpFocus(); }}
        onDragOver={(e) => { if (e.dataTransfer.types.includes("Files") && !noFiles) e.preventDefault(); }}
        onDrop={(e) => { if (e.dataTransfer.files.length) { e.preventDefault(); if (!noFiles) upload(e.dataTransfer.files); } }}>
        <ComposerExtras draft={draft} focusQuote={draft.focusQuote} onFocused={draft.quoteFocused} onDone={draft.bumpFocus}
          onRef={(f) => openRefSheet(app, f, {
            // A folder goes as a zip only from the chat's own station (zipped there).
            zips: !!f.ref?.dir && f.ref.station === shown.station,
            setMode: (mode) => now.current.setMode(f.id, mode),
            asFiles: draft.asFiles, setAsFiles: (on) => now.current.setAsFiles(on),
          })} />
        {bar}
        {draft.error && <p className={`${partsCss.mError} ${css.mComposerError}`}>{draft.error}</p>}
      </div>
    </div>
  );
}
