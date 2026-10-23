import { globalStyle, style, styleVariants } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { cardGround } from "./styles/pages.css.ts";

// The people a day's bar is split by, in the order the usage view ranks them (client/core-ts/src/views/usage.ts SERIES),
// the rest grey. Checked with the dataviz validator (four slots, adjacent pairs) on the light and dark grounds; the
// first is still.fail's own accent, stepped down in dark to stay in the band.
const light = ["#ef6a3c", "#2a78d6", "#1baf7a", "#4a3aa7"];
const dark = ["#e0602f", "#3987e5", "#199e70", "#9085e9"];
const seriesVars = (colors: string[]) => Object.fromEntries(colors.map((c, i) => [`--usage-${i}`, c]));

// The page's inks and grounds, as the wide screen has them; the phone's page (`mobile`) puts its own in.
const u = { text: "var(--u-text)", muted: "var(--u-muted)", subtle: "var(--u-subtle)", line: "var(--u-line)", strong: "var(--u-strong)", hover: "var(--u-hover)", tile: "var(--u-tile)" };

// On the page's root: the tooltips that say a day's parts are drawn outside the page.
globalStyle(":root", { vars: { ...seriesVars(light), "--usage-rest": vars.lineStrong } });
globalStyle(":root[data-theme=\"dark\"]", { vars: seriesVars(dark) });
globalStyle(":root:not([data-theme=\"light\"])", { "@media": { "(prefers-color-scheme: dark)": { vars: seriesVars(dark) } } });

export const usage = style({
  vars: {
    "--u-text": vars.text, "--u-muted": vars.muted, "--u-subtle": vars.subtle, "--u-line": vars.line, "--u-strong": vars.lineStrong,
    "--u-hover": vars.hover, "--u-tile": cardGround,
  },
  display: "grid", gap: "28px",
});

/** On the phone's page: its inks, and cards for grounds. */
export const mobile = style({
  vars: {
    "--u-text": "var(--m-ink)", "--u-muted": "var(--m-muted)", "--u-subtle": "var(--m-subtle)", "--u-line": "var(--m-line)",
    "--u-strong": "var(--m-thumb)", "--u-hover": "var(--m-chip)", "--u-tile": "var(--m-surface)", "--usage-rest": "var(--m-thumb)",
  },
  gap: "22px", padding: "0 16px",
});

export const series = styleVariants({
  0: { background: "var(--usage-0)" },
  1: { background: "var(--usage-1)" },
  2: { background: "var(--usage-2)" },
  3: { background: "var(--usage-3)" },
  rest: { background: "var(--usage-rest)" },
});

// ── totals ────────────────────────────────────────────────────────────────

export const tiles = style({
  display: "grid", gridTemplateColumns: "repeat(4, minmax(0, 1fr))", gap: "10px",
  "@media": { "(max-width: 700px)": { gridTemplateColumns: "repeat(2, minmax(0, 1fr))" } },
});
export const tile = style({
  display: "grid", gap: "2px", padding: "14px 16px", borderRadius: vars.rCard, background: u.tile, cornerShape: vars.cornerShape,
});
export const tileLabel = style({ fontSize: vars.textMeta, color: u.muted });
export const tileValue = style({ fontSize: vars.textHeading, lineHeight: "30px", fontWeight: "600", fontVariantNumeric: "tabular-nums", letterSpacing: "-.01em" });
export const tileSub = style({ fontSize: vars.textMeta, color: u.subtle });

// ── the days ──────────────────────────────────────────────────────────────

/** The day picked: its name, its cost large with its calls beside it, over the bars. */
export const dayHead = style({ display: "grid", gap: "2px", marginBottom: "16px" });
export const dayName = style({ fontSize: vars.textMeta, color: u.muted });
export const dayFigures = style({ display: "flex", alignItems: "baseline", gap: "8px", minWidth: "0" });
export const dayCost = style({ fontSize: vars.textHeading, lineHeight: "1.4", fontWeight: "600", letterSpacing: "-.01em", color: u.text });
export const dayCalls = style({ fontSize: vars.textUi, color: u.muted, whiteSpace: "nowrap" });

const PLOT = 150;
/** The room at the plot's right the scale says its lines in, where no bar is. */
const SCALE_ROOM = "24px";
export const plot = style({ position: "relative", height: `${PLOT}px`, borderBottom: `1px solid ${u.line}` });
/** A line of the scale, across under the bars; its words at the right just over it. */
export const tick = style({ position: "absolute", left: "0", right: "0", height: "1px", background: u.line, pointerEvents: "none" });
export const tickLabel = style({
  position: "absolute", right: "0", bottom: "3px", fontSize: vars.textCaption, lineHeight: "14px", color: u.subtle, fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap",
});
export const days = style({
  position: "absolute", inset: `0 ${SCALE_ROOM} 0 0`, display: "flex", alignItems: "stretch", gap: "6px",
  selectors: { "&[data-many]": { gap: "2px" } },
});
/** A day: the whole column is what is clicked, the bar sits at its foot. */
export const day = style({
  flex: "1", minWidth: "0", display: "flex", flexDirection: "column", justifyContent: "flex-end", alignItems: "center",
  padding: "0", border: "0", background: "none", cursor: "pointer",
});
/** A day's bar: its parts one over another, the first at the foot, 1 apart. */
export const bar = style({
  display: "flex", flexDirection: "column-reverse", gap: "1px", width: "min(100%, 16px)",
  selectors: { "&[data-many]": { width: "100%" } },
});
/** A part: round at its ends (3 with many days), the foot's square on the line. */
export const part = style({
  flex: "1 1 0", minHeight: "1px", borderRadius: `calc(4px * ${vars.cornerScale})`, cornerShape: vars.cornerShape,
  selectors: {
    [`${bar}[data-many] &`]: { borderRadius: `calc(2px * ${vars.cornerScale})` },
    "&:first-child": { borderBottomLeftRadius: "0", borderBottomRightRadius: "0" },
  },
});
export const labels = style({ display: "flex", gap: "6px", marginTop: "6px", paddingRight: SCALE_ROOM, selectors: { "&[data-many]": { gap: "2px" } } });
export const label = style({
  flex: "1", minWidth: "0", textAlign: "center", fontSize: vars.textCaption, color: u.subtle, whiteSpace: "nowrap", overflow: "visible",
  fontVariantNumeric: "tabular-nums",
  selectors: { "&[data-on]": { color: u.text, fontWeight: "500" } },
});
/** With several people: each of them, what they spent the day picked, and its share of the day's under it. */
export const dayRows = style({ display: "grid", gap: "12px", marginTop: "16px" });
export const dayRow = style({ display: "grid", gridTemplateColumns: "auto minmax(0, 1fr) auto", alignItems: "center", columnGap: "8px", rowGap: "6px", fontSize: vars.textUi, color: u.text });
export const dayDot = style({ width: "8px", height: "8px", borderRadius: "50%" });
export const dayWho = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const dayPart = style({ fontVariantNumeric: "tabular-nums" });
export const dayShare = style({ gridColumn: "2 / 4", height: "4px", borderRadius: "2px", background: u.hover, overflow: "hidden", display: "flex" });
globalStyle(`${dayShare} > span`, { height: "100%", borderRadius: "2px" });

// ── the lists ─────────────────────────────────────────────────────────────

export const listHead = style({ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px", marginBottom: "8px" });
export const rows = style({ display: "grid" });
export const row = style({
  display: "grid", gridTemplateColumns: "auto minmax(0, 1fr) auto", alignItems: "center", columnGap: "12px", rowGap: "6px",
  padding: "10px 12px", borderRadius: vars.rField, cornerShape: vars.cornerShape, color: u.text, textDecoration: "none",
  fontSize: vars.textUi, transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: { "a&:hover, button&:hover": { background: u.hover }, "button&": { width: "100%", border: "0", background: "none", font: "inherit", textAlign: "left", cursor: "pointer" } },
});
export const rank = style({ width: "20px", textAlign: "right", color: u.subtle, fontSize: vars.textMeta, fontVariantNumeric: "tabular-nums" });
export const face = style({ width: "20px", height: "20px", borderRadius: "50%", overflow: "hidden", display: "grid", placeItems: "center" });
export const rowText = style({ display: "grid", gap: "1px", minWidth: "0" });
export const rowTitle = style({ fontWeight: "500", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const rowSub = style({ fontSize: vars.textMeta, color: u.muted, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
export const rowCost = style({ display: "grid", justifyItems: "end", gap: "1px", fontVariantNumeric: "tabular-nums" });
export const rowShare = style({ fontSize: vars.textMeta, color: u.muted });
/** Its share of the whole, under its words. */
export const share = style({ gridColumn: "2 / 4", height: "4px", borderRadius: "2px", background: u.hover, overflow: "hidden" });
export const shareFill = style({ height: "100%", borderRadius: "2px", background: u.strong });
export const more = style({
  justifySelf: "start", marginTop: "4px", padding: "6px 12px", border: "0", borderRadius: vars.rField, background: "none",
  color: u.muted, font: "inherit", fontSize: vars.textUi, cursor: "pointer", cornerShape: vars.cornerShape,
  selectors: { "&:hover": { background: u.hover, color: u.text } },
});

export const notes = style({ display: "grid", gap: "4px", margin: "0", padding: "0", listStyle: "none", fontSize: vars.textMeta, color: u.subtle });
export const empty = style({ margin: "0", padding: "28px 0", textAlign: "center", fontSize: vars.textUi, color: u.muted });

/** The phone's: what sits on a card of its own (the days, a list). */
export const card = style({ padding: "14px 12px", borderRadius: `calc(18px * ${vars.cornerScale})`, cornerShape: vars.cornerShape, background: u.tile });
export const cardHead = style({ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "12px", padding: "0 4px 10px" });

/** The picks over the page and the lists: each option on one line, as wide as the widest. */
export const pick = style({ minWidth: "140px" });
export const pickLists = style({ minWidth: "300px" });
globalStyle(`${pick} > button, ${pickLists} > button`, { whiteSpace: "nowrap", padding: "0 10px" });

// Inspect the rates behind the total, with the same cards on wide and narrow screens.
export const tileLink = style({ color: "inherit", textDecoration: "none", selectors: { "&:hover": { background: u.hover } } });
export const priceStation = style({ fontSize: vars.textTitle, margin: "0 0 8px", fontWeight: 600 });
export const priceNote = style({ fontSize: vars.textMeta, color: u.muted, margin: "0 0 20px", lineHeight: 1.6 });
