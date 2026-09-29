import { globalStyle, keyframes, style } from "@vanilla-extract/css";
import { mComposerField } from "./Chat.css.ts";
import { mComposerCapsule } from "./ChatHost.css.ts";
import { mMessages } from "./styles/chat.css.ts";
import { msgMine } from "../styles/chat.css.ts";

export const mNewchatScreen = style({ paddingBottom: "var(--m-bottom)", boxSizing: "border-box" });
export const mNewBody = style({
  flex: "1", minHeight: "0", overflowY: "auto", display: "flex", flexDirection: "column", alignItems: "center",
  gap: "6px", padding: "30px 30px 10px", textAlign: "center",
});
export const mNewProblem = style({
  marginTop: "6px !important", fontSize: "13px !important", color: "var(--m-red)",
  selectors: {
    "&[data-wait]": { color: "var(--m-muted)" },
  },
});
export const mNewSpent = style({
  margin: "0 12px", padding: "8px 12px", borderRadius: "12px",
  background: "color-mix(in srgb, var(--m-warn) 12%, transparent)", fontSize: "13px",
});
export const mNewBottom = style({
  display: "flex", flexDirection: "column", gap: "4px", flex: "none", padding: "8px 10px 0",
});
export const mChoosers = style({
  display: "flex", gap: "6px", overflowX: "auto", padding: "6px 2px", scrollbarWidth: "none",
  selectors: {
    "&::-webkit-scrollbar": { display: "none" },
  },
});
export const mChooser = style({
  display: "inline-flex", alignItems: "center", gap: "6px", flex: "none", height: "30px", boxSizing: "border-box",
  padding: "0 11px", borderRadius: "15px", fontSize: "13px !important", whiteSpace: "nowrap", cursor: "pointer",
});
globalStyle(`${mNewBody} h2`, { margin: "6px 0 0", fontSize: "22px", fontWeight: "700" });
globalStyle(`${mNewBody} > p`, { fontSize: "14px" });

// A new chat becoming its chat (NewChat.tsx toMadeChat): only what leaves is pictured; the rest is the new page at once.
// The pictures hang off the document, not the phone's root: its easing variables are not theirs, so written out.
const made = ":root[data-made]";
const sceneOut = keyframes({ to: { opacity: 0, transform: "translateY(-32px) scale(.96)" } });
const choosersOut = keyframes({ to: { opacity: 0, transform: "translateY(44px)" } });
globalStyle(`${made}::view-transition-old(root)`, { display: "none" });
globalStyle(`${made}::view-transition-new(root)`, { animation: "none" });
// The composer stays on the page, not pictured apart: what arrives passes over it.
globalStyle(`${made} ${mComposerCapsule}`, { viewTransitionName: "none" });
// Out of the way before what comes passes where they were.
globalStyle(`${made}::view-transition-old(m-made-scene)`, { animation: `${sceneOut} 160ms cubic-bezier(.3, 0, .5, 1) both` });
globalStyle(`${made}::view-transition-old(m-made-choosers)`, { animation: `${choosersOut} 100ms cubic-bezier(.3, 0, .5, 1) both` });
// The choices sink into the composer's top edge (their own box's foot), not over it.
globalStyle(`${made}::view-transition-group(m-made-choosers)`, { overflow: "clip" });
// The message sent is drawn on its way by a copy of it; the composer's hint waits until the words have left it.
globalStyle(`${made} ${mMessages}:not([data-ghost]) ${msgMine}`, { visibility: "hidden" });
globalStyle(`${made} ${mComposerField}::placeholder`, { color: "transparent" });
