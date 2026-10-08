import { style } from "@vanilla-extract/css";

/** A new chat and a chat: one page, what is above and one composer at the foot (ChatHost.tsx; --m-bottom is its height). */
export const mChatHost = style({
  position: "absolute", inset: "0",
  vars: { "--m-bottom": "72px", "--m-composer-room": "max(var(--m-bottom), calc(110px + var(--m-foot)))" },
});
/** The composer: a capsule floating over the list, which runs on around it. */
export const mComposer = style({
  position: "absolute", left: "0", right: "0", bottom: "0", zIndex: "3",
  padding: "8px 10px calc(10px + var(--m-foot))",
  "@media": {
    // Wider (app.tsx WIDE): beside the latest chats' button, which is level with it (app.css.ts mRecentButton: 10 + 52 + 10).
    "(min-width: 680px)": { paddingLeft: "72px" },
  },
});
/** The same composer, in the decisions page's footer rather than over a chat (wider, clear of the latest chats' button too). */
export const mInlineComposer = style({
  position: "relative", padding: "8px 0 0",
  "@media": {
    "(min-width: 680px)": { paddingLeft: "62px" },
  },
});
export const mHostComposer = style({
  selectors: {
    [`${mComposer}&`]: { zIndex: "6" },
  },
});
export const mComposerCapsule = style({
  viewTransitionName: "composer", display: "flex", flexDirection: "column", gap: "8px", padding: "8px",
  borderRadius: "26px",
});
export const mComposerOffline = style({ margin: "0", padding: "2px 8px", fontSize: "13px", color: "var(--m-muted)" });
export const mComposerError = style({ margin: "0", padding: "0 6px", fontSize: "12px" });
