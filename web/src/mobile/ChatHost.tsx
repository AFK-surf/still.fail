// A new chat and a chat are one page: what is above changes (a new chat's scene, then the chat it made), the composer
// at its foot is one, kept, with what is typed, the focus and a composition under way, as a new chat becomes its chat
// (the shell keeps a page that is replaced by another, app.tsx). What the composer writes to is the page's: it says so
// (`useHost().use`), and the composer asks it when a message goes.
import { ArchiveNotice } from "../ArchiveNotice.tsx";
import { createContext, useContext, useLayoutEffect, useRef, useState, type RefObject } from "react";
import { useParams } from "react-router";
import { StationContext, type Station } from "../station.tsx";
import { useApp } from "./app.tsx";
import { ChatScreen, ComposerBar, DraftExtras, openAttach, type Draft } from "./Chat.tsx";
import { useDraft } from "../draft.ts";
import { useStationCall, type Attachment } from "../api.ts";
import { NewChatScreen } from "./NewChat.tsx";
import { Loading } from "./parts.tsx";
import * as css from "./ChatHost.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import * as partsCss from "./styles/parts.css.ts";

/** What the composer writes to, as the page above it says. */
export interface HostComposer {
  /** The station its files go to. */
  station: string;
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

export function ChatHost({ stations }: { stations: Station[] | undefined }) {
  const { station: id, chat } = useParams();
  // Each chat keeps what is written to it; a new chat's goes on into the chat it makes. Files go to the station the
  // page writes to (its composer says which).
  const upload = useRef<(file: File) => Promise<Attachment>>(() => Promise.reject(new Error("没有 station")));
  const shared = useDraft({ key: chat === undefined ? undefined : `${id}:${chat}`, upload: (file) => upload.current(file) });
  const [focus, setFocus] = useState(0);
  const draft: Draft = { ...shared, focus, bumpFocus: () => setFocus((n) => n + 1) };
  const now = useRef(draft);
  now.current = draft;
  const root = useRef<HTMLDivElement>(null);
  // The callbacks as the page last gave them; what it shows, as state (changing only when it does).
  const latest = useRef<HostComposer | null>(null);
  const [shown, setShown] = useState<Pick<HostComposer, "station" | "placeholder" | "offline" | "archived"> | null>(null);
  const use = (spec: HostComposer) => {
    latest.current = spec;
    setShown((was) => (was && was.station === spec.station && was.placeholder === spec.placeholder && was.offline === spec.offline && was.archived === spec.archived ? was
      : { station: spec.station, placeholder: spec.placeholder, offline: spec.offline, ...(spec.archived !== undefined ? { archived: spec.archived } : {}) }));
  };
  const station = id === undefined ? undefined : stations?.find((s) => s.id === id);
  const body = id === undefined ? <NewChatScreen />
    : !stations ? <Loading text="正在读取…" />
    : !station ? <Loading text="这个 workspace 里没有这台 station。" />
    : <StationContext.Provider value={station}><ChatScreen /></StationContext.Provider>;
  return (
    <HostContext.Provider value={{ draft, use }}>
      <div className={css.mChatHost} ref={root}>
        {body}
        {/* Once shown, it stays (the page above changing hands it on). */}
        {shown && <Composer shown={shown} latest={latest} draft={draft} now={now} root={root} upload={upload} />}
      </div>
    </HostContext.Provider>
  );
}

/** The composer: a floating capsule at the page's foot, with the files and quotes going with the message. */
function Composer({ shown, latest, draft, now, root, upload: uploader }: {
  shown: Pick<HostComposer, "station" | "placeholder" | "offline" | "archived">; latest: RefObject<HostComposer | null>; draft: Draft; now: RefObject<Draft>;
  root: RefObject<HTMLDivElement | null>; upload: RefObject<(file: File) => Promise<Attachment>>;
}) {
  const app = useApp();
  const call = useStationCall(shown.station);
  uploader.current = (file) => call.upload(file);
  const upload = draft.add;
  const locked = shown.offline || !!shown.archived;
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
  return (
    <div className={`${css.mComposer} ${css.mHostComposer}`} ref={capsule}>
      {/* Files pasted or dropped in go with the message, as ＋ adds them; offline, nothing goes to the station. */}
      <div className={`${pagesCss.mFloating} ${css.mComposerCapsule}`} onClick={(e) => { if (e.target === e.currentTarget) draft.bumpFocus(); }}
        onPaste={(e) => { if (e.clipboardData.files.length) { e.preventDefault(); if (!locked) upload(e.clipboardData.files); } }}
        onDragOver={(e) => { if (e.dataTransfer.types.includes("Files") && !locked) e.preventDefault(); }}
        onDrop={(e) => { if (e.dataTransfer.files.length) { e.preventDefault(); if (!locked) upload(e.dataTransfer.files); } }}>
        {shown.archived && <ArchiveNotice className={css.mComposerOffline} offline={shown.offline} restore={() => latest.current?.restore?.() ?? Promise.resolve()} />}
        {shown.offline && <p className={css.mComposerOffline}>这台 station 离线了：这里是之前读到的内容，暂时不能发消息。</p>}
        <DraftExtras draft={draft} />
        <ComposerBar draft={draft} placeholder={shown.placeholder} locked={locked}
          onPlus={() => openAttach(app, upload)} onType={() => latest.current?.type?.()} onSend={() => latest.current?.send(now.current)} />
        {draft.error && <p className={`${partsCss.mError} ${css.mComposerError}`}>{draft.error}</p>}
      </div>
    </div>
  );
}
