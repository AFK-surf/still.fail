// A new chat and a chat are one page: what is above changes (a new chat's scene, then the chat it made), the composer
// at its foot is one, kept, with what is typed, the focus and a composition under way, as a new chat becomes its chat
// (the shell keeps a page that is replaced by another, app.tsx). What the composer writes to is the page's: it says so
// (`useHost().use`), and the composer asks it when a message goes.
import { createContext, useContext, useLayoutEffect, useRef, useState, type RefObject } from "react";
import { useParams } from "react-router";
import { StationContext, type Station } from "../station.tsx";
import { useApp } from "./app.tsx";
import { ChatScreen, ComposerBar, DraftExtras, openAttach, useDraft, useUpload, type Draft } from "./Chat.tsx";
import { NewChatScreen } from "./NewChat.tsx";
import { Loading } from "./parts.tsx";

/** What the composer writes to, as the page above it says. */
export interface HostComposer {
  /** The station its files go to. */
  station: string;
  placeholder: string;
  /** Nothing can be sent (its station offline), and it says why. */
  offline: boolean;
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
  const { station: id } = useParams();
  const draft = useDraft();
  const now = useRef(draft);
  now.current = draft;
  const root = useRef<HTMLDivElement>(null);
  // The callbacks as the page last gave them; what it shows, as state (changing only when it does).
  const latest = useRef<HostComposer | null>(null);
  const [shown, setShown] = useState<Pick<HostComposer, "station" | "placeholder" | "offline"> | null>(null);
  const use = (spec: HostComposer) => {
    latest.current = spec;
    setShown((was) => (was && was.station === spec.station && was.placeholder === spec.placeholder && was.offline === spec.offline ? was
      : { station: spec.station, placeholder: spec.placeholder, offline: spec.offline }));
  };
  const station = id === undefined ? undefined : stations?.find((s) => s.id === id);
  const body = id === undefined ? <NewChatScreen />
    : !stations ? <Loading text="正在读取…" />
    : !station ? <Loading text="这个 workspace 里没有这台 station。" />
    : <StationContext.Provider value={station}><ChatScreen /></StationContext.Provider>;
  return (
    <HostContext.Provider value={{ draft, use }}>
      <div className="m-chat-host" ref={root}>
        {body}
        {/* Once shown, it stays (the page above changing hands it on). */}
        {shown && <Composer shown={shown} latest={latest} draft={draft} now={now} root={root} />}
      </div>
    </HostContext.Provider>
  );
}

/** The composer: a floating capsule at the page's foot, with the files and quotes going with the message. */
function Composer({ shown, latest, draft, now, root }: {
  shown: Pick<HostComposer, "station" | "placeholder" | "offline">; latest: RefObject<HostComposer | null>; draft: Draft; now: RefObject<Draft>;
  root: RefObject<HTMLDivElement | null>;
}) {
  const app = useApp();
  const upload = useUpload(draft, shown.station);
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
    <div className="m-composer m-host-composer" ref={capsule}>
      {/* Files pasted or dropped in go with the message, as ＋ adds them; offline, nothing goes to the station. */}
      <div className="m-floating m-composer-capsule" onClick={(e) => { if (e.target === e.currentTarget) draft.bumpFocus(); }}
        onPaste={(e) => { if (e.clipboardData.files.length) { e.preventDefault(); if (!shown.offline) upload(e.clipboardData.files); } }}
        onDragOver={(e) => { if (e.dataTransfer.types.includes("Files") && !shown.offline) e.preventDefault(); }}
        onDrop={(e) => { if (e.dataTransfer.files.length) { e.preventDefault(); if (!shown.offline) upload(e.dataTransfer.files); } }}>
        {shown.offline && <p className="m-composer-offline">这台 station 离线了：这里是之前读到的内容，暂时不能发消息。</p>}
        <DraftExtras draft={draft} />
        <ComposerBar draft={draft} placeholder={shown.placeholder} locked={shown.offline}
          onPlus={() => openAttach(app, upload)} onType={() => latest.current?.type?.()} onSend={() => latest.current?.send(now.current)} />
        {draft.error && <p className="m-error m-composer-error">{draft.error}</p>}
      </div>
    </div>
  );
}
