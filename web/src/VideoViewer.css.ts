// A picture or a video (@stillfail/ui's viewer/media.css.ts) in the file preview (FilePreview.tsx): just after it in
// the cascade (styles/index.ts).
import { globalStyle } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { vv, vvBar } from "@stillfail/ui/viewer/media.css.ts";
import { fp, fpHead, fpZoom, glass } from "./FilePreview.css.ts";

/** The picture takes the whole page, in the theme's colours; the page's bar (its name, download, close) shows with the player's. */
globalStyle(`${fp}:has(${vv})`, { background: vars.canvas, color: vars.text });
globalStyle(`${fp}:has(${vv}) ${fpHead}`, glass);
globalStyle(`${fp}:has(${vvBar}[data-awake]) ${fpHead}`, { opacity: "1", transitionDuration: "120ms" });
/** On a phone, pinching zooms: its buttons would crowd the frame's facts out. */
globalStyle(`${vv} ${fpZoom}`, { "@media": { "(max-width: 640px)": { display: "none" } } });
