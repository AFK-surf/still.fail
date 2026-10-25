// The notifications page (Notifications.tsx): the preview screen, the ways of telling as tiles, the kinds as rows that
// open to their ways.
import { style } from "@vanilla-extract/css";
import { surfaceCorner } from "@stillfail/ui/styles/align.ts";
import { cardLook } from "../styles/pages.css.ts";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { litOver } from "@stillfail/ui/styles/lit.ts";

export const muted = style({ color: vars.muted });

// The preview: a small screen with the banner in its top right corner, the app's icon below.
/** How far the banner stands from the screen's edges, and its corner: the screen's is the two (concentric). */
const BANNER_IN = 12;
const BANNER_CORNER = 16;
export const screen = style({
  position: "relative", height: "200px", marginBottom: "28px", overflow: "hidden",
  borderRadius: surfaceCorner(BANNER_IN, BANNER_CORNER), cornerShape: vars.cornerShape,
  background: `linear-gradient(150deg, ${vars.blueBg}, ${vars.accentBg})`,
});
export const banner = style({
  position: "absolute", top: `${BANNER_IN}px`, right: `${BANNER_IN}px`, width: `min(320px, calc(100% - ${2 * BANNER_IN}px))`,
  display: "flex", gap: "10px", alignItems: "flex-start", padding: "10px 12px",
  borderRadius: `${BANNER_CORNER}px`, cornerShape: vars.cornerShape, // own corner: the system's banner, drawn small; the screen round it follows it
  background: vars.raised, boxShadow: `0 1px 6px ${vars.shadow}`,
  transition: `opacity ${vars.dur} ${vars.easeOut}, transform ${vars.dur} ${vars.easeOut}`,
  selectors: { "&[data-off]": { opacity: "0", transform: "translateY(-12px)" } },
});
// The app's icon drawn as the system draws it: its square in a rounded corner.
export const bannerIcon = style({ flex: "none", width: "28px", height: "28px", borderRadius: "22%" });
export const bannerText = style({ flex: "1", minWidth: "0", display: "grid", gap: "2px", fontSize: vars.textMeta, lineHeight: vars.leadingMeta });
export const bannerHead = style({ display: "flex", gap: "8px", justifyContent: "space-between", minWidth: "0" });
export const bannerBody = style({ overflow: "hidden", display: "-webkit-box", WebkitLineClamp: "2", WebkitBoxOrient: "vertical" });
export const dockBar = style({
  position: "absolute", bottom: "10px", left: "50%", transform: "translateX(-50%)",
  display: "flex", gap: "10px", padding: "7px", borderRadius: surfaceCorner(7, 8), cornerShape: vars.cornerShape,
  background: `color-mix(in oklab, ${vars.raised} 70%, transparent)`,
});
export const appIcon = style({ width: "30px", height: "30px", borderRadius: "8px", cornerShape: vars.cornerShape, background: vars.line }); // own corner: an app's icon in the Dock, drawn small, its Dock's shape
export const appIconMine = style({ position: "relative", width: "30px", height: "30px" });
export const appIconImage = style({ display: "block", width: "100%", height: "100%", borderRadius: "22%" });
export const badge = style({
  position: "absolute", top: "-6px", right: "-8px", minWidth: "18px", height: "18px", padding: "0 5px",
  borderRadius: "999px", background: vars.red, color: vars.onPrimary, fontSize: vars.textCaption, lineHeight: "18px", textAlign: "center",
});

// The ways of telling: tiles side by side, each with its picture.
export const tiles = style({ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(120px, 1fr))", gap: "10px" });
export const tile = style({
  ...cardLook, borderRadius: vars.rCard, display: "grid", justifyItems: "center", gap: "4px", padding: "14px 10px 12px",
  border: "2px solid transparent", color: vars.text, font: "inherit", fontSize: vars.textUi, cursor: "pointer",
  transition: `border-color ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&[data-on]": { borderColor: vars.accent },
    // Pressed, each turns its way on or off (or goes where the system allows it): pointed at, the ink over its card's
    // ground, the one asking for the system's leave as the others (docs/ui-panels.md 悬停).
    "&:hover:not(:disabled)": litOver,
    "&[data-action]": { borderColor: `color-mix(in srgb, ${vars.red} 55%, transparent)` },
    "&:disabled": { cursor: "default", opacity: "0.5" },
  },
});
// The system has to allow it first: the tile is the way there, ringed in red, its picture marked, a red button in it.
export const tileAction = style({
  display: "inline-flex", alignItems: "center", gap: "2px", marginTop: "4px", padding: "4px 10px 4px 12px", borderRadius: "999px",
  background: vars.red, color: vars.onPrimary, fontSize: vars.textMeta, fontWeight: "500",
});
export const picAlert = style({
  position: "absolute", top: "50%", left: "50%", translate: "-50% -30%", width: "18px", height: "18px", borderRadius: "50%",
  display: "grid", placeItems: "center", background: vars.red, color: vars.onPrimary, fontSize: vars.textCaption, fontWeight: "600", lineHeight: "1",
});
export const tilePicture = style({
  position: "relative", width: "72px", height: "46px", marginBottom: "4px", overflow: "hidden",
  borderRadius: "8px", background: vars.canvas, border: `1px solid ${vars.line}`, // own corner: a screen, drawn small
});
const shape = { position: "absolute", display: "block", background: vars.lineStrong } as const;
// In the picture's top right corner: as far from both edges, its corner the picture's less that (8 − 5).
export const picBanner = style({ ...shape, top: "5px", right: "5px", width: "38px", height: "11px", borderRadius: "3px" });
export const picApp = style({ ...shape, bottom: "5px", left: "26px", width: "18px", height: "18px", borderRadius: "5px", background: vars.accent }); // own corner: the app's icon, drawn small
export const picBadge = style({ position: "absolute", top: "-4px", right: "-5px", width: "9px", height: "9px", borderRadius: "50%", background: vars.red });
export const tileName = style({ fontWeight: "500" });
export const tileState = style({ color: vars.muted, fontSize: vars.textMeta });

// The kinds: rows in a card, each opening to its ways.
export const kinds = style({ gap: "0", paddingTop: "6px", paddingBottom: "6px" });
export const kind = style({ selectors: { "& + &": { borderTop: `1px solid ${vars.line}` } } });
export const kindHead = style({
  display: "flex", alignItems: "center", gap: "12px", width: "100%", padding: "12px 0",
  background: "none", border: "none", color: vars.text, font: "inherit", textAlign: "left", cursor: "pointer",
});
export const kindText = style({ flex: "1", minWidth: "0", display: "grid", gap: "2px", fontSize: vars.textUi });
export const sum = style({ flex: "none", color: vars.muted, fontSize: vars.textMeta });
export const chevron = style({
  flex: "none", color: vars.muted, transition: `transform ${vars.dur} ${vars.easeOut}`,
  selectors: { [`${kind}[data-open] &`]: { transform: "rotate(90deg)" } },
});
// Its switches end as far from the card's edge below as from its side (the card's 6 and these 14 make its 20).
export const kindWays = style({ display: "grid", gap: "4px", padding: "0 0 14px 14px" });
export const wayRow = style({ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px", minHeight: "32px", fontSize: vars.textUi, cursor: "pointer" });
export const sound = style({ margin: "0", color: vars.muted, fontSize: vars.textMeta });
