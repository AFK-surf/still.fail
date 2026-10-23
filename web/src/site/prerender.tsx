// The official site's page as HTML, for the built index.html (web/site-prerender.mjs): what search engines and link
// previews read, and what shows before the scripts run — the demo too, at its opening frame.
import { renderToString } from "react-dom/server";
import { renderDemo } from "../demo/prerender.tsx";
import { Site } from "./Site.tsx";
import type { SiteLang } from "./words.ts";

/** The page in a language: Chinese at /, English at /en/. */
export function render(lang: SiteLang): string {
  return renderToString(<Site demo={renderDemo()} lang={lang} />);
}
