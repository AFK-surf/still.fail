// The official site's page as HTML, for the built index.html (web/site-prerender.mjs): what search engines and link
// previews read, and what shows before the scripts run — the demo too, at its opening frame.
import { renderToString } from "react-dom/server";
import { renderDemo } from "../demo/prerender.tsx";
import { frameHtml, Site } from "./Site.tsx";
import type { SiteLang } from "./words.ts";

/** The page in a language: Chinese at /, English at /en/. */
export function render(lang: SiteLang): string {
  return renderToString(<Site demo={{ chat: renderDemo({ lang }), stations: renderDemo({ start: "stations", lang }) }} lang={lang} />);
}

/** The phone beside the computer (site/phone.html, en/phone.html): its app's opening frame, on the stations' page. */
export function renderPhone(lang: SiteLang): string {
  return frameHtml({ phone: renderDemo({ start: "stations", lang }).phone });
}
