import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "../styles/tokens.css.ts";
import { mHPhase, mSettingText } from "./History.css.ts";

const corner = (px: number) => ({ borderRadius: `calc(${px}px * ${vars.cornerScale})`, cornerShape: vars.cornerShape });

/**
 * The workspace at Home's bottom left (Workspaces.tsx WorkspaceDock): a frosted capsule as tall as 令, as wide as its
 * name (up to 奏), the name over the dots; swiped sideways, its names follow the finger, the capsule clipping them.
 */
export const mDock = style({
  position: "relative", display: "flex", flexDirection: "column", justifyContent: "center", alignItems: "flex-start", gap: "4px",
  boxSizing: "border-box", flex: "0 1 auto", minWidth: "96px", height: "56px", marginRight: "auto", padding: "0 18px",
  borderRadius: "999px", overflow: "hidden", color: "var(--m-ink)", cursor: "pointer", pointerEvents: "auto",
  touchAction: "none", userSelect: "none", WebkitUserSelect: "none",
});
/** The names side by side: the one in view laid out (the capsule's width), the one before and the next beside it. */
export const mStrip = style({ position: "relative", display: "flex", maxWidth: "100%", "--dx": "0px", "--here": "100%" } as Record<string, string>);
/** A name (with the invitations' dot), a gap after the one before's end, or before the next's start. */
export const mPage = style({
  display: "flex", alignItems: "center", gap: "6px", minWidth: "0", maxWidth: "100%", height: "22px", transform: "translateX(var(--dx))",
  selectors: {
    '&:not([data-page="here"])': { position: "absolute", top: "0", left: "0", maxWidth: "none" },
    '&[data-page="before"]': { transform: "translateX(calc(var(--dx) - 100% - 24px))" },
    '&[data-page="after"]': { transform: "translateX(calc(var(--dx) + var(--here) + 24px))" },
    // The ones beside it only while a finger has the name (and it settles back): at rest it stands alone.
    [`&:is([data-page="before"], [data-page="after"]):not(${mStrip}[data-peek] *)`]: { visibility: "hidden" },
    '&[data-page="left"]': { visibility: "hidden" },
    [`${mStrip}[data-settling] &`]: { transition: "transform 240ms var(--m-standard)" },
  },
});
/** Where it is among the workspaces, under its name. */
export const mDots = style({ display: "flex", alignItems: "center", gap: "6px", height: "8px" });
export const mPageDot = style({
  width: "6px", height: "6px", borderRadius: "50%", background: "var(--m-line)", flex: "none", boxSizing: "border-box",
  selectors: {
    "&[data-here]": { background: "var(--m-ink)" },
    // As their marks (../ChatMark.css.ts chatMarkInline): new messages, something wrong, waiting on the viewer.
    '&[data-tone="done"]': { background: "#3b82f6" },
    '&[data-tone="alert"]': { background: "#e5484d" },
    '&[data-tone="wait"]': { width: "8px", height: "8px", background: "none", border: "2px solid #3b82f6" },
  },
});

/** The panel under the name (app.tsx MenuHost, `content`). */
export const mPanel = style({ display: "flex", flexDirection: "column" });
export const mPanelNote = style({ padding: "4px 10px" });
export const mGroup = style({ display: "flex", flexDirection: "column" });
export const mGroupLabel = style({ padding: "8px 10px 4px", fontSize: vars.textCaption, color: "var(--m-muted)" });
export const mRow = style({});
export const mTile = style({
  display: "grid", placeItems: "center", flex: "none", width: "32px", height: "32px", ...corner(10),
  background: "var(--m-chip)", fontSize: vars.textUi, fontWeight: "600",
});
export const mRowName = style({ flex: "1", minWidth: "0", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontWeight: "600" });
export const mInvite = style({ display: "flex", alignItems: "center", gap: "8px", padding: "9px 10px", marginBottom: "4px", ...corner(14), background: "var(--m-accent-bg)" });
export const mInviteText = style({ flex: "1", minWidth: "0", display: "flex", flexDirection: "column", fontSize: vars.textMeta });
export const mActions = style({ display: "flex", gap: "4px", marginTop: "6px" });
export const mAction = style({});

globalStyle(`${mPanel} button${mRow}, ${mPanel} button${mAction}`, {
  display: "flex", alignItems: "center", gap: "12px", width: "100%", border: "0", background: "none", color: "var(--m-ink)",
  cursor: "pointer", ...corner(14),
});
globalStyle(`${mPanel} button${mRow}`, { padding: "9px 10px", textAlign: "left" });
globalStyle(`${mPanel} button${mRow}[data-here]`, { background: "var(--m-chip)" });
globalStyle(`${mPanel} button${mRow}[data-here] ${mTile}`, { background: "var(--m-ink)", color: "var(--m-bg)" });
globalStyle(`${mPanel} button${mAction}`, { flex: "1", justifyContent: "center", gap: "6px", height: "40px", padding: "0 8px", whiteSpace: "nowrap" });
globalStyle(`${mPanel} button${mAction}:disabled`, { opacity: "0.5" });
globalStyle(`${mInviteText} small`, { fontSize: vars.textCaption, color: "var(--m-muted)" });
globalStyle(`${mPanel} ${mInvite} button`, { flex: "none", height: "32px", padding: "0 12px", fontSize: vars.textMeta });
/** Here rather than with its class: it comes after .m-invite small, and wins over it. */
globalStyle(`${mHPhase} small`, { fontSize: vars.textCaption, color: "var(--m-subtle)" });
/** Here rather than with its class: it comes after .m-invite small, and wins over it. */
globalStyle(`${mSettingText} small`, { fontSize: vars.textCaption });
globalStyle(`${mDock} b`, {
  minWidth: "0", fontSize: vars.textTitle, lineHeight: "22px", fontWeight: "600", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap",
});
