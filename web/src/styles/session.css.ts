import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./tokens.css.ts";
import { pageBar } from "./sidebar.css.ts";
import { pageBarTitle } from "./conversation.css.ts";

/** The session: a column for the title and the chat, and a full-height tab set on the right. */
export const sessionPage = style({
  flex: "1", minHeight: "0", flexDirection: "column", display: "grid", gridTemplateColumns: "minmax(0, 1fr)",
  gridTemplateRows: "minmax(0, 1fr)",
  // The tab set slides in from past the right edge and back out there.
  overflowX: "clip",
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
        // The chat keeps 360px however wide the tab set is dragged: the tab set gives way first. Side by side, the chat
        // and the tab set are two panes laid into the window, 8px apart (shell.css.ts main holds them).
        "&[data-panel=\"true\"]": {
          columnGap: "8px",
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
  // One-line expanded composer: text, padding, toolbar, gap and dock margins.
  vars: { "--composer-room": `max(var(--composer-height, 0px), calc(${vars.textBody} * 1.5 + 102px))` },
});
/** Back to the newest, when scrolled up: a round button over the pane's bottom right, above the composer. */
export const chatPane = style({
  position: "relative", flex: "1", minHeight: "0", display: "flex", flexDirection: "column",
  selectors: {
    // Where the messages meet the bar above, they fade out rather than being cut (a scroll edge, not a line); at the
    // list's top there is nothing under it yet. The avatars that stay at the top lie over it (Chat.css.ts).
    "&::before": {
      content: "\"\"", position: "absolute", top: "0", left: "0", right: "0", height: "20px", zIndex: "1",
      background: `linear-gradient(${vars.canvas}, color-mix(in srgb, ${vars.canvas} 0%, transparent))`, pointerEvents: "none",
    },
  },
});
/** These panes keep their distance from the bottom themselves; the browser's top anchoring would fight it. */
export const chatList = style({
  flex: "1", minHeight: "0", overflowY: "auto", padding: "24px 32px", display: "flex", flexDirection: "column",
  gap: "28px", position: "relative", overflowAnchor: "none",
  selectors: {
    // What floats over its foot: its scrollbar (scrollbars.ts) ends a little above the composer, not under it.
    [`${chat}[data-under-composer] &`]: {
      // And of what waits to be decided over it (Asks.tsx: its height and gap, while there is something).
      // Reserve the one-line expanded composer (text + padding, toolbar, gap and dock margins) even as a capsule.
      paddingBottom: "calc(24px + var(--composer-room) + var(--asks-height, 0px))",
      scrollPaddingBottom: "calc(8px + var(--composer-room) + var(--asks-height, 0px))",
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
/** Side by side (the side panel open on a wide window), each of the two is a pane of its own, with its hairline. */
globalStyle(`${sessionPage}[data-panel="true"] > *`, {
  "@media": {
    "(min-width: 1101px)": {
      borderRadius: "12px", background: vars.canvas, overflow: "hidden",
      boxShadow: `${vars.paneShadow}, inset 0 0 0 .5px ${vars.ring}`,
    },
  },
});
