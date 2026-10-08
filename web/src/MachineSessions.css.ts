// The new chat page's way to go on with a session the machine kept (MachineSessions.tsx).
import { style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

/** Under the composer, quiet as the words around it until pointed at. */
export const offer = style({
  display: "inline-flex", alignItems: "center", gap: 6, padding: "4px 10px", border: 0, borderRadius: vars.rNav,
  background: "transparent", color: vars.muted, font: "inherit", fontSize: vars.textSecondary, lineHeight: "20px", cursor: "pointer",
  selectors: { "&:hover": { background: vars.hover, color: vars.text } },
});

export const list = style({ listStyle: "none", margin: "0 -12px", padding: 0, display: "grid", gap: 2 });

export const row = style({
  width: "100%", display: "grid", gridTemplateColumns: "auto minmax(0, 1fr) auto", alignItems: "center", gap: 12,
  padding: "10px 12px", border: 0, borderRadius: vars.rOption, background: "transparent", color: vars.text,
  font: "inherit", textAlign: "left", cursor: "pointer",
  selectors: { "&:hover:not(:disabled)": { background: vars.hover }, "&:disabled": { cursor: "default" } },
});

export const main = style({ display: "grid", gap: 2, minWidth: 0 });
export const title = style({ ...ellipsis, fontSize: vars.textBody, fontWeight: 500 });
export const meta = style({ ...ellipsis, fontSize: vars.textLabel, color: vars.muted });
export const already = style({ fontSize: vars.textLabel, color: vars.muted, whiteSpace: "nowrap" });

/** A session looked at before going on with it, its messages spaced as a chat's (session.css.ts chatList). */
// A chat hangs agents' avatars 28px out in its margin (Chat.css.ts msgRow): the preview keeps that room inside the dialog.
export const preview = style({ display: "flex", flexDirection: "column", gap: 28, padding: "0 0 12px 28px" });
export const previewWait = style({ display: "flex", alignItems: "center", gap: 8, minHeight: 120, justifyContent: "center", color: vars.muted, fontSize: vars.textSecondary });
export const previewMore = style({ margin: 0, textAlign: "center", color: vars.muted, fontSize: vars.textLabel });
