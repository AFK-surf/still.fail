import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { muted } from "../styles/shell.css.ts";
import { callout } from "../styles/additions.css.ts";

export const onboardingLead = style({
  textWrap: "balance", wordBreak: "keep-all", overflowWrap: "anywhere", margin: "0 0 24px", color: vars.muted,
  lineHeight: "1.6",
});
export const threadItem = style({ display: "grid", gap: "1px" });
export const accountTrigger = style({
  display: "flex", alignItems: "center", gap: "10px", width: "100%", padding: "8px 10px", border: "0",
  borderRadius: vars.rNav, background: "none", color: vars.text, textAlign: "left", cursor: "pointer",
  cornerShape: vars.cornerShape,
  selectors: {
    "&:hover": { background: vars.hover },
    "&[data-state=\"open\"]": { background: vars.hover },
  },
});
export const accountText = style({ display: "grid", minWidth: "0", lineHeight: "1.3" });
export const accountName = style({
  fontSize: vars.textSm, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const accountMenu = style({});
/** A workspace in the menu: its name and account on the left, its stations and people on the right, each by one of those lines. */
export const menuWorkspace = style({
  flex: "1", minWidth: "0", display: "grid", gridTemplateColumns: "minmax(0, 1fr) auto", columnGap: "12px", rowGap: "1px",
  alignItems: "baseline",
});
export const menuStat = style({ textAlign: "right", fontSize: vars.textXs, color: vars.muted });
/** The workspace in use, a soft card atop the menu: its name and what it holds, and the way into its settings. */
export const menuCurrent = style({
  marginBottom: "4px", padding: "10px 10px 10px 12px", background: `color-mix(in srgb, ${vars.text} 5%, transparent)`,
});
export const menuCurrentText = style({ flex: "1", minWidth: "0", display: "grid", gap: "1px" });
export const menuCurrentGo = style({ display: "flex", alignItems: "center", gap: "2px", flex: "none", fontSize: vars.textXs, color: vars.muted });
export const inviteDot = style({
  width: "8px", height: "8px", borderRadius: "50%", background: vars.accent, flex: "none",
});
export const menuInvite = style({
  display: "flex", alignItems: "center", gap: "10px", padding: "6px 10px", fontSize: vars.textSm,
});
export const menuInviteActions = style({ display: "flex", gap: "4px", flex: "none" });
export const menuInviteBtn = style({
  height: "28px", padding: "0 12px", outline: "none",
  selectors: {
    "&[data-highlighted]": { filter: "brightness(0.95)" },
  },
});
/** A workspace with no station (cloud/workspace.tsx's Onboarding): one page, adding the first. */
export const onboarding = style({
  display: "flex", flexDirection: "column", height: "100%", minHeight: "0", overflow: "auto", background: vars.canvas,
});
export const onboardingBar = style({
  flex: "none", display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px",
  padding: "0 12px 0 0", WebkitAppRegion: "drag",
});
export const onboardingAccount = style({ width: "240px", WebkitAppRegion: "no-drag" });
export const onboardingMain = style({
  flex: "1", width: "min(560px, calc(100% - 48px))", margin: "0 auto", padding: "24px 0 48px", display: "flex",
  flexDirection: "column", alignItems: "center", textAlign: "center",
});
export const onboardingTitle = style({ margin: "20px 0 8px", fontSize: vars.textLg, fontWeight: "600" });
export const onboardingFoot = style({ marginTop: "20px", fontSize: vars.textSm });
globalStyle(`${threadItem} ${muted}, ${menuWorkspace} ${muted}, ${menuCurrentText} ${muted}`, { fontSize: vars.textXs });
globalStyle(`${menuCurrentText} b`, { fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
globalStyle(`${accountTrigger} > svg`, { color: vars.muted, flex: "none", marginLeft: "auto" });
globalStyle(`${menuInvite} ${threadItem}`, { flex: "1", minWidth: "0" });
globalStyle(`${onboarding} ${callout}`, { width: "100%", textAlign: "left" });
