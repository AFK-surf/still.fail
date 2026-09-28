// A web service on a station's machine (a dev server an agent started, a
// report it serves), shown in a frame beside the chat. The frame is on the
// preview host (PREVIEW_ORIGIN, see cloud/src/preview.ts), so the service's
// scripts reach nothing of ember's; its service worker hands every request of
// the service to this page, which sends it to the station through the core,
// like any other call, and hands the answer back. No port on the station is
// open to anyone. The desktop app needs none of that: the frame is at
// ember-preview://, which the app serves itself through its core.
import { ArrowLeft, ArrowRight, External, Refresh } from "./icons.tsx";
import { useEffect, useRef, useState } from "react";
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

/** A service beside a chat, or on a page of its own (`alone`): the bar has no "open on its own" there. */
export function StationPreview({ station, port, alone = false }: { station: string; port: number; alone?: boolean }) {
  // Its page of its own, at the station's pages' place (a new window or tab: the browser's).
  const own = useHref(useLink()(`/preview/${port}`));
  const external = alone ? undefined : own;
  return window.emberDesktop ? <DesktopPreview station={station} port={port} external={external} /> : <WebPreview station={station} port={port} external={external} />;
}

interface Bar {
  port: number;
  /** Where the service is now, as its frame says (null: not known). */
  at: string | null;
  go(path: string): void;
  reload(): void;
  /** Absent where the frame's history cannot be reached (the desktop app's frame). */
  back?(): void;
  forward?(): void;
  external?: string | undefined;
}

/** Back, forward, reload, where it is (typed to go elsewhere), and its page of its own: over the frame. */
function PreviewBar({ port, at, go, reload, back, forward, external }: Bar) {
  const [typed, setTyped] = useState(at ?? "/");
  const [editing, setEditing] = useState(false);
  // Where it went is what the bar says, unless someone is typing there.
  useEffect(() => { if (at !== null && !editing) setTyped(at); }, [at, editing]);
  const icon = { size: 14, strokeWidth: 1.75 };
  return (
    <form className="preview-bar" onSubmit={(e) => { e.preventDefault(); go(typed.startsWith("/") ? typed : `/${typed}`); (document.activeElement as HTMLElement | null)?.blur(); }}>
      {back && <button type="button" className="icon-btn" aria-label="后退" title="后退" onClick={back}><ArrowLeft {...icon} /></button>}
      {forward && <button type="button" className="icon-btn" aria-label="前进" title="前进" onClick={forward}><ArrowRight {...icon} /></button>}
      <button type="button" className="icon-btn" aria-label="刷新" title="刷新" onClick={reload}><Refresh {...icon} /></button>
      <label className="preview-address">
        <span className="preview-host">localhost:{port}</span>
        <input className="preview-path" value={typed} onChange={(e) => setTyped(e.target.value)} onFocus={() => setEditing(true)} onBlur={() => setEditing(false)} aria-label="路径" spellCheck={false} />
      </label>
      {external && <a className="icon-btn" href={external} target="_blank" rel="noopener" aria-label="在新窗口打开" title="在新窗口打开"><External {...icon} /></a>}
    </form>
  );
}

function DesktopPreview({ station, port, external }: { station: string; port: number; external?: string | undefined }) {
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
  return (
    <div className="preview">
      <PreviewBar port={port} at={path} go={go} reload={() => setN((x) => x + 1)} external={external} />
      {host && <iframe key={n} className="preview-frame" title={`localhost:${port}`} src={`ember-preview://${host}${path}`} />}
    </div>
  );
}

function WebPreview({ station, port, external }: { station: string; port: number; external?: string | undefined }) {
  const call = useCall();
  // One frame for as long as this shows: moving about (back, reload, a path) is the frame's own, told to it.
  const [nonce] = useState(() => crypto.randomUUID());
  const [first] = useState("/");
  const [at, setAt] = useState<string | null>(null);
  const frame = useRef<HTMLIFrameElement>(null);
  useEffect(() => {
    const bridges: MessagePort[] = [];
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== ORIGIN || event.source !== frame.current?.contentWindow || event.data?.nonce !== nonce) return;
      if (event.data?.type === "ember-preview-at" && typeof event.data.path === "string") {
        setAt(event.data.path);
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
  return (
    <div className="preview">
      <PreviewBar port={port} at={at} go={(path) => nav("go", path)} reload={() => nav("reload")} back={() => nav("back")} forward={() => nav("forward")} external={external} />
      <iframe ref={frame} className="preview-frame" title={`localhost:${port}`} src={`${ORIGIN}/_ember/frame?n=${nonce}&path=${encodeURIComponent(first)}`} />
    </div>
  );
}

/** A service on a page of its own: the whole window, with its bar (opened from a preview's "open on its own"). */
export function PreviewPage({ station, port }: { station: string; port: number }) {
  return <div className="preview-page"><StationPreview station={station} port={port} alone /></div>;
}
