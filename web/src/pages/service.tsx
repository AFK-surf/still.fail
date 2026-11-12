// A web service on a station's machine on a page of its own (its "open on its own"): the whole window its frame, on the
// preview host (cloud/src/preview.ts), whose requests and WebSockets go to the station through the core
// (previewBridge.ts), found by its job (the `job` topic), known by its name, never its port. Stopped or not found, it
// says so in its place.
import { render } from "preact";
import { useEffect, useRef, useState } from "preact/hooks";
import { I18nRoot, t } from "@stillfail/ui/i18n.ts";
import { core, useTopic } from "../core/react.ts";
import type { Job } from "../core/shapes.ts";
import { bridge, fromPreview, toPreview } from "../previewBridge.ts";
import { accounts, signInHere, takeSignedIn } from "./core.ts";
import * as css from "./service.css.ts";
import { PREVIEW_ORIGIN } from "../channel.ts";

const ORIGIN = PREVIEW_ORIGIN;

function Frame({ station, port, name }: { station: string; port: number; name: string }) {
  const frame = useRef<HTMLIFrameElement>(null);
  const [nonce] = useState(() => crypto.randomUUID());
  // The frame's requests, handed here once it is ready: on to the station. A frame that takes answers as they come says
  // so, and is told this page gives them.
  useEffect(() => {
    const bridges: (() => void)[] = [];
    const onMessage = (event: MessageEvent) => {
      if (event.origin !== ORIGIN || event.source !== frame.current?.contentWindow || event.data?.nonce !== nonce) return;
      if (!fromPreview(event.data, "ready")) return;
      const { port1, port2 } = new MessageChannel();
      const streams = event.data.streams === true;
      bridges.push(bridge(port1, { call: (n, p, b, on, signal) => core().callBytes(n, p, b, on, signal), station, service: port, streams }));
      frame.current?.contentWindow?.postMessage({ type: toPreview("port"), streams }, ORIGIN, [port2]);
    };
    addEventListener("message", onMessage);
    return () => {
      removeEventListener("message", onMessage);
      for (const stop of bridges) stop();
    };
  }, [nonce, station, port]);
  return <iframe ref={frame} className={css.frame} title={name} src={`${ORIGIN}/_stillfail/frame?n=${nonce}&path=${encodeURIComponent("/")}`} />;
}

function ServicePage({ station, service }: { station: string; service: string }) {
  const found = useTopic<Job>({ topic: "job", station, id: service });
  const job = found.value ?? null;
  useEffect(() => { if (job) document.title = job.name; }, [job?.name]);
  if (!job && found.error) return <p className={css.missing}>{t("web-main.preview.noService", { error: found.error.message })}</p>;
  if (!job) return null;
  if (!job.open || job.port == null) return <p className={css.missing}>{t("web-main.preview.stopped", { name: job.name })}</p>;
  return <Frame station={station} port={job.port} name={job.name} />;
}

export async function show(root: HTMLElement, station: string, service: string): Promise<void> {
  await takeSignedIn();
  if ((await accounts()).length === 0) return location.replace(signInHere());
  // (in place of the splash index.html paints first)
  root.replaceChildren();
  render(<I18nRoot><ServicePage station={station} service={service} /></I18nRoot>, root);
}
