// The share page (docs/public-share.md「查看页」): a published chat, read from its station by whoever has the link, and
// drawn as the chat draws it (Chat.tsx's message rows and their styles, Prose.tsx's Markdown, Viz.tsx's
// visualizations), read-only. The link says which station, which snapshot and its key (link.ts); the cloud says which
// relays (/v1/relays); a visit to the station reads the snapshot and its images and goes (guest.ts, iroh.ts). A file
// opens as it does in the chat, in its preview over the page (FilePreview.tsx): read from what this page has, or on a
// visit of its own when it has not (guestFiles). Nothing the station sends is opened as a page here: an HTML file is
// drawn only in the host's sandboxed /frame (FrameHost), an SVG only as an image, and a download is saved as bytes.
// Each way it can fail is a line of its own: the link cut short, still.fail or the station out of reach, the link
// gone, the station busy.
import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { placeFiles } from "../../../client/core-ts/src/placed.ts";
import type { Attachment } from "../core/shapes.ts";
import { Avatar } from "@stillfail/ui/Avatar.tsx";
import { FilePreview, FileSource, Gallery, type FileSourceOf, type GalleryOf } from "../FilePreview.tsx";
import { fileSize } from "@stillfail/ui/fileSize.ts";
import { Read } from "@stillfail/ui/icons.tsx";
import { imageBox } from "../imageBox.ts";
import { Prose, withBareLinks } from "../Prose.tsx";
import { thumbhashUrl } from "../thumbhash.ts";
import { FrameHost, VizHtml } from "../Viz.tsx";
import { useStation } from "../station.tsx";
import { thumbId } from "../viewerFlight.ts";
import { failure } from "@stillfail/ui/toast.tsx";
import { lang, t } from "../i18n.ts";
import * as chatCss from "../styles/chat.css.ts";
import * as controlsCss from "@stillfail/ui/styles/controls.css.ts";
import * as conversationCss from "../styles/conversation.css.ts";
import * as vizCss from "../Viz.css.ts";
import * as msgCss from "../Chat.css.ts";
import * as css from "./share.css.ts";
import { GuestError, guestFiles, isAgent, isHtml, isShownImage, readShared, type Got, type SharedEntry, type SharedFile, type Snapshot } from "./guest.ts";
import { Unreachable, visit } from "./iroh.ts";
import { parseLink, type ShareLink } from "./link.ts";
import { MONO } from "../modelMarks.ts";
import * as uiCss from "../ui.css.ts";
import mark16 from "../../public/mark-16.svg";
import mark16Dark from "../../public/mark-16-dark.svg";
import idle from "../../public/idle.svg";
import idleDark from "../../public/idle-dark.svg";
import offline from "../../public/offline.svg";
import offlineDark from "../../public/offline-dark.svg";
import * as spinnerCss from "@stillfail/ui/styles/spinner.css.ts";

/** The marks of models' makers (public/models), as the chat draws an agent by its maker's; one the page does not know: none. */
const MARKS = import.meta.glob<string>("../../public/models/*.svg", { query: "?url", import: "default", eager: true });
const markOf = (maker: string | undefined): string | undefined => (maker ? MARKS[`../../public/models/${maker}.svg`] : undefined);

declare const __SHARE_CLOUD__: string;

type Why = "malformed" | "cloud" | "offline" | "gone" | "busy" | "broken";
/** A file read: its bytes, and as it is drawn (an image's blob URL, an HTML file's words); null: it could not be. */
type Loaded = { got: Got; url?: string; html?: string } | null;
type State =
  | { at: "connecting" }
  | { at: "failed"; why: Why; error?: string }
  | { at: "shown"; link: ShareLink; relays: string[]; snapshot: Snapshot; files: Map<string, Loaded>; reading: boolean };

/** still.fail's relays, from the cloud this page was built for (cloud/share-hosts.ts). */
async function relaysOf(): Promise<string[]> {
  const answer = await fetch(`${__SHARE_CLOUD__}/v1/relays`, { credentials: "omit", referrerPolicy: "no-referrer" });
  if (!answer.ok) throw new Error(`${answer.status}`);
  const relays = ((await answer.json()) as { relay_urls?: unknown }).relay_urls;
  const urls = Array.isArray(relays) ? relays.filter((u): u is string => typeof u === "string") : [];
  if (urls.length === 0) throw new Error("no relays");
  return urls;
}

function loaded(f: SharedFile, got: Got | null): Loaded {
  if (got === null) return null;
  if (isShownImage(f)) return { got, url: URL.createObjectURL(new Blob([got.bytes as Uint8Array<ArrayBuffer>], { type: got.type })) };
  if (isHtml(f)) return { got, html: new TextDecoder().decode(got.bytes) };
  return { got };
}

/** Saves a file as `name`: downloaded, never opened as a page here (an HTML or SVG file would run as this page's),
 * whatever it is: the preview's download (FileSource `save`). */
function save(name: string, blob: Blob) {
  const url = URL.createObjectURL(new Blob([blob], { type: "application/octet-stream" }));
  const a = document.createElement("a");
  a.href = url;
  a.download = name;
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 60_000);
}

/** A time as the page says it: the day and the minute, the year too when it is not this one. */
function when(ms: number): string {
  const date = new Date(ms);
  const year = date.getFullYear() !== new Date().getFullYear();
  return new Intl.DateTimeFormat(lang() === "zh" ? "zh-CN" : "en", { ...(year ? { year: "numeric" } : {}), month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" }).format(date);
}

function attachment(f: SharedFile): Attachment {
  const a: Attachment = { name: f.name, path: f.k, size: f.size };
  if (f.width !== undefined && f.height !== undefined) Object.assign(a, { width: f.width, height: f.height });
  if (f.thumbhash !== undefined) a.thumbhash = f.thumbhash;
  return a;
}

/** The page's state: read as the link says, again on `retry`, anew when the link changes. */
function useShared(): [State, () => void] {
  const [hash, setHash] = useState(() => location.hash);
  const [attempt, setAttempt] = useState(0);
  const [state, setState] = useState<State>({ at: "connecting" });
  useEffect(() => {
    const changed = () => setHash(location.hash);
    addEventListener("hashchange", changed);
    return () => removeEventListener("hashchange", changed);
  }, []);
  useEffect(() => {
    const link = parseLink(hash);
    if (!link) return void setState({ at: "failed", why: "malformed" });
    let live = true;
    const urls: string[] = [];
    const set = (update: (s: State) => State) => { if (live) setState(update); };
    setState({ at: "connecting" });
    void (async () => {
      let relays: string[];
      try {
        relays = await relaysOf();
      } catch {
        return set(() => ({ at: "failed", why: "cloud" }));
      }
      let visited;
      try {
        visited = await visit(link.station, relays);
      } catch (e) {
        return set(() => ({ at: "failed", why: e instanceof Unreachable ? "offline" : "broken", error: failure(e) }));
      }
      if (!live) return void visited.close();
      // The snapshot's files by their number, as the visit reads them.
      const byKey = new Map<string, SharedFile>();
      try {
        await readShared(visited.conn, link, {
          snapshot: (snapshot) => {
            for (const e of snapshot.entries) for (const f of e.files) byKey.set(f.k, f);
            set(() => ({ at: "shown", link, relays, snapshot, files: new Map(), reading: true }));
          },
          file: (k, got) => {
            const l = loaded(byKey.get(k)!, got);
            if (l?.url) urls.push(l.url);
            set((s) => (s.at === "shown" ? { ...s, files: new Map(s.files).set(k, l) } : s));
          },
        });
        set((s) => (s.at === "shown" ? { ...s, reading: false } : s));
      } catch (e) {
        // Gone, busy, not readable; or the connection lost before the snapshot came: out of reach.
        set(() => (e instanceof GuestError ? { at: "failed", why: e.kind, error: e.message } : { at: "failed", why: "offline", error: failure(e) }));
      } finally {
        void visited.close();
      }
    })();
    return () => {
      live = false;
      for (const url of urls) URL.revokeObjectURL(url);
    };
  }, [hash, attempt]);
  return [state, () => setAttempt((n) => n + 1)];
}

export function Share() {
  const [state, retry] = useShared();
  useEffect(() => {
    document.title = state.at === "shown" && state.snapshot.title ? `${state.snapshot.title} · still.fail` : t("web-share.title");
  }, [state]);
  if (state.at === "connecting") return <StateLine picture="idle" line={<><span className={spinnerCss.spinner} aria-hidden="true" />{t("web-share.connecting")}</>} />;
  if (state.at === "failed") {
    const again = state.why === "cloud" || state.why === "offline" || state.why === "busy";
    const line = state.why === "broken" ? t("web-share.broken", { error: state.error ?? "" }) : t(`web-share.${state.why}`);
    return <StateLine picture={state.why === "offline" || state.why === "cloud" ? "offline" : "idle"} line={line}
      action={again ? <button type="button" className={controlsCss.btn} onClick={retry}>{t("common.retry")}</button> : null} />;
  }
  return <Shown state={state} />;
}

function Themed({ light, dark, size, alt = "" }: { light: string; dark: string; size: number; alt?: string }) {
  return <picture><source srcSet={dark} media="(prefers-color-scheme: dark)" /><img src={light} width={size} height={size} alt={alt} /></picture>;
}

function StateLine({ picture, line, action }: { picture: "idle" | "offline"; line: ReactNode; action?: ReactNode }) {
  const [light, dark] = picture === "idle" ? [idle, idleDark] : [offline, offlineDark];
  return (
    <main className={css.state}>
      <Themed light={light} dark={dark} size={72} />
      <p className={css.stateLine} role="status">{line}</p>
      {action}
    </main>
  );
}

/** Why reading a file failed, as the preview says it (`web-main.preview.loadFailed`). */
function why(e: unknown): string {
  if (e instanceof Unreachable) return t("web-share.offline");
  if (e instanceof GuestError && e.kind !== "broken") return t(`web-share.${e.kind}`);
  return failure(e);
}

/** What the page has of its files, and how one is opened: in the preview, over the page. */
type Files = { loaded: Map<string, Loaded>; reading: boolean; open(f: SharedFile): void; id: string };
/** Through context, not props: Prose draws a message's placed files once and keeps them, and they change as they come. */
const FilesContext = createContext<Files | null>(null);
const useFiles = () => useContext(FilesContext)!;

function Shown({ state }: { state: Extract<State, { at: "shown" }> }) {
  const { snapshot, link, relays, files } = state;
  const [opened, setOpened] = useState<Attachment | null>(null);
  // The preview reads what the page has already as it is; anything else on a visit of its own. One source for good:
  // a new one would have the preview read its file again.
  const have = useRef(files);
  have.current = files;
  const source = useMemo<FileSourceOf>(() => {
    const read = guestFiles(link, (k) => have.current.get(k)?.got, () => visit(link.station, relays));
    return {
      file: (key, file, thumb, onProgress) => read.file(key, file, thumb, onProgress).catch((e: unknown) => { throw new Error(why(e)); }),
      save: (file, blob) => save(file.name, blob),
    };
  }, [link, relays]);
  // An image open steps through the snapshot's images, as one in the chat does through the chat's: in the order the
  // page shows them (what an agent's words place first, where they place it; the rest below).
  const gallery = useMemo<GalleryOf>(() => ({
    list: () => snapshot.entries.flatMap((e) => {
      const { placed, rest } = isAgent(e) ? placeFiles(e.text, e.files) : { placed: new Map<string, SharedFile>(), rest: e.files };
      return [...placed.values(), ...rest].filter(isShownImage).map((f) => ({ sessionKey: link.id, file: attachment(f) }));
    }),
  }), [snapshot, link.id]);
  const ctx: Files = { loaded: files, reading: state.reading, open: (f) => setOpened(attachment(f)), id: link.id };
  const meta = [snapshot.station, t("web-share.published", { by: snapshot.by, time: when(snapshot.at) }), ...(snapshot.redacted > 0 ? [t("web-share.redacted", { n: snapshot.redacted })] : [])];
  return (
    <FrameHost.Provider value="/frame">
      <FileSource.Provider value={source}>
        <Gallery.Provider value={gallery}>
          <FilesContext.Provider value={ctx}>
            <main className={css.page}>
              <header className={css.head}>
                <h1 className={css.title}>{snapshot.title || t("web-share.title")}</h1>
                <p className={css.meta}>{meta.filter(Boolean).join(" · ")}</p>
              </header>
              <div className={css.list}>
                {snapshot.entries.map((e) => <Entry key={e.n} entry={e} />)}
              </div>
              <footer className={css.foot}>
                <a className={css.footLink} href="https://still.fail" target="_blank" rel="noopener noreferrer">
                  <Themed light={mark16} dark={mark16Dark} size={16} />{t("web-share.from")}
                </a>
              </footer>
            </main>
          </FilesContext.Provider>
          {opened && <FilePreview open onClose={() => setOpened(null)} sessionKey={link.id} file={opened} />}
        </Gallery.Provider>
      </FileSource.Provider>
    </FrameHost.Provider>
  );
}

/** One message, as the chat draws someone else's (Chat.tsx OthersMessage): the avatar out in the margin, the name and
 * time over what was said; an agent's words Markdown with its files placed in them, a person's plain words. */
function Entry({ entry: e }: { entry: SharedEntry }) {
  const agent = isAgent(e);
  return (
    <div className={`${conversationCss.msg} ${msgCss.msgRow}`} data-role={agent ? "agent" : "person"}>
      {agent
        ? <span className={`${chatCss.msgAvatar} ${msgCss.msgAvatarAgent}`}>{markOf(e.maker)
          ? <img className={uiCss.modelLogo} src={markOf(e.maker)} alt="" width={12} height={12} data-mono={MONO.has(e.maker!) || undefined} />
          : <Themed light={mark16} dark={mark16Dark} size={12} />}</span>
        : <span className={chatCss.msgAvatar}><Avatar id={e.author} name={e.author} size={18} /></span>}
      <div className={msgCss.msgMain}>
        <div className={conversationCss.msgHead}>
          <span className={msgCss.msgName}>{e.author}</span>
          <time className={conversationCss.msgTime} dateTime={new Date(e.at).toISOString()}>{when(e.at)}</time>
        </div>
        {agent
          ? <AgentWords entry={e} />
          : <>{e.text && <div className={chatCss.msgPlain}>{withBareLinks(e.text)}</div>}<FileList list={e.files} /></>}
      </div>
    </div>
  );
}

function AgentWords({ entry: e }: { entry: SharedEntry }) {
  const byPath = useMemo(() => new Map(e.files.map((f) => [f.k, f])), [e.files]);
  const { placed, rest } = useMemo(() => placeFiles(e.text, e.files), [e.text, e.files]);
  const shown = useMemo(() => new Map([...placed].map(([name, f]) => [name, attachment(f)])), [placed]);
  // The same function for good: a new one would have Prose read the words again.
  const draw = useCallback((a: Attachment, as: "shown" | "link", words?: ReactNode) => {
    const f = byPath.get(a.path);
    if (!f) return words;
    return as === "link" ? <FileLink file={f}>{words}</FileLink> : <FileShown file={f} />;
  }, [byPath]);
  return (
    <>
      <div className={conversationCss.markdown}><Prose files={shown} file={draw}>{e.text}</Prose></div>
      <FileList list={rest} />
    </>
  );
}

function FileList({ list }: { list: SharedFile[] }) {
  if (list.length === 0) return null;
  return <div className={msgCss.msgFiles}>{list.map((f) => <FileShown key={f.k} file={f} />)}</div>;
}

/** A link in an agent's words naming one of its files: it opens the file, as in the chat. */
function FileLink({ file: f, children }: { file: SharedFile; children: ReactNode }) {
  const files = useFiles();
  return <a href={`#${f.k}`} onClick={(e) => { e.preventDefault(); files.open(f); }}>{children}</a>;
}

/** A file where it is shown: an image, an HTML file placed in an agent's words as its visualization, else its card. */
function FileShown({ file: f }: { file: SharedFile }) {
  const files = useFiles();
  const got = files.loaded.get(f.k);
  if (isShownImage(f)) return <Image file={f} url={got?.url} failed={got === null || (got === undefined && !files.reading)} />;
  if (isHtml(f) && got?.html !== undefined) return <VizHtml html={got.html} title={f.name} heightKey={`share\n${files.id}\n${f.k}`} onOpen={() => files.open(f)} />;
  if (isHtml(f) && got === undefined && files.reading) return <div className={vizCss.viz} aria-busy="true"><div className={vizCss.vizWait} style={{ height: 120 }} /><div className={vizCss.vizBar} /></div>;
  return <FileCard file={f} />;
}

/** An image as the chat has it (Chat.tsx FileItem): its box set from its size, its likeness until it comes. */
function Image({ file: f, url, failed }: { file: SharedFile; url: string | undefined; failed: boolean }) {
  const files = useFiles();
  const station = useStation();
  const [shown, setShown] = useState(false);
  const { letterbox, ...size } = imageBox(attachment(f));
  const likeness = thumbhashUrl(f.thumbhash);
  return (
    <button type="button" className={msgCss.msgImage} style={size} aria-label={t("web-main.file.view", { name: f.name })} onClick={() => (url || failed) && files.open(f)}
      data-letterbox={letterbox ? "" : undefined} data-loaded={shown ? "reveal" : undefined} data-failed={failed || undefined} data-near=""
      // The preview opens out of it and closes back into it (viewerFlight.ts).
      data-viewer-thumb={url ? thumbId(station.address, files.id, f.k) : undefined}>
      {!shown && (likeness
        ? <span className={msgCss.msgImageWait} style={{ ...letterbox, backgroundImage: `url(${likeness})` }} data-likeness="" aria-hidden="true" />
        : <span className={msgCss.msgImageWait} style={letterbox} aria-hidden="true"><i /><i /><i /></span>)}
      {failed && <span className={msgCss.msgImageUnavailable} aria-hidden="true"><Read size={20} /><span>{t("web-main.file.noPreview")}</span></span>}
      {url && <img src={url} alt={f.name} onLoad={() => setShown(true)} />}
    </button>
  );
}

/** A file's card (Chat.tsx FileCard): its name and size; a click opens it. */
function FileCard({ file: f }: { file: SharedFile }) {
  const files = useFiles();
  return (
    <button type="button" className={msgCss.fileCardOpen} onClick={() => files.open(f)} aria-label={t("web-main.file.view", { name: f.name })}>
      <span className={msgCss.fileCard}>
        <Read size={16} aria-hidden="true" />
        <span className={msgCss.fileCardText}>
          <span className={msgCss.fileCardName}>{f.name}</span>
          <span className={msgCss.fileCardMeta}>{fileSize(f.size)}</span>
        </span>
      </span>
    </button>
  );
}
