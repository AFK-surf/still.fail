import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
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
  fontSize: vars.textUi, fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
export const accountMenu = style({});
/** A workspace in the menu: its name, and under it whose it is when there are accounts to tell apart. */
export const menuWorkspace = style({ flex: "1", minWidth: "0", display: "grid", rowGap: "1px" });
/** A workspace's name in the menu, and the dot of what it has waiting after it. */
export const menuWorkspaceName = style({ display: "flex", alignItems: "center", gap: "6px", minWidth: "0" });
export const menuWorkspaceText = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** The tick of the workspace in use, in a column the others keep empty so the names line up. */
export const menuCheck = style({ width: "14px", flex: "none", display: "flex", alignSelf: "flex-start", marginTop: "3px" });
/** The key that switches to it, at its end. */
export const menuKey = style({ flex: "none", alignSelf: "flex-start", lineHeight: "20px", fontSize: vars.textMeta, color: vars.subtle, fontVariantNumeric: "tabular-nums" });
/**
 * Making a workspace and adding an account: seldom done, so a line of small words above the list, away from the trigger. The first's icon
 * stands in the ticks' column and its words start where the names do (a row's padding, the tick's 14px, the gap).
 */
export const menuRare = style({ display: "flex", flexWrap: "wrap", gap: "2px", marginBottom: "8px" });
export const menuRareItem = style({
  display: "flex", alignItems: "center", gap: "8px", height: "24px", padding: "0 10px", border: "0", borderRadius: "999px",
  fontSize: vars.textMeta, color: vars.muted, cursor: "pointer", outline: "none", userSelect: "none",
  selectors: {
    "&[data-highlighted]": { background: vars.hover, color: vars.text },
    "&[data-disabled]": { color: vars.subtle, cursor: "default" },
  },
});
export const menuRareIcon = style({ width: "14px", flex: "none", display: "flex", justifyContent: "center" });
export const inviteDot = style({
  width: "8px", height: "8px", borderRadius: "50%", background: vars.accent, flex: "none",
});
export const menuInvite = style({
  display: "flex", flexWrap: "wrap", alignItems: "center", gap: "10px", padding: "6px 10px", fontSize: vars.textUi,
});
/** What went wrong answering it, on a line of its own under it. */
export const menuInviteError = style({ flexBasis: "100%", margin: "0" });
/** Something asked from the menu on its way: in the chevron's place. */
export const accountSpinner = style({ marginLeft: "auto" });
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
  // The Windows app's window buttons over its right end (styles/global.css.ts).
  selectors: { ':is([data-desktop="overlay"], [data-desktop="custom"]) &': { paddingRight: "calc(var(--window-buttons, 0px) + 12px)" } },
});
export const onboardingAccount = style({ width: "240px", WebkitAppRegion: "no-drag" });
export const onboardingMain = style({
  flex: "1", width: "min(560px, calc(100% - 48px))", margin: "0 auto", padding: "24px 0 48px", display: "flex",
  flexDirection: "column", alignItems: "center", textAlign: "center",
});
export const onboardingTitle = style({ margin: "20px 0 8px", fontSize: vars.textHeading, fontWeight: "600" });
export const onboardingFoot = style({ marginTop: "20px", fontSize: vars.textUi });
/** A link of the foot that opens something rather than going to a page: a button that looks as the others. */
export const onboardingLinkButton = style({ padding: "0", border: "0", background: "none", font: "inherit", cursor: "pointer" });
globalStyle(`${threadItem} ${muted}, ${menuWorkspace} ${muted}`, { fontSize: vars.textMeta });
globalStyle(`${menuCheck} svg, ${menuRareItem} svg`, { color: "inherit" });
globalStyle(`${menuCheck} svg`, { color: vars.accent });
globalStyle(`${accountTrigger} > svg`, { color: vars.muted, flex: "none", marginLeft: "auto" });
globalStyle(`${menuInvite} ${threadItem}`, { flex: "1", minWidth: "0" });
globalStyle(`${onboarding} ${callout}`, { width: "100%", textAlign: "left" });
