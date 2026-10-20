// The demo's opening frame as HTML, for the site built to HTML (site/prerender.tsx): the desktop's app and the phone's,
// on the same made-up data the browser starts from. The page shows the one that fits (site.css.ts), until the demo
// takes its box over (mount.tsx).
import { renderToString } from "react-dom/server";
import { DemoApp } from "./mount.tsx";
import { withoutDownloads } from "../downloads.ts";

export function renderDemo(): { wide: string; phone: string } {
  // As mountDemo: the site has its own 下载 over the demo, which has none in its rail.
  withoutDownloads();
  return { wide: renderToString(<DemoApp phone={false} />), phone: renderToString(<DemoApp phone />) };
}
