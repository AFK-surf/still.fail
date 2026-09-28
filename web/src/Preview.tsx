// A web service on a station's machine (a dev server an agent started, a
// report it serves), shown in a frame beside the chat. The frame is on the
// preview host (PREVIEW_ORIGIN, see cloud/src/preview.ts), so the service's
// scripts reach nothing of ember's; its service worker hands every request of
// the service to this page, which sends it to the station through the core,
// like any other call, and hands the answer back. No port on the station is
// open to anyone. The desktop app needs none of that: the frame is at
// ember-preview://, which the app serves itself through its core.
import { ArrowLeft, ArrowRight, External, Refresh, Web } from "./icons.tsx";
import { useCallback, useEffect, useRef, useState } from "react";
import { useHref } from "react-router";
import { useLink } from "./station.tsx";
import { useCall } from "./core/react.ts";

declare const __PREVIEW_ORIGIN__: string;
const ORIGIN = __PREVIEW_ORIGIN__;

function toBase64(bytes: Uint8Array): string {
  let text = "";
  for (let i = 0; i < bytes.length; i += 0x8000) text += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(text);
}

const fromBase64 = (text: string) => Uint8Array.from(atob(text), (c) => c.charCodeAt(0));

interface Asked { id: number; method: string; path: string; headers: [string, string][]; body: Uint8Array | null }

interface Shown {
  station: string;
  /** How the station reaches it; never shown. */
  port: number;
  /** What people know it by. */
  name: string;
  external?: string | undefined;
  /** It ended and the station starts it again (how often so far); null while it is up. */
  restarting?: Restarting | null | undefined;
}

interface Restarting { restarts: number }

/** A web service beside a chat, or on a page of its own (`alone`: no "open on its own" there). */
export function StationPreview({ station, port, name, service, alone = false, restarting = null }:
  { station: string; port: number; name: string; service: string; alone?: boolean; restarting?: Restarting | null }) {
  // Its page of its own, at the station's pages' place (a new window or tab: the browser's).
  const own = useHref(useLink()(`/services/${encodeURIComponent(service)}`));
  const shown: Shown = { station, port, name, external: alone ? undefined : own, restarting };
  return window.emberDesktop ? <DesktopPreview {...shown} /> : <WebPreview {...shown} />;
}

interface Bar {
  name: string;
  /** Where the service is now, as its frame says (null: not known). */
  at: string | null;
  go(path: string): void;
  reload(): void;
  /** Absent where the frame's history cannot be reached (the desktop app's frame); off at either end of it. */
  back?(): void;
  forward?(): void;
  canBack?: boolean;
  canForward?: boolean;
  external?: string | undefined;
}

/** Back, forward, reload, where it is (typed to go elsewhere), and its page of its own: over the frame. */
function PreviewBar({ name, at, go, reload, back, forward, canBack = false, canForward = false, external }: Bar) {
  const [typed, setTyped] = useState(at ?? "/");
  const [editing, setEditing] = useState(false);
  // Where it went is what the bar says, unless someone is typing there.
  useEffect(() => { if (at !== null && !editing) setTyped(at); }, [at, editing]);
  const icon = { size: 14, strokeWidth: 1.75 };
  return (
    <form className="preview-bar" onSubmit={(e) => { e.preventDefault(); go(typed.startsWith("/") ? typed : `/${typed}`); (document.activeElement as HTMLElement | null)?.blur(); }}>
      {back && <button type="button" className="icon-btn" aria-label="后退" title="后退" disabled={!canBack} onClick={back}><ArrowLeft {...icon} /></button>}
      {forward && <button type="button" className="icon-btn" aria-label="前进" title="前进" disabled={!canForward} onClick={forward}><ArrowRight {...icon} /></button>}
      <button type="button" className="icon-btn" aria-label="刷新" title="刷新" onClick={reload}><Refresh {...icon} /></button>
      <label className="preview-address">
        <Web size={14} strokeWidth={1.75} />
        <span className="preview-host">{name}</span>
        <input className="preview-path" value={typed} onChange={(e) => setTyped(e.target.value)} onFocus={() => setEditing(true)} onBlur={() => setEditing(false)} aria-label="路径" spellCheck={false} />
      </label>
      {external && <a className="icon-btn" href={external} target="_blank" rel="noopener" aria-label="在新窗口打开" title="在新窗口打开"><External {...icon} /></a>}
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
    <div className="preview-restart" role="status">
      <span className="preview-restart-dot" aria-hidden="true" />
      <span><b>{name}正在重启</b><span>{restarting.restarts ? `第 ${restarting.restarts} 次 · ` : ""}起来后自动刷新</span></span>
    </div>
  );
}

function DesktopPreview({ station, port, name, external, restarting }: Shown) {
  const [host, setHost] = useState<string | null>(null);
  const [path, setPath] = useState("/");
  const [n, setN] = useState(0);
  useEffect(() => {
    let live = true;
    void window.emberDesktop!.previewHost(station, port).then((h) => { if (live) setHost(h); });
    return () => { live = false; };
  }, [station, port]);
  const go = (to: string) => {
    setPath(to);
    setN((x) => x + 1);
  };
  const reloadDesktop = useCallback(() => setN((x) => x + 1), []);
  return (
    <div className="preview">
      <PreviewBar name={name} at={path} go={go} reload={() => setN((x) => x + 1)} external={external} />
      <div className="preview-stage">
        {host && <iframe key={n} className="preview-frame" title={name} src={`ember-preview://${host}${path}`} />}
        <Restart name={name} restarting={restarting} reload={reloadDesktop} />
      </div>
    </div>
  );
}

function WebPreview({ station, port, name, external, restarting }: Shown) {
  const call = useCall();
  // One frame for as long as this shows: moving about (back, reload, a path) is the frame's own, told to it.
  const [nonce] = useState(() => crypto.randomUUID());
  const [first] = useState("/");
  const [at, setAt] = useState<string | null>(null);
  const [moves, setMoves] = useState({ back: false, forward: false });
  const frame = useRef<HTMLIFrameElement>(null);
  useEffect(() => {
    const bridges: MessagePort[] = [];
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== ORIGIN || event.source !== frame.current?.contentWindow || event.data?.nonce !== nonce) return;
      if (event.data?.type === "ember-preview-at" && typeof event.data.path === "string") {
        setAt(event.data.path);
        setMoves({ back: event.data.back === true, forward: event.data.forward === true });
        return;
      }
      if (event.data?.type !== "ember-preview-ready") return;
      const { port1, port2 } = new MessageChannel();
      bridges.push(port1);
      port1.onmessage = async ({ data }: MessageEvent<Asked>) => {
        try {
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
  const nav = (action: "back" | "forward" | "reload" | "go", path?: string) => frame.current?.contentWindow?.postMessage({ type: "ember-preview-nav", action, path }, ORIGIN);
  const reloadWeb = useCallback(() => frame.current?.contentWindow?.postMessage({ type: "ember-preview-nav", action: "reload" }, ORIGIN), []);
  return (
    <div className="preview">
      <PreviewBar name={name} at={at} go={(path) => nav("go", path)} reload={() => nav("reload")} back={() => nav("back")} forward={() => nav("forward")} canBack={moves.back} canForward={moves.forward} external={external} />
      <div className="preview-stage">
        <iframe ref={frame} className="preview-frame" title={name} src={`${ORIGIN}/_ember/frame?n=${nonce}&path=${encodeURIComponent(first)}`} />
        <Restart name={name} restarting={restarting} reload={reloadWeb} />
      </div>
    </div>
  );
}

/** A web service on a page of its own (its "open on its own"): the whole window with its bar, found by its job. */
export function ServicePage({ station, service }: { station: string; service: string }) {
  const call = useCall();
  const [job, setJob] = useState<{ name: string; port: number | null; state: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => {
    call("station.request", { station, method: "GET", path: `/jobs/${encodeURIComponent(service)}` })
      .then((j) => { const found = j as { name: string; port: number | null; state: string }; setJob(found); document.title = found.name; }, (e: Error) => setError(e.message));
  }, [call, station, service]);
  if (error) return <div className="preview-page preview-missing">找不到这个服务：{error}</div>;
  if (!job) return <div className="preview-page" />;
  if (job.port === null || (job.state !== "running" && job.state !== "exited")) return <div className="preview-page preview-missing">「{job.name}」已经停了。</div>;
  return <div className="preview-page"><StationPreview station={station} port={job.port} name={job.name} service={service} alone /></div>;
}
