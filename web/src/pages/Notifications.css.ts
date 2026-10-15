// The notifications page (Notifications.tsx): the preview screen, the ways of telling as tiles, the kinds as rows that
// open to their ways.
import { style } from "@vanilla-extract/css";
import { cardGround } from "../styles/pages.css.ts";
import { vars } from "../styles/tokens.css.ts";

export const muted = style({ color: vars.muted });

// The preview: a small screen with the banner at its top right, the dock on its right edge, the app's icon below.
export const screen = style({
  position: "relative", height: "200px", marginBottom: "28px", overflow: "hidden",
  borderRadius: `calc(22px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: `linear-gradient(150deg, ${vars.blueBg}, ${vars.accentBg})`,
});
export const banner = style({
  position: "absolute", top: "14px", right: "14px", width: "min(320px, calc(100% - 28px))",
  display: "flex", gap: "10px", alignItems: "flex-start", padding: "10px 12px",
  borderRadius: `calc(16px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: vars.raised, boxShadow: `0 1px 6px ${vars.shadow}`,
  transition: `opacity ${vars.dur} ${vars.easeOut}, transform ${vars.dur} ${vars.easeOut}`,
  selectors: { "&[data-off]": { opacity: "0", transform: "translateY(-12px)" } },
});
// The app's icon drawn as the system draws it: its square in a rounded corner.
export const bannerIcon = style({ flex: "none", width: "28px", height: "28px", borderRadius: "22%" });
export const bannerText = style({ flex: "1", minWidth: "0", display: "grid", gap: "2px", fontSize: vars.textMeta, lineHeight: vars.leadingMeta });
export const bannerHead = style({ display: "flex", gap: "8px", justifyContent: "space-between", minWidth: "0" });
export const bannerBody = style({ overflow: "hidden", display: "-webkit-box", WebkitLineClamp: "2", WebkitBoxOrient: "vertical" });
export const edge = style({ position: "absolute", right: "0", bottom: "16px", display: "grid", gap: "4px", justifyItems: "end" });
export const edgeItem = style({
  padding: "2px 10px 2px 12px", borderRadius: "999px 0 0 999px", background: vars.raised, color: vars.muted,
  fontSize: vars.textCaption, lineHeight: vars.leadingCaption,
  selectors: { "&[data-kind=failed]": { color: vars.red }, "&[data-kind=wait]": { color: vars.accentText } },
});
export const dockBar = style({
  position: "absolute", bottom: "10px", left: "50%", transform: "translateX(-50%)",
  display: "flex", gap: "10px", padding: "7px 10px", borderRadius: `calc(16px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  background: `color-mix(in oklab, ${vars.raised} 70%, transparent)`,
});
export const appIcon = style({ width: "30px", height: "30px", borderRadius: "8px", background: vars.line });
export const appIconMine = style({ position: "relative", width: "30px", height: "30px" });
export const appIconImage = style({ display: "block", width: "100%", height: "100%", borderRadius: "22%" });
export const badge = style({
  position: "absolute", top: "-6px", right: "-8px", minWidth: "18px", height: "18px", padding: "0 5px",
  borderRadius: "999px", background: vars.red, color: vars.onPrimary, fontSize: vars.textCaption, lineHeight: "18px", textAlign: "center",
});

// The ways of telling: tiles side by side, each with its picture.
export const tiles = style({ display: "grid", gridTemplateColumns: "repeat(auto-fit, minmax(120px, 1fr))", gap: "10px" });
export const tile = style({
  display: "grid", justifyItems: "center", gap: "4px", padding: "14px 10px 12px",
  borderRadius: `calc(18px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: cardGround,
  border: "2px solid transparent", color: vars.text, font: "inherit", fontSize: vars.textUi, cursor: "pointer",
  transition: `border-color ${vars.dur} ${vars.easeOut}`,
  selectors: { "&[data-on]": { borderColor: vars.accent }, "&[data-refused]": { borderColor: "transparent" }, "&:disabled": { cursor: "default", opacity: "0.5" } },
});
// What the system refused, under the tiles, with the way to its settings.
export const refused = style({
  display: "flex", alignItems: "center", gap: "12px", marginTop: "10px", padding: "10px 14px",
  borderRadius: vars.rField, cornerShape: vars.cornerShape, background: vars.redBg, color: vars.red, fontSize: vars.textUi,
});
export const refusedAction = style({ marginLeft: "auto", flex: "none" });
export const tilePicture = style({
  position: "relative", width: "72px", height: "46px", marginBottom: "4px", overflow: "hidden",
  borderRadius: "8px", background: vars.canvas, border: `1px solid ${vars.line}`,
});
const shape = { position: "absolute", display: "block", background: vars.lineStrong } as const;
export const picBanner = style({ ...shape, top: "5px", right: "5px", width: "38px", height: "11px", borderRadius: "4px" });
export const picApp = style({ ...shape, bottom: "5px", left: "26px", width: "18px", height: "18px", borderRadius: "5px", background: vars.accent });
export const picBadge = style({ position: "absolute", top: "-4px", right: "-5px", width: "9px", height: "9px", borderRadius: "50%", background: vars.red });
export const picEdge = style({
  ...shape, right: "0", width: "18px", height: "7px", borderRadius: "4px 0 0 4px",
  selectors: { "&:first-child": { top: "13px" }, "&:last-child": { top: "24px" } },
});
export const tileName = style({ fontWeight: "500" });
export const tileState = style({ color: vars.muted, fontSize: vars.textMeta, selectors: { [`${tile}[data-refused] &`]: { color: vars.red } } });

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
export const kindWays = style({ display: "grid", gap: "4px", padding: "0 0 12px 14px" });
export const wayRow = style({ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px", minHeight: "32px", fontSize: vars.textUi, cursor: "pointer" });
export const sound = style({ margin: "0", color: vars.muted, fontSize: vars.textMeta });
