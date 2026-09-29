// A web service on a station's machine (a dev server an agent started, a
// report it serves), shown in a frame beside the chat. The frame is on the
// preview host (PREVIEW_ORIGIN, see cloud/src/preview.ts), so the service's
// scripts reach nothing of ember's; its service worker hands every request of
// the service to this page, which sends it to the station through the core,
// like any other call, and hands the answer back. No port on the station is
// open to anyone. The desktop app needs none of that: the frame is at
// ember-preview://, which the app serves itself through its core; the bar
// over it is the same.
//
// A visualization an agent posted (an HTML file placed in its message, Viz.tsx) opens the same way, in the same
// frame (marking and all): only the frame's requests are answered here, with the file drawn in ember's stylesheet,
// instead of by a port on the station.
import { ArrowLeft, ArrowRight, External, Refresh, Web } from "./icons.tsx";
import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode, type RefObject } from "react";
import { useHref } from "react-router";
import { useLink } from "./station.tsx";
import { useCall } from "./core/react.ts";
import * as css from "./Preview.css.ts";
import * as pagesCss from "./styles/pages.css.ts";
import { useMarks } from "./annotate/Marks.tsx";
import { Tip } from "./ui.tsx";
import { previewKey, useViewport } from "./viewport.ts";
import { ViewportButton } from "./ViewportSize.tsx";
import { PreviewStage, useStage } from "./PreviewStage.tsx";
import { useVizFile, useVizMessages, vizDocument } from "./Viz.tsx";

declare const __PREVIEW_ORIGIN__: string;
const ORIGIN = __PREVIEW_ORIGIN__;

function toBase64(bytes: Uint8Array): string {
  let text = "";
  for (let i = 0; i < bytes.length; i += 0x8000) text += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(text);
}

const fromBase64 = (text: string) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));

interface Asked { id: number; method: string; path: string; headers: [string, string][]; body: Uint8Array | null }

/** A visualization's file: the session that sent it, its path there and its name. */
export interface FileSource { session: string; path: string; name: string }

/** A visualization's place among the previews (as a web service's job id is a service's): `file:` and its source. */
export function fileService(file: FileSource): string {
  return `file:${JSON.stringify([file.session, file.path, file.name])}`;
}

export function fileSourceOf(service: string | null): FileSource | null {
  if (!service?.startsWith("file:")) return null;
  try {
    const [session, path, name] = JSON.parse(service.slice("file:".length)) as [string, string, string];
    return typeof session === "string" && typeof path === "string" && typeof name === "string" ? { session, path, name } : null;
  } catch { return null; }
}

export interface Shown {
  station: string;
  /** How the station reaches it; never shown. None for a visualization (`file`). */
  port?: number | undefined;
  /** A visualization instead of a web service. */
  file?: FileSource | undefined;
  /** What people know it by. */
  name: string;
  external?: string | undefined;
  /** It ended and the station starts it again (how often so far); null while it is up. */
  restarting?: Restarting | null | undefined;
  /** The chat beside it, whose draft its marks go into (annotate/Marks.tsx); none: no marking. */
  draftKey?: string | undefined;
  /** Its job: the size its page is laid out at is kept by it (viewport.ts); none: as big as the preview. */
  service?: string | undefined;
}

export interface Restarting { restarts: number }

/** A web service (or a visualization, `file`) beside a chat, or on a page of its own (`alone`: no "open on its own" there). */
export function StationPreview({ station, port, file, name, service, alone = false, restarting = null, draftKey }:
  { station: string; port?: number; file?: FileSource; name: string; service: string; alone?: boolean; restarting?: Restarting | null; draftKey?: string }) {
  // Its page of its own, at the station's pages' place (a new window or tab: the browser's). A visualization has none.
  const own = useHref(useLink()(`/services/${encodeURIComponent(service)}`));
  return <ServiceFrame station={station} port={port} file={file} name={name} service={service} external={alone || file ? undefined : own} restarting={restarting} draftKey={draftKey} />;
}

/** The frame and its bar, wherever it is put (Previews.tsx keeps it in one place while it moves). */
export function ServiceFrame(shown: Shown) {
  if (shown.file) return <FileFrame {...shown} file={shown.file} />;
  const port = shown.port ?? 0;
  return window.emberDesktop ? <DesktopPreview {...shown} port={port} /> : <WebPreview {...shown} port={port} />;
}

/** One request of the frame's, answered. */
interface Answer { status: number; headers: [string, string][]; body: Uint8Array }

/**
 * A visualization in the web frame (the desktop app's too: its own frames go to a station's port): the frame asks for
 * its page and gets the file in ember's stylesheet, with what its widget kept; what the widget says comes from that
 * page, the frame's own frame, straight to this one (Viz.tsx's useVizMessages).
 */
function FileFrame({ station, file, ...shown }: Shown & { file: FileSource }) {
  const viz = useVizFile(file.session, { name: file.name, path: file.path, size: 0 });
  const frame = useRef<HTMLIFrameElement>(null);
  // What it keeps from now on, for its page asked for again (reload).
  const kept = useRef<{ state: unknown } | null>(null);
  const keep = viz && !viz.failed ? viz.keep : undefined;
  // The page is a frame of the preview's frame (which holds no other of the file's).
  const pages = () => { const outer = frame.current?.contentWindow; return outer ? Array.from({ length: outer.length }, (_, i) => outer[i]!) : []; };
  useVizMessages(pages, { origin: ORIGIN, draftKey: shown.draftKey, onState: (state) => { kept.current = { state }; keep?.(state); } });
  const html = viz && !viz.failed ? viz.html : null;
  const state = viz && !viz.failed ? viz.state : null;
  const serve = useCallback(async (asked: Asked): Promise<Answer> => {
    const page = asked.method === "GET" && !/\.[a-z0-9]+$/i.test(asked.path.split("?")[0]!);
    if (!page || html === null) return { status: 404, headers: [["content-type", "text/plain; charset=utf-8"]], body: new TextEncoder().encode("Not found") };
    const doc = vizDocument(html, kept.current ? kept.current.state : state);
    return { status: 200, headers: [["content-type", "text/html; charset=utf-8"], ["cache-control", "no-store"]], body: new TextEncoder().encode(doc) };
  }, [html, state]);
  if (viz?.failed) return <div className={css.preview}><p className={css.previewMissing}>读不到「{file.name}」。</p></div>;
  if (!viz) return <div className={css.preview} />;
  return <WebPreview {...shown} station={station} port={0} serve={serve} frame={frame} fixed />;
}

interface Bar {
  name: string;
  /** Where the service is now, as its frame says (null: not known). */
  at: string | null;
  go(path: string): void;
  reload(): void;
  /** Off at either end of the frame's history. */
  back?(): void;
  forward?(): void;
  canBack?: boolean;
  canForward?: boolean;
  external?: string | undefined;
  /** Anything else of the bar's (marking the page), before its page of its own. */
  extra?: ReactNode;
  /** What shows in the address's place for now (marking the page). */
  instead?: ReactNode;
  /** The page's size, after the address. */
  size?: ReactNode;
  /** Nowhere else to go (a visualization): the address is only its name. */
  fixed?: boolean;
}

/** Back, forward, reload, where it is (typed to go elsewhere), and its page of its own: over the frame. */
function PreviewBar({ name, at, go, reload, back, forward, canBack = false, canForward = false, external, extra, instead, size, fixed = false }: Bar) {
  const [typed, setTyped] = useState(at ?? "/");
  const [editing, setEditing] = useState(false);
  // Where it went is what the bar says, unless someone is typing there.
  useEffect(() => { if (at !== null && !editing) setTyped(at); }, [at, editing]);
  const icon = { size: 14, strokeWidth: 1.75 };
  return (
    <form className={css.previewBar} onSubmit={(e) => { e.preventDefault(); go(typed.startsWith("/") ? typed : `/${typed}`); (document.activeElement as HTMLElement | null)?.blur(); }}>
      {back && <Tip label="后退"><button type="button" className={pagesCss.iconBtn} aria-label="后退" disabled={!canBack} onClick={back}><ArrowLeft {...icon} /></button></Tip>}
      {forward && <Tip label="前进"><button type="button" className={pagesCss.iconBtn} aria-label="前进" disabled={!canForward} onClick={forward}><ArrowRight {...icon} /></button></Tip>}
      <Tip label="刷新"><button type="button" className={pagesCss.iconBtn} aria-label="刷新" onClick={reload}><Refresh {...icon} /></button></Tip>
      {instead ?? (
        <label className={css.previewAddress}>
          <Web size={14} strokeWidth={1.75} />
          <span className={css.previewHost}>{name}</span>
          {!fixed && <input className={css.previewPath} value={typed} onChange={(e) => setTyped(e.target.value)} onFocus={() => setEditing(true)} onBlur={() => setEditing(false)} aria-label="路径" spellCheck={false} />}
        </label>
      )}
      {size}
      {extra}
      {external && <Tip label="在新窗口打开"><a className={pagesCss.iconBtn} href={external} target="_blank" rel="noopener" aria-label="在新窗口打开"><External {...icon} /></a></Tip>}
    </form>
  );
}

/** Over the page while its service starts again; once it is up the page loads anew (`reload`). */
function Restart({ name, restarting, reload }: { name: string; restarting: Restarting | null | undefined; reload: () => void }) {
  const was = useRef(restarting);
  useEffect(() => {
    if (was.current && !restarting) reload();
    was.current = restarting;
  }, [restarting, reload]);
  if (!restarting) return null;
  return (
    <div className={css.previewRestart} role="status">
      <span className={css.previewRestartDot} aria-hidden="true" />
      <span><b>{name}正在重启</b><span>{restarting.restarts ? `第 ${restarting.restarts} 次 · ` : ""}起来后自动刷新</span></span>
    </div>
  );
}

/**
 * The bar over a frame that keeps the service's history (cloud/src/preview.ts on the web, the desktop app's own in
 * apps/desktop/src/main.ts): it says where the service is and whether it can go back or on (ember-preview-at), and is
 * told where to go (ember-preview-nav). `frame` is the frame at `origin`, loaded with `src`.
 */
function Framed({ name, external, restarting, draftKey, viewKey, origin, src, nonce, frame, fixed = false }:
  Omit<Shown, "station" | "port" | "service" | "file"> & { viewKey: string | undefined; origin: string | null; src: string | null; nonce: string; frame: RefObject<HTMLIFrameElement | null>; fixed?: boolean }) {
  const [at, setAt] = useState<string | null>(null);
  const [moves, setMoves] = useState({ back: false, forward: false });
  // A frame that can mark the page says so (an older one does not).
  const [markable, setMarkable] = useState(false);
  const viewport = useViewport(viewKey);
  const stage = useStage(viewKey, viewport);
  const link = useMemo(() => ({ frame, origin, nonce }), [frame, origin, nonce]);
  const marks = useMarks({ frame, origin, nonce, name, draftKey, able: markable, scale: stage.placed?.scale ?? 1 });
  useEffect(() => {
    if (!origin) return;
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== origin || event.source !== frame.current?.contentWindow || event.data?.nonce !== nonce) return;
      if (event.data?.type !== "ember-preview-at" || typeof event.data.path !== "string") return;
      setAt(event.data.path);
      setMoves({ back: event.data.back === true, forward: event.data.forward === true });
      setMarkable(event.data.annotate === true);
    };
    window.addEventListener("message", onMessage);
    return () => window.removeEventListener("message", onMessage);
  }, [origin, nonce, frame]);
  const nav = useCallback((action: "back" | "forward" | "reload" | "go", path?: string) => {
    if (origin) frame.current?.contentWindow?.postMessage({ type: "ember-preview-nav", action, path }, origin);
  }, [origin, frame]);
  const reload = useCallback(() => nav("reload"), [nav]);
  return (
    <div className={css.preview}>
      <PreviewBar name={name} at={at} go={(path) => nav("go", path)} reload={reload} back={() => nav("back")} forward={() => nav("forward")} canBack={moves.back} canForward={moves.forward} external={external} extra={marks.button} instead={marks.address} fixed={fixed}
        size={viewKey && <ViewportButton viewKey={viewKey} viewport={viewport} zoom={stage.zoom} turn={stage.turn} compact={marks.address !== null}
          folded={stage.folded} unfold={() => stage.fold(false)} />} />
      <PreviewStage stage={stage} link={link} over={marks.over} after={<Restart name={name} restarting={restarting} reload={reload} />}>
        {/* The frame never moves in the document (it would load anew): only its box's size and place change. */}
        {src && <iframe ref={frame} className={css.previewFrame} title={name} src={src} />}
      </PreviewStage>
    </div>
  );
}

function DesktopPreview({ station, port, file: _, ...shown }: Shown & { port: number }) {
  const [nonce] = useState(() => crypto.randomUUID());
  const [host, setHost] = useState<string | null>(null);
  const frame = useRef<HTMLIFrameElement>(null);
  useEffect(() => {
    let live = true;
    void window.emberDesktop!.previewHost(station, port).then((h) => { if (live) setHost(h); });
    return () => { live = false; };
  }, [station, port]);
  const origin = host && `ember-preview://${host}`;
  return <Framed {...shown} viewKey={shown.service && previewKey(station, shown.service)} origin={origin} src={origin && `${origin}/_ember/frame?n=${nonce}&path=%2F`} nonce={nonce} frame={frame} />;
}

/**
 * `serve`: answers the frame's requests here (a visualization) instead of the station's port; `frame`: the frame, for
 * whoever else speaks with its page; `fixed`: nowhere else to go, the bar only names it.
 */
function WebPreview({ station, port, file: _, serve, frame: given, fixed = false, ...shown }:
  Shown & { port: number; serve?: (asked: Asked) => Promise<Answer>; frame?: RefObject<HTMLIFrameElement | null>; fixed?: boolean }) {
  const call = useCall();
  // One frame for as long as this shows: moving about (back, reload, a path) is the frame's own, told to it.
  const [nonce] = useState(() => crypto.randomUUID());
  const [first] = useState("/");
  const own = useRef<HTMLIFrameElement>(null);
  const frame = given ?? own;
  const served = useRef(serve);
  served.current = serve;
  // The frame's requests of the service, handed here once it is ready: on to the station.
  useEffect(() => {
    const bridges: MessagePort[] = [];
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== ORIGIN || event.source !== frame.current?.contentWindow || event.data?.nonce !== nonce) return;
      if (event.data?.type !== "ember-preview-ready") return;
      const { port1, port2 } = new MessageChannel();
      bridges.push(port1);
      port1.onmessage = async ({ data }: MessageEvent<Asked>) => {
        try {
          if (served.current) {
            const answer = await served.current(data);
            port1.postMessage({ id: data.id, status: answer.status, headers: answer.headers, body: answer.body }, [answer.body.buffer]);
            return;
          }
          const answer = await call("station.preview", {
            station, port, method: data.method, path: data.path, headers: data.headers, body: data.body ? toBase64(data.body) : "",
          }) as { status: number; headers: [string, string][]; body: string };
          const body = fromBase64(answer.body);
          port1.postMessage({ id: data.id, status: answer.status, headers: answer.headers, body }, [body.buffer]);
        } catch (error) {
          port1.postMessage({ id: data.id, error: `没能从 station 取到：${error instanceof Error ? error.message : String(error)}` });
        }
      };
      frame.current?.contentWindow?.postMessage({ type: "ember-preview-port" }, ORIGIN, [port2]);
    };
    window.addEventListener("message", onMessage);
    return () => {
      window.removeEventListener("message", onMessage);
      for (const bridge of bridges) bridge.close();
    };
  }, [nonce, station, port, call]);
  return <Framed {...shown} viewKey={shown.service && previewKey(station, shown.service)} origin={ORIGIN} src={`${ORIGIN}/_ember/frame?n=${nonce}&path=${encodeURIComponent(first)}`} nonce={nonce} frame={frame} fixed={fixed} />;
}

/** A web service on a page of its own (its "open on its own"): the whole window with its bar, found by its job. */
export function ServicePage({ station, service }: { station: string; service: string }) {
  const call = useCall();
  const [job, setJob] = useState<{ name: string; port: number | null; state: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    call("job.get", { station, id: service })
      .then((j) => { const found = j as { name: string; port: number | null; state: string }; setJob(found); document.title = found.name; }, (e: Error) => setError(e.message));
  }, [call, station, service]);
  if (error) return <div className={`${css.previewPage} ${css.previewMissing}`}>找不到这个服务：{error}</div>;
  if (!job) return <div className={css.previewPage} />;
  if (job.port === null || (job.state !== "running" && job.state !== "exited")) return <div className={`${css.previewPage} ${css.previewMissing}`}>「{job.name}」已经停了。</div>;
  return <div className={css.previewPage}><StationPreview station={station} port={job.port} name={job.name} service={service} alone /></div>;
}
