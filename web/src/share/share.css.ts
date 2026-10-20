// The share page (Share.tsx): a published chat as the chat draws it, its messages in one column down the page, which
// scrolls as a document does (the app's never does: its panes do). Its messages' own styles are the chat's.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { msgAvatar } from "../styles/chat.css.ts";
import { msgRow } from "../Chat.css.ts";

const phone = "(max-width: 700px)";

globalStyle("html, body", { height: "auto", overflow: "visible", overscrollBehavior: "auto" });
/** The phone's type, a size up from the wide screen's, as the app's narrow screen has it (mobile/styles/root.css.ts). */
globalStyle(":root", {
  "@media": {
    [phone]: {
      vars: { [vars.textCaption]: "12px", [vars.textMeta]: "13px", [vars.textUi]: "15px", [vars.textBody]: "15px", [vars.textTitle]: "16px" },
    },
  },
});

/** The column: the chat's width, its avatars out in the margin on a wide screen as the chat has them (Chat.css.ts). */
export const page = style({
  maxWidth: "820px", margin: "0 auto", padding: "56px 40px 40px",
  "@media": { [phone]: { padding: "28px 16px 32px" } },
});
export const head = style({ display: "grid", gap: "6px", marginBottom: "36px", "@media": { [phone]: { marginBottom: "28px" } } });
export const title = style({ margin: "0", fontSize: vars.textHeading, lineHeight: vars.leadingHeading, fontWeight: "600" });
export const meta = style({ margin: "0", fontSize: vars.textMeta, lineHeight: vars.leadingMeta, color: vars.muted });
/** Messages a gap apart, as the chat's list has them. */
export const list = style({ display: "grid", gap: "28px", vars: { "--list-gap": "28px" }, "@media": { [phone]: { gap: "24px", vars: { "--list-gap": "24px" } } } });
// The page scrolls, not a pane: a long message's avatar is held just under its top.
globalStyle(`${list} ${msgRow} > ${msgAvatar}`, { top: "12px" });

export const foot = style({
  display: "flex", justifyContent: "center", marginTop: "56px", fontSize: vars.textMeta, lineHeight: vars.leadingMeta,
});
export const footLink = style({
  display: "inline-flex", alignItems: "center", gap: "6px", color: vars.muted,
  selectors: { "&:hover": { color: vars.text } },
});

/** One state of the page in place of the chat (connecting, the station offline, the link gone…): a picture and a line. */
export const state = style({
  minHeight: "100dvh", display: "grid", placeContent: "center", justifyItems: "center", gap: "14px", padding: "24px",
  textAlign: "center", color: vars.muted, fontSize: vars.textUi, lineHeight: vars.leadingUi,
});
export const stateLine = style({ margin: "0", display: "inline-flex", alignItems: "center", gap: "8px", maxWidth: "360px" });
