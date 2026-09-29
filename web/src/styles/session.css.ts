import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";
import { pageBar } from "./sidebar.css.ts";
import { pageBarTitle } from "./conversation.css.ts";

/** The session: a column for the title and the chat, and a full-height tab set on the right. */
export const sessionPage = style({
  flex: "1", minHeight: "0", flexDirection: "column", display: "grid", gridTemplateColumns: "minmax(0, 1fr)",
  gridTemplateRows: "minmax(0, 1fr)",
  selectors: {
    // The tab set's width is a whole number of pixels (38% of the page rarely is), so what is centred in it stays sharp.
    "&[data-panel=\"true\"]": { gridTemplateColumns: ["minmax(0, 1fr) minmax(360px, 38%)", "minmax(0, 1fr) minmax(360px, round(down, 38%, 1px))"] },
  },
  "@media": {
    "(max-width: 1100px)": {
      selectors: {
        "&[data-panel=\"true\"]": { gridTemplateColumns: "minmax(0, 1fr)" },
      },
    },
    "(min-width: 1101px)": {
      selectors: {
        // The chat keeps 360px however wide the tab set is dragged: the tab set gives way first.
        "&[data-panel=\"true\"]": {
          gridTemplateColumns: [
            "minmax(360px, 1fr) minmax(0, var(--panel-w, max(360px, 38%)))",
            "minmax(360px, 1fr) minmax(0, var(--panel-w, max(360px, round(down, 38%, 1px))))",
          ],
        },
      },
    },
  },
});
export const chat = style({
  position: "relative", minWidth: "0", minHeight: "0", display: "flex", flexDirection: "column",
  background: vars.canvas,
});
/** Back to the newest, when scrolled up: a round button over the pane's bottom right, above the composer. */
export const chatPane = style({
  position: "relative", flex: "1", minHeight: "0", display: "flex", flexDirection: "column",
});
/** These panes keep their distance from the bottom themselves; the browser's top anchoring would fight it. */
export const chatList = style({
  flex: "1", minHeight: "0", overflowY: "auto", padding: "24px 32px", display: "flex", flexDirection: "column",
  gap: "28px", position: "relative", overflowAnchor: "none",
  selectors: {
    // What floats over its foot: its scrollbar (scrollbars.ts) ends a little above the composer, not under it.
    [`${chat}[data-under-composer] &`]: {
      paddingBottom: "calc(24px + var(--composer-height))", scrollPaddingBottom: "calc(8px + var(--composer-height))",
    },
  },
  // Making way for the small web services in the corner (Previews.tsx, which moves it), with its composer: what it
  // shows, not its scrollbar, which stays at the window's edge.
  paddingRight: "calc(32px + var(--avoid-previews, 0px))",
  "@media": {
    "(max-width: 700px)": {
      padding: "16px",
      paddingRight: "calc(16px + var(--avoid-previews, 0px))",
    },
  },
});
globalStyle(`${sessionPage} ${pageBar}`, { gridTemplateColumns: "minmax(0, 1fr) auto" });
/** Not clipped: an agent mark's state dot sits partly outside it (the title ellipsises by itself). */
globalStyle(`${sessionPage} ${pageBarTitle}`, {
  gridColumn: "1", justifySelf: "stretch", gap: "10px", minWidth: "0", paddingLeft: "8px",
});
/** A long title gives way first: it shrinks to an ellipsis, the people and agents after it stay whole. */
globalStyle(`${sessionPage} ${pageBarTitle} h1`, { maxWidth: "none", minWidth: "0", flex: "0 1 auto" });
globalStyle(`${sessionPage} ${pageBar}`, {
  "@media": {
    "(max-width: 1100px)": {
      gridTemplateColumns: "auto minmax(0, 1fr) auto",
    },
  },
});
globalStyle(`${sessionPage} ${pageBarTitle}`, {
  "@media": {
    "(max-width: 1100px)": {
      gridColumn: "2", paddingLeft: "0",
    },
  },
});
