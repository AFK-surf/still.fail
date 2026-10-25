import { style, styleVariants } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { cardGround } from "./styles/pages.css.ts";

export const page = style({ display: "grid", gap: "14px" });

// ── totals ────────────────────────────────────────────────────────────────

export const tiles = style({
  display: "grid", gridAutoFlow: "column", gridAutoColumns: "minmax(0, 1fr)", gap: "8px",
  "@media": { "(max-width: 700px)": { gridAutoFlow: "row", gridTemplateColumns: "repeat(2, minmax(0, 1fr))" } },
});
export const tile = style({
  display: "grid", gap: "2px", padding: "10px 12px 8px", borderRadius: vars.rCard, background: cardGround, cornerShape: vars.cornerShape, minWidth: "0",
});
export const tileHead = style({ display: "flex", justifyContent: "space-between", gap: "8px", fontSize: vars.textMeta, color: vars.muted, whiteSpace: "nowrap" });
export const tileSub = style({ color: vars.subtle, overflow: "hidden", textOverflow: "ellipsis", minWidth: "0" });
export const tileValue = style({ fontSize: vars.textTitle, fontWeight: "600", fontVariantNumeric: "tabular-nums" });
/** The last minutes' line, under the value. */
export const spark = style({ display: "block", width: "100%", height: "26px", marginTop: "2px" });
export const sparkLine = style({ fill: "none", stroke: "currentColor", strokeWidth: "1.25", vectorEffect: "non-scaling-stroke" });
export const sparkArea = style({ fill: "currentColor", opacity: 0.14 });

// ── the bar over the table ────────────────────────────────────────────────

export const bar = style({ display: "flex", alignItems: "center", justifyContent: "space-between", gap: "8px", flexWrap: "wrap", marginTop: "4px" });
export const kinds = style({ minWidth: "260px" });
export const shows = style({ minWidth: "120px" });

// ── the table ─────────────────────────────────────────────────────────────

export const table = style({ width: "100%", borderCollapse: "collapse", fontSize: vars.textUi });
export const head = style({
  padding: "6px 8px", fontSize: vars.textMeta, fontWeight: "500", color: vars.muted, textAlign: "left", whiteSpace: "nowrap",
  borderBottom: `1px solid ${vars.line}`,
});
export const sortable = style({
  all: "unset", cursor: "pointer", color: "inherit",
  selectors: { "&:hover": { color: vars.text }, "&:focus-visible": { outline: `2px solid ${vars.accent}`, outlineOffset: "2px", borderRadius: "3px" } },
});
export const sorted = style({ color: vars.text });
export const cell = style({ padding: "6px 8px", borderBottom: `1px solid ${vars.line}`, verticalAlign: "middle" });
export const number = style({ textAlign: "right", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" });
export const strong = style({ fontWeight: "600" });
export const group = style({ cursor: "pointer", selectors: { "&:hover": { background: vars.hover } } });
export const name = style({ display: "flex", alignItems: "center", gap: "6px", minWidth: "0" });
export const nameText = style({ overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap", fontWeight: "500" });
export const chatLink = style({ color: "inherit", textDecoration: "none", selectors: { "&:hover": { textDecoration: "underline" } } });
export const toggle = style({ display: "inline-flex", color: vars.subtle, flex: "none", transition: `transform ${vars.dur} ${vars.easeOut}` });
export const open = style({ transform: "rotate(90deg)" });
export const meta = style({ color: vars.subtle, fontSize: vars.textMeta, whiteSpace: "nowrap" });
export const process = style({ color: vars.muted });
/** A process's row: its end shown as it is pointed at (or reached by the keyboard). */
export const row = style({});
export const endCell = style({ width: "32px", padding: "2px 4px", textAlign: "right" });
export const end = style({ opacity: 0, selectors: { [`${row}:hover &, &:focus-visible`]: { opacity: 1 } } });
export const processName = style({ paddingLeft: "30px" });
export const whose = style({ color: vars.muted, maxWidth: "200px", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" });
/** How much of the most this row uses, before the sorted column's figure. */
export const share = style({ display: "inline-block", width: "36px", height: "4px", borderRadius: "2px", background: vars.line, marginRight: "8px", verticalAlign: "middle", overflow: "hidden" });
export const shareFill = style({ display: "block", height: "100%", background: vars.accent });

export const foot = style({ display: "grid", gap: "4px", margin: "0", padding: "0", listStyle: "none", fontSize: vars.textMeta, color: vars.subtle });
export const empty = style({ margin: "0", padding: "28px 0", textAlign: "center", color: vars.muted });
export const tone = styleVariants({ cpu: { color: vars.accent }, memory: { color: vars.blue }, net: { color: vars.green }, disk: { color: vars.amber } });
export const scroll = style({ overflowX: "auto" });
