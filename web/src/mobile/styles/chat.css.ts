import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";

export const mChat = style({ position: "absolute", inset: "0", background: "var(--m-bg)" });
/** Where the list's first message stands: under the bar (a chat read the first time, its bones there too: ../Chat.css.ts). */
export const mListTop = "calc(var(--m-top) + 68px)";
/** The chat's messages, drawn as the wide screen draws them (../../Chat.tsx), a little closer together. */
export const mMessages = style({
  position: "absolute", inset: "0", display: "flex", flexDirection: "column", gap: "var(--list-gap)", overflowY: "auto",
  // Stop at the edge: native rubber-banding otherwise fights the virtual list's clamped scroll position.
  overscrollBehavior: "none", overflowAnchor: "none",
  // Its end clear of the composer, and of the bell to what waits to be decided over it while there is something
  // (../../Chat.tsx askClear).
  padding: `${mListTop} var(--list-gutter) calc(var(--m-composer-room) + var(--ask-clear, 0px) + 10px)`,
  scrollPaddingTop: "calc(var(--m-top) + 60px)",
  // Its sides the screen's margin, which a message's table scrolls into (../../Chat.css.ts).
  vars: { "--list-gap": "20px", "--list-gutter": "14px" },
});
/** The list drawn where it stands, not over the page: a chat's page while it is read, its messages in their bones under the
 * room its bar takes (../Chat.tsx ChatWaiting). */
export const mMessagesHeld = style({ position: "static", overflowY: "visible", paddingTop: "0" });
export const mWaiting = style({ display: "inline-flex", alignItems: "center", gap: "5px" });
export const mPlain = style({
  margin: "0", fontSize: vars.textBody, lineHeight: "23px", whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
/** What a job told its agent, opened: program output, its columns kept. */
export const mOutput = style({
  margin: "0", fontFamily: vars.fontMono, fontSize: vars.textCaption, lineHeight: "1.55", whiteSpace: "pre-wrap", overflowWrap: "anywhere",
});
