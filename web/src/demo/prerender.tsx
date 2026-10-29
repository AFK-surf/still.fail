// The demo's opening frame as HTML, for the site built to HTML (site/prerender.tsx): the desktop's app and the phone's,
// on the same made-up data the browser starts from, where it opens and in the page's language as the page mounts it.
// The page shows the one that fits (site.css.ts), until the demo takes its box over (mount.tsx).
import { renderToString } from "react-dom/server";
import { DemoApp, openOn, type DemoOptions } from "./mount.tsx";
import { withoutDownloads } from "../downloads.ts";
import { forgetTopics } from "../core/react.ts";
import { forgetPrefs } from "../prefs.ts";
import { Picture } from "../picture.ts";

/** `picture`: drawn as a picture that no script takes over (../picture.ts); else as the app's first frame, till it does. */
export function renderDemo(options: DemoOptions, picture = false): { wide: string; phone: string } {
  // As mountDemo: the site has its own 下载 over the demo, which has none in its rail.
  withoutDownloads();
  openOn(options);
  // Each frame as a page of its own: none of the topics read for the one built before (opening elsewhere, in another
  // language), its prefs neither.
  forgetTopics();
  forgetPrefs();
  return {
    wide: renderToString(<Picture.Provider value={picture}><DemoApp phone={false} /></Picture.Provider>),
    phone: renderToString(<Picture.Provider value={picture}><DemoApp phone /></Picture.Provider>),
  };
}
