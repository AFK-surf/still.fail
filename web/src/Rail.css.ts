// The rail at the wide screen's left (Rail.tsx): a column of the sidebar's own ground, the places as icons.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "./styles/tokens.css.ts";

const wide = "(min-width: 701px)";
const narrow = "(max-width: 700px)";

export const rail = style({
  display: "flex", flexDirection: "column", alignItems: "center", gap: 6, padding: "0 0 12px", background: vars.sidebar,
  WebkitUserSelect: "none", userSelect: "none",
  "@media": { [narrow]: { display: "none" } },
});
/**
 * Level with the sidebar's top row, the sidebar's opening and closing in it. In the desktop app the row drags the window;
 * on macOS its buttons are in it (main.ts puts them 16 px in, reaching past the rail), and the toggle comes under them.
 */
export const top = style({
  flex: "none", alignSelf: "stretch", display: "flex", alignItems: "center", justifyContent: "center", height: 48, marginBottom: 6,
  selectors: {
    "[data-desktop] &": { height: 44, WebkitAppRegion: "drag" },
    '[data-desktop="inset"]:not([data-fullscreen]) &': { height: 88, alignItems: "flex-end" },
  },
});
globalStyle(`[data-desktop] ${top} > *`, { WebkitAppRegion: "no-drag" });
/** The panel icons are drawn for a panel at the right: turned round for the sidebar at the left. */
export const mirrored = style({ transform: "scaleX(-1)" });
export const grow = style({ flex: 1 });

export const item = style({
  position: "relative", display: "grid", placeItems: "center", width: 38, height: 38, padding: 0, border: 0,
  borderRadius: `calc(12px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: "none", color: vars.muted,
  cursor: "pointer", transition: `background ${vars.dur} ${vars.easeOut}, color ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover": { background: vars.hover, color: vars.text },
    "&[data-on]": { background: vars.selected, color: vars.text },
  },
});
/** 奏, the word, its size the icons' (vars.textTitle is the nearest of the type sizes). */
export const zou = style({ fontSize: vars.textTitle, lineHeight: "20px", fontWeight: 600 });
/** What waits on a place: a count on the icon's corner, cut out of the rail's ground. */
export const count = style({
  position: "absolute", top: 2, right: 0, minWidth: 16, height: 16, padding: "0 4px", boxSizing: "border-box", borderRadius: 8,
  background: vars.red, color: "#fff", fontSize: vars.textCaption, lineHeight: "16px", fontWeight: 600, textAlign: "center",
  fontVariantNumeric: "tabular-nums", boxShadow: `0 0 0 2px ${vars.sidebar}`,
});

/** The workspaces to switch to (Rail.tsx RailWorkspaces), each its first letter, the one in view ringed. */
export const workspaces = style({ display: "flex", flexDirection: "column", alignItems: "center", gap: 6, padding: "4px 0" });
export const workspaceItem = style({
  position: "relative", display: "grid", placeItems: "center", width: 30, height: 30, padding: 0, border: 0,
  borderRadius: `calc(9px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: vars.hover, color: vars.muted,
  fontSize: vars.textUi, fontWeight: 600, cursor: "pointer",
  selectors: {
    "&:hover": { color: vars.text },
    "&[data-on]": { background: vars.text, color: vars.sidebar },
  },
});
/** The switcher among them: no room above it there. */
export const workspaceHere = style({ display: "contents" });
globalStyle(`${workspaceHere} > button`, { marginTop: 0 });
// What waits in the others is on each of them there, not on it too.
globalStyle(`${workspaceHere} > button > span`, { display: "none" });
/** The workspace in view, its first letter; its menu is the switcher's (cloud/workspace.tsx). */
export const workspace = style({
  position: "relative", display: "grid", placeItems: "center", width: 30, height: 30, marginTop: 4, padding: 0, border: 0,
  borderRadius: `calc(9px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: vars.text, color: vars.sidebar,
  fontSize: vars.textUi, fontWeight: 600, cursor: "pointer",
});
export const mark = style({ position: "absolute", top: -4, right: -4, display: "flex", padding: 2, borderRadius: "50%", background: vars.sidebar });

/** What is about the rail: nothing on a narrow screen. */
export const wideOnly = style({ "@media": { [narrow]: { display: "none" } } });
/** What the rail holds, on a narrow screen (no rail there) in the sidebar's foot as before. */
export const narrowOnly = style({ "@media": { [wide]: { display: "none" } } });

/** The places the stations lend (FilesNav): under each station's name, its folders. */
export const station = style({
  display: "flex", alignItems: "center", gap: 6, margin: "14px 10px 4px", fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted,
  selectors: { "&:first-child": { marginTop: 6 } },
});
export const dot = style({
  width: 6, height: 6, borderRadius: "50%", background: vars.subtle, flex: "none",
  selectors: { "&[data-online]": { background: vars.online } },
});

// ── changing it (Rail.tsx: its menu's 自定义侧边条, or 外观's) ──

/** A place in the rail as it is: nothing of its own in the layout (its menu finds it by `data-rail-item`). */
export const slot = style({ display: "contents" });
/** A place while the rail is changed: dragged up or down to where it goes, a − at its corner to take it out. */
export const editing = style({
  position: "relative", borderRadius: `calc(12px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, cursor: "grab", touchAction: "none",
  outline: `1.5px dashed ${vars.lineStrong}`, outlineOffset: -1,
  selectors: { "&[data-dragged]": { cursor: "grabbing", background: vars.selected, outlineStyle: "solid", zIndex: 1 } },
});
/** What the place draws, not pressed while it is moved. */
export const still = style({ pointerEvents: "none" });
export const remove = style({
  position: "absolute", top: -5, left: -5, display: "grid", placeItems: "center", width: 18, height: 18, padding: 0, border: 0,
  borderRadius: "50%", background: vars.text, color: vars.sidebar, cursor: "pointer", boxShadow: `0 0 0 2px ${vars.sidebar}`,
});
/** The panel beside the rail of what can be added (ui.tsx Panel* parts), with more room than a menu. */
export const adder = style({
  width: 248, display: "grid", gap: 8,
  // Over the popover's own padding, whichever of the two style sheets comes first.
  selectors: { "&[data-side]": { vars: { "--panel-pad": "12px" } } },
});
export const zouSmall = style({ fontSize: vars.textBody, lineHeight: "18px", fontWeight: 600 });
