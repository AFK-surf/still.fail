// The official site's page as HTML, for the built index.html (web/site-prerender.mjs): what search engines and link
// previews read, and what shows before the scripts run — the demo too, at its opening frame.
import { renderToString } from "react-dom/server";
import { renderDemo } from "../demo/prerender.tsx";
import { frameHtml, Site } from "./Site.tsx";
import { featurePage, WORDS, type SiteLang } from "./words.ts";

/** The page in a language: Chinese at /, English at /en/. */
export function render(lang: SiteLang): string {
  return renderToString(<Site demo={{ chat: renderDemo({ lang }), stations: renderDemo({ start: "stations", lang }) }} lang={lang} />);
}

/** The phone beside the computer (site/phone.html, en/phone.html): its app's opening frame, on the stations' page. */
export function renderPhone(lang: SiteLang): string {
  return frameHtml({ phone: renderDemo({ start: "stations", lang }).phone });
}

/** The pages of the phones showing what it is for (featurePage), each the phone's app's opening frame at its page. */
export function renderFeatures(lang: SiteLang): { file: string; html: string }[] {
  return [...new Set(WORDS[lang].scenes.map((s) => s.at))].flatMap((at) => {
    const page = at ? featurePage(at) : null;
    return page ? [{ file: `${page}.html`, html: frameHtml({ phone: renderDemo({ at, lang }).phone }) }] : [];
  });
}
