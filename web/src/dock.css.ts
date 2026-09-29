import { globalStyle, style } from "@vanilla-extract/css";
import { chat } from "./styles/session.css.ts";
import { composerWrap } from "./styles/cloud.css.ts";
import { composerBox } from "./styles/composer.css.ts";
import { newChatInner } from "./NewChat.css.ts";

/** The chat pages' one composer (dock.tsx) sits over its place on the page, laid out for a new chat or a chat. */
export const composerSlot = style({
  flex: "none",
  selectors: {
    [`${newChatInner} > &`]: { justifySelf: "stretch" },
    // A chat's list runs on under its composer, which floats over it frosted, as the phone's does: what scrolls under it
    // shows through, blurred. The list's foot leaves the composer's height free, so its last message still ends above it.
    [`${chat}[data-under-composer] > &`]: {
      position: "absolute", left: "0", bottom: "0", pointerEvents: "none",
      // Clear of the small web services in the corner, with the rest of the chat (session.css.ts chat).
      right: "var(--avoid-previews, 0px)",
    },
    [`${chat}[data-under-composer][data-avoid-previews=settled] > &`]: { transition: "right 280ms cubic-bezier(.2, .8, .2, 1)" },
  },
});
export const composerDock = style({
  position: "absolute", zIndex: "3",
  selectors: {
    // Named only while a page changes (transitionTo): named, it would be a backdrop root and its glass would blur nothing.
    ":root[data-transitioning] &": { viewTransitionName: "dock" },
  },
});
globalStyle(`${composerDock} ${composerWrap}`, { borderTop: "0" });
globalStyle(`${composerDock}[data-variant="new"] ${composerWrap}`, { padding: "0", textAlign: "left" });
globalStyle(`${composerDock}[data-variant="new"] ${composerBox}`, { minHeight: "96px" });
globalStyle(`${composerDock}[data-switching] ${composerBox}`, { transition: "none" });
globalStyle(`${composerDock}[data-variant="chat"] ${composerWrap}`, { pointerEvents: "none" });
globalStyle(`${composerDock}[data-variant="chat"] ${composerWrap} > *`, { pointerEvents: "auto" });
