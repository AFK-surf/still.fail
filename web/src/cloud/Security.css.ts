import { style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { cardGround } from "../styles/pages.css.ts";

/** The lock's state, first in its card: a dot and words. */
export const dot = style({
  width: "7px", height: "7px", borderRadius: "50%", flex: "none", background: vars.lineStrong,
  selectors: { '&[data-on="true"]': { background: vars.online }, '&[data-tone="amber"]': { background: vars.amber } },
});
/** The state, first in its card: its words alone, on the card's line (no dot before them: docs/ui-panels.md 页面卡片). */
export const state = style({ display: "flex", alignItems: "center", gap: "8px", fontSize: vars.textBody, fontWeight: "500" });
export const stateMeta = style({ fontWeight: "400", color: vars.muted, fontSize: vars.textUi });
/** What it changes, a line each with its icon. */
export const points = style({ display: "grid", gap: "10px" });
export const point = style({ display: "grid", gridTemplateColumns: "20px 1fr", gap: "8px", fontSize: vars.textBody, lineHeight: vars.leadingBody, color: vars.text });
export const pointIcon = style({ color: vars.muted, marginTop: "2px" });
export const sub = style({ display: "block", margin: "0", color: vars.muted });
export const actions = style({ display: "flex", alignItems: "center", gap: "10px", flexWrap: "wrap" });
export const note = style({ margin: "0", fontSize: vars.textMeta, color: vars.muted });
/** A row of a list in a card: a person, a device, a station. */
export const row = style({ display: "flex", alignItems: "center", gap: "12px", fontSize: vars.textUi, minHeight: "30px" });
export const rowText = style({ flex: "1", minWidth: "0", display: "flex", alignItems: "baseline", gap: "6px", flexWrap: "wrap" });
export const rowName = style({ fontWeight: "500", color: vars.text });
export const rowMeta = style({ color: vars.muted, fontSize: vars.textMeta });
export const rows = style({ display: "grid", gap: "12px" });
export const devices = style({ display: "grid", gap: "8px", paddingLeft: "42px" });
export const deviceIcon = style({ color: vars.muted, flex: "none" });
export const warn = style({ color: vars.amber, fontSize: vars.textMeta });
/** A short code, as the device shows it. */
export const code = style({
  fontFamily: vars.fontMono, fontWeight: "600", letterSpacing: "1px", padding: "3px 9px", borderRadius: "8px",
  background: `color-mix(in oklab, ${vars.text} 6%, transparent)`, fontSize: vars.textBody,
});
export const bigCode = style({ fontFamily: vars.fontMono, fontSize: vars.textDisplay, lineHeight: "1.3", letterSpacing: "6px", fontWeight: "600", textAlign: "center", margin: "6px 0" });
export const count = style({ fontSize: vars.textMeta, padding: "0 7px", borderRadius: "10px", background: vars.accentBg, color: vars.accentText, fontWeight: "500" });
/** The one-line notice at the top of the settings pages while the lock is off (the owner's). */
export const banner = style({
  display: "flex", alignItems: "center", gap: "10px", fontSize: vars.textUi, padding: "8px 8px 8px 14px",
  borderRadius: `calc(14px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: cardGround, marginBottom: "22px", color: vars.text,
});
export const bannerLink = style({ color: vars.accentText, textDecoration: "none" });
export const bannerClose = style({ marginLeft: "auto" });
/** The draft's sticky foot: what happens, and the button. */
export const foot = style({
  position: "sticky", bottom: "0", display: "flex", alignItems: "center", justifyContent: "flex-end", gap: "10px", padding: "14px 0",
  background: `linear-gradient(transparent, ${vars.canvas} 30%)`,
});
export const footNote = style({ marginRight: "auto", fontSize: vars.textMeta, color: vars.muted });
export const check = style({ width: "18px", height: "18px", accentColor: vars.primary, flex: "none", margin: "0" });
/** The page a device waiting to be confirmed shows instead of the workspace. */
export const waiting = style({ maxWidth: "460px", margin: "110px auto 0", padding: "0 24px", textAlign: "center", display: "grid", gap: "14px", justifyItems: "center" });
export const waitingTitle = style({ margin: "0", fontSize: vars.textHeading, lineHeight: vars.leadingHeading, fontWeight: "600" });
export const waitingLead = style({ margin: "0", color: vars.muted, fontSize: vars.textBody, lineHeight: vars.leadingBody });
export const waitingNote = style({ display: "flex", alignItems: "center", gap: "8px", color: vars.muted, fontSize: vars.textMeta });
/** The code shown on a trusted device, typed here: as large as the code is shown there. */
export const codeInput = style({ width: "200px", textAlign: "center", fontFamily: vars.fontMono, fontSize: vars.textTitle, letterSpacing: "4px" });
/** Its request did not go: why, in red. */
export const waitingFailed = style({ color: vars.red, fontSize: vars.textMeta, lineHeight: vars.leadingBody });
/** The workspaces a waiting device asks to be let into, first in its prompt: their names, as large as the title's words. */
export const places = style({ display: "flex", alignItems: "center", gap: "6px 14px", flexWrap: "wrap", margin: "2px 0 4px" });
export const placesLabel = style({ color: vars.muted, fontSize: vars.textUi });
export const place = style({ display: "inline-flex", alignItems: "center", gap: "6px", fontSize: vars.textBody, fontWeight: "600", color: vars.text });
/** The state's card, first on the page: as far from what follows as a section is. */
export const lead = style({ marginBottom: "28px" });
