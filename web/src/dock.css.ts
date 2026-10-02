import { globalStyle, style } from "@vanilla-extract/css";
import { chat } from "./styles/session.css.ts";
import { composerWrap } from "./styles/cloud.css.ts";
import { composerBox } from "./styles/composer.css.ts";
import { vars } from "./styles/tokens.css.ts";
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

// Extend the frame past the message column: its straight edge starts at the column edge.
// Keep 12px clear at the pane edges when a narrow split pane cannot fit the whole curve.
globalStyle(`${composerDock}[data-variant="chat"] ${composerWrap}`, {
  paddingLeft: "12px", paddingRight: "12px",
});
globalStyle(`${composerDock}[data-variant="chat"] ${composerBox}`, {
  vars: { "--composer-curve": "22px" },
  width: "min(100%, calc(100% - 40px + 2 * var(--composer-curve)))",
  maxWidth: "calc(760px + 2 * var(--composer-curve))",
  "@media": { "(max-width: 700px)": { width: "100%" } },
});
globalStyle(`${composerDock}[data-variant="chat"] ${composerBox}[data-multiline]`, {
  vars: { "--composer-curve": `calc(32px * ${vars.cornerScale})` },
});
