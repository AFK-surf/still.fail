// A web service on a station's machine (a dev server an agent started, a
// report it serves), shown in a frame beside the chat. The frame is on the
// preview host (PREVIEW_ORIGIN, see cloud/src/preview.ts), so the service's
// scripts reach nothing of ember's; its service worker hands every request of
// the service to this page, which sends it to the station through the core,
// like any other call, and hands the answer back. No port on the station is
// open to anyone. The desktop app needs none of that: the frame is at
// ember-preview://, which the app serves itself through its core.
import { RotateCw } from "lucide-react";
import { useEffect, useRef, useState } from "react";
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

export function StationPreview({ station, port }: { station: string; port: number }) {
  return window.emberDesktop ? <DesktopPreview station={station} port={port} /> : <WebPreview station={station} port={port} />;
}

/** Where it is and a reload, over the frame. */
function PreviewBar({ port, typed, setTyped, go }: { port: number; typed: string; setTyped: (path: string) => void; go: (path: string) => void }) {
  return (
    <form className="preview-bar" onSubmit={(e) => { e.preventDefault(); go(typed); }}>
      <span className="preview-host">localhost:{port}</span>
      <input className="preview-path" value={typed} onChange={(e) => setTyped(e.target.value)} aria-label="路径" spellCheck={false} />
      <button type="button" className="icon-btn" aria-label="重新载入" title="重新载入" onClick={() => go(typed)}><RotateCw size={14} strokeWidth={1.75} /></button>
    </form>
  );
}

function DesktopPreview({ station, port }: { station: string; port: number }) {
  const [host, setHost] = useState<string | null>(null);
  const [path, setPath] = useState("/");
  const [typed, setTyped] = useState("/");
  const [n, setN] = useState(0);
  useEffect(() => {
    let live = true;
    void window.emberDesktop!.previewHost(station, port).then((h) => { if (live) setHost(h); });
    return () => { live = false; };
  }, [station, port]);
  const go = (to: string) => {
    const next = to.startsWith("/") ? to : `/${to}`;
    setTyped(next);
    setPath(next);
    setN((x) => x + 1);
  };
  return (
    <div className="preview">
      <PreviewBar port={port} typed={typed} setTyped={setTyped} go={go} />
      {host && <iframe key={n} className="preview-frame" title={`localhost:${port}`} src={`ember-preview://${host}${path}`} />}
    </div>
  );
}

function WebPreview({ station, port }: { station: string; port: number }) {
  const call = useCall();
  const [path, setPath] = useState("/");
  const [typed, setTyped] = useState("/");
  // A new one opens the frame anew (a reload): its bridge is made again for it.
  const [nonce, setNonce] = useState(() => crypto.randomUUID());
  const frame = useRef<HTMLIFrameElement>(null);
  useEffect(() => {
    const bridges: MessagePort[] = [];
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== ORIGIN || event.source !== frame.current?.contentWindow) return;
      if (event.data?.type !== "ember-preview-ready" || event.data.nonce !== nonce) return;
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
  const go = (to: string) => {
    const next = to.startsWith("/") ? to : `/${to}`;
    setTyped(next);
    setPath(next);
    setNonce(crypto.randomUUID());
  };
  return (
    <div className="preview">
      <PreviewBar port={port} typed={typed} setTyped={setTyped} go={go} />
      <iframe key={nonce} ref={frame} className="preview-frame" title={`localhost:${port}`}
        src={`${ORIGIN}/_ember/frame?n=${nonce}&path=${encodeURIComponent(path)}`} />
    </div>
  );
}
