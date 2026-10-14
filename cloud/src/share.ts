// The share host (share.still.fail, docs/public-share.md): where someone given a link to a published chat reads it. A
// static Worker of its own (stillfail-share, wrangler.share.jsonc): the page (web/share, `vite build --config
// web/vite.share.config.ts`) and these files beside it, written out by build-static.ts. Like the preview host it is not
// the app's origin, so nothing on it reaches a sign-in; nothing on it keeps anything either. What it shows never passes
// through still.fail: the page asks the cloud for the relays (/v1/relays) and reads the snapshot from the station itself,
// over iroh, through them.
//
// Its headers are the strict part: the page runs its own scripts and iroh's wasm and talks to the cloud and the relays
// alone; nothing on the host is indexed, framed or sent a referrer. A visualization in a message (web/src/Viz.tsx) runs
// its own scripts, which a frame written from the page (srcdoc) could not under the page's policy (it inherits it): it is
// /frame instead, a document of this host with the frames' policy, sandboxed without its origin as srcdoc frames are,
// which writes in what the page posts it (Viz.tsx FrameHost).

/** Where the share page's scripts look: the cloud it asks for the relays, and those relays. */
export type ShareHosts = { cloud: string; relays: string[] };

/** An origin and its WebSocket twin (a relay is dialled over both: HTTPS to time it, a WebSocket to use it). */
function withSockets(url: string): string[] {
  if (!URL.canParse(url)) return [];
  const { origin, protocol, host } = new URL(url);
  return [origin, `${protocol === "http:" ? "ws:" : "wss:"}//${host}`];
}

/** The page's policy: its own scripts (and wasm; pdf.js's worker is one of them), styles (Shiki writes its colours in
 * style attributes), images, video and audio (blob: the files read from the station, shown in the file preview), the
 * cloud and the relays to talk to, /frame to frame. */
export function pageCsp({ cloud, relays }: ShareHosts): string {
  const connect = [...new Set(["'self'", ...withSockets(cloud).slice(0, 1), ...relays.flatMap(withSockets)])];
  return [
    "default-src 'none'",
    "script-src 'self' 'wasm-unsafe-eval'",
    "style-src 'self' 'unsafe-inline'",
    "img-src 'self' blob: data:",
    "media-src blob:",
    "font-src 'self'",
    `connect-src ${connect.join(" ")}`,
    "frame-src 'self'",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
  ].join("; ");
}

/** The frames' policy, as web/src/Viz.tsx's CSP (which the document written in carries too): scripts and styles from
 * a few public CDNs and inline, nothing to talk to. */
const CDNS = "https://cdnjs.cloudflare.com https://esm.sh https://cdn.jsdelivr.net https://unpkg.com";
export const FRAME_CSP = [
  "default-src 'none'",
  `script-src 'unsafe-inline' 'unsafe-eval' ${CDNS}`,
  `style-src 'unsafe-inline' ${CDNS} https://fonts.googleapis.com`,
  `font-src data: ${CDNS} https://fonts.gstatic.com`,
  "img-src data: blob:",
  "media-src data: blob:",
  "connect-src 'none'",
  "base-uri 'none'",
].join("; ");

/** The frame a visualization is drawn in: the first document its page posts it, written in (once: what is written in
 * listens to nothing of this). */
const FRAME = `<!doctype html><meta charset="utf-8"><title>still.fail</title><script>
addEventListener("message", function take(event) {
  if (event.source !== parent || !event.data || typeof event.data.stillfailVizDocument !== "string") return;
  removeEventListener("message", take);
  document.open();
  document.write(event.data.stillfailVizDocument);
  document.close();
});
</script>
`;

/** The files the share host has beside its page: the frame, and the headers (Cloudflare's _headers) of all of it. */
export function shareFiles(hosts: ShareHosts): Record<string, string> {
  return {
    "frame.html": FRAME,
    "_headers": [
      "/*",
      "  X-Robots-Tag: noindex, nofollow",
      "  Referrer-Policy: no-referrer",
      "  X-Content-Type-Options: nosniff",
      "/",
      `  Content-Security-Policy: ${pageCsp(hosts)}`,
      "  Cache-Control: no-cache",
      "/frame",
      `  Content-Security-Policy: ${FRAME_CSP}`,
      "  Cache-Control: no-cache",
      "",
    ].join("\n"),
  };
}
