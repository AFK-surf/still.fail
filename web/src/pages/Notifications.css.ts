// The notifications page (Notifications.tsx): the preview screen, the ways of telling as tiles, the kinds as rows that
// open to their ways.
import { style } from "@vanilla-extract/css";
import { surfaceCorner } from "@stillfail/ui/styles/align.ts";
import { cardLook } from "../styles/pages.css.ts";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { litOver } from "@stillfail/ui/styles/lit.ts";

export const muted = style({ color: vars.muted });

// The preview: a small screen of the device's system (Notifications.tsx SYSTEM). macOS: the banner in its top right
// corner, the app's icon in the Dock below; Windows: the banner in its bottom right corner, over the taskbar.
/** How far the banner stands from the screen's edges, and its corner: the screen's is the two (concentric). */
const BANNER_IN = 12;
const BANNER_CORNER = 16;
export const screen = style({
  position: "relative", height: "200px", marginBottom: "28px", overflow: "hidden",
  borderRadius: surfaceCorner(BANNER_IN, BANNER_CORNER), cornerShape: vars.cornerShape,
  background: `linear-gradient(150deg, ${vars.blueBg}, ${vars.accentBg})`,
});
/** Windows' taskbar: the screen's whole width at its foot. */
const TASKBAR = 44;
/** A banner as the system draws it, small. */
const bannerLook = {
  display: "flex", gap: "10px", alignItems: "flex-start", padding: "10px 12px",
  borderRadius: `${BANNER_CORNER}px`, cornerShape: vars.cornerShape, // own corner: the system's banner, drawn small; the screen round it follows it
  background: vars.raised, boxShadow: `0 1px 6px ${vars.shadow}`,
  transition: `opacity ${vars.dur} ${vars.easeOut}, transform ${vars.dur} ${vars.easeOut}`,
} as const;
export const banner = style({
  ...bannerLook,
  position: "absolute", top: `${BANNER_IN}px`, right: `${BANNER_IN}px`, width: `min(320px, calc(100% - ${2 * BANNER_IN}px))`,
  selectors: {
    "&[data-off]": { opacity: "0", transform: "translateY(-12px)" },
    '&[data-system="windows"]': { top: "auto", bottom: `${TASKBAR + BANNER_IN}px` },
    '&[data-system="windows"][data-off]': { transform: "translateY(12px)" },
  },
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
export const taskbar = style({
  position: "absolute", left: "0", right: "0", bottom: "0", height: `${TASKBAR}px`,
  display: "flex", gap: "10px", alignItems: "center", justifyContent: "center",
  background: `color-mix(in oklab, ${vars.raised} 70%, transparent)`,
});
export const appIcon = style({ width: "30px", height: "30px", borderRadius: "8px", cornerShape: vars.cornerShape, background: vars.line }); // own corner: an app's icon in the Dock, drawn small, its Dock's shape
export const appIconMine = style({ position: "relative", width: "30px", height: "30px" });
export const appIconImage = style({ display: "block", width: "100%", height: "100%", borderRadius: "22%" });

// A phone's system (Android, iOS): the device itself, a phone (a tablet, on one) standing up from the preview's foot
// with its top in view, the card's ground round it: its frame 6 round its screen (the frame's corner the screen's
// with it), on the screen its status bar and its camera (Android's hole, iOS's island), the banner across the top
// (a phone's width at most) over the home screen's first row of icons. As the app's page draws it (sfdesk
// notifications.mbt device_preview).
const BEZEL = 6;
const SCREEN_CORNER = 18;
export const stage = style({ ...cardLook, position: "relative", height: "200px", marginBottom: "28px", overflow: "hidden" });
export const device = style({
  position: "absolute", top: "20px", left: "50%", transform: "translateX(-50%)", width: "min(300px, calc(100% - 64px))", height: "200px",
  padding: `${BEZEL}px`, borderRadius: `${SCREEN_CORNER + BEZEL}px`, cornerShape: vars.cornerShape, background: vars.text, // its foot out of the stage
  selectors: { "&[data-tablet]": { width: "min(520px, calc(100% - 64px))" } },
});
export const deviceScreen = style({
  position: "relative", width: "100%", height: "100%", overflow: "hidden",
  borderRadius: `${SCREEN_CORNER}px`, cornerShape: vars.cornerShape,
  background: `linear-gradient(150deg, ${vars.blueBg}, ${vars.accentBg})`,
});
export const status = style({
  position: "absolute", top: "0", left: "22px", right: "22px", height: "24px",
  display: "flex", alignItems: "center", justifyContent: "space-between", fontSize: vars.textCaption, fontWeight: "600",
});
export const battery = style({ width: "18px", height: "9px", borderRadius: "2px", background: vars.text });
const camera = { position: "absolute", top: "8px", left: "50%", transform: "translateX(-50%)", borderRadius: "999px", background: vars.text } as const;
export const hole = style({ ...camera, width: "8px", height: "8px" });
export const island = style({ ...camera, width: "36px", height: "11px" });
export const homeRow = style({ position: "absolute", top: "100px", left: "0", right: "0", display: "flex", justifyContent: "center", gap: "24px" });
export const homeApp = style({ width: "36px", height: "36px", borderRadius: "8px", cornerShape: vars.cornerShape, background: vars.line }); // own corner: an app's icon, drawn small
export const homeAppMine = style({ position: "relative", width: "36px", height: "36px" });
export const bannerAcross = style({
  ...bannerLook,
  position: "absolute", top: "24px", left: "8px", right: "8px", maxWidth: "400px", margin: "0 auto",
  selectors: { "&[data-off]": { opacity: "0", transform: "translateY(-12px)" } },
});
// The system's dot on the app's icon while a notification shows (Android's launcher's).
export const dot = style({ position: "absolute", top: "-3px", right: "-3px", width: "10px", height: "10px", borderRadius: "50%", background: vars.red });

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
export const picBanner = style({
  ...shape, top: "5px", right: "5px", width: "38px", height: "11px", borderRadius: "3px",
  selectors: {
    // a phone's across its top; Windows' in its bottom right corner
    '&[data-system="phone"]': { left: "5px", width: "auto" },
    '&[data-system="windows"]': { top: "auto", bottom: "5px" },
  },
});
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
