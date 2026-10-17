// What another app shares, its panel on a wide screen (ShareIn.tsx): ⌘K's (Switcher.css.ts), high on the window. Its
// words stand where a dialog's do (24 in); the rows' ground reaches to 12 from its edge, and the composer at its foot is
// a pill 12 in from it, so the panel's corner is from that pill (12 + its half height, align.ts pillInner), as ⌘K's is
// from its rows; the send button in the pill is 4 in from it, its corner the pill's less that.
import { globalStyle, style } from "@vanilla-extract/css";
import { vars } from "@stillfail/ui/styles/tokens.css.ts";
import { inner, innerShape, outset } from "@stillfail/ui/styles/align.ts";
import { DIALOG_PAD } from "@stillfail/ui/parts.css.ts";
import { switcher } from "./Switcher.css.ts";

const EDGE = 12;
/** The composer's height (⌘K's rows', which its corner is from), and its send button's, 4 in from it. */
const COMPOSER = 38;
const SEND = 30;
const SEND_IN = (COMPOSER - SEND) / 2;
/** A row's words in from its ground: a dialog's 24 from the panel's edge. */
const ROW_IN = DIALOG_PAD - EDGE;

const ellipsis = { minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" } as const;

/** ⌘K's panel (its ground, its corner from a 38 high pill 12 in, where it stands), a little narrower and taller. */
export const panel = style([switcher, { width: "min(520px, calc(100vw - 32px))", maxHeight: "min(600px, 78vh)" }]);

/** What is shared: a mark of what it is (a link, some text), its title over it, on the rows' line. */
export const what = style({ display: "flex", alignItems: "flex-start", gap: "10px", flex: "none", padding: `${ROW_IN}px ${ROW_IN}px 6px` });
export const whatMark = style({ flex: "none", display: "grid", placeItems: "center", width: 20, height: 20, color: vars.muted });
export const whatText = style({ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 2 });
export const whatTitle = style({ ...ellipsis, fontSize: vars.textUi, fontWeight: 600, lineHeight: "20px" });
/** The link or the text: two lines of it (three, in the text's ink, when it is all there is), cut short. */
export const whatSource = style({
  fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted, overflowWrap: "anywhere",
  display: "-webkit-box", WebkitBoxOrient: "vertical", WebkitLineClamp: "2", overflow: "hidden",
  selectors: { "&[data-alone]": { fontSize: vars.textUi, lineHeight: "20px", color: vars.text, WebkitLineClamp: "3" } },
});

/** A few words over a part of the list (发到, 新 chat 开在), on the rows' line. */
export const section = style({ margin: `10px ${ROW_IN}px 4px`, fontSize: vars.textMeta, color: vars.muted });

/** 发到, and at its end 搜索 (取消 while searching): quiet words to press. */
export const labelRow = style({ display: "flex", alignItems: "baseline", justifyContent: "space-between", gap: 12 });
export const search = style({
  flex: "none", padding: 0, border: 0, background: "none", color: vars.muted, font: "inherit", cursor: "pointer",
  selectors: { "&:hover": { color: vars.text } },
});

/** The chats and the rest: reaching out to the panel's edge, as ⌘K's do, its scrollbar beside the rows. */
export const list = style({ flex: 1, minHeight: 0, overflowY: "auto", ...outset(EDGE), padding: `0 ${EDGE}px 4px` });
export const none = style({ margin: `8px ${ROW_IN}px`, fontSize: vars.textUi, color: vars.muted });
export const row = style({
  display: "flex", alignItems: "center", gap: 10, width: "100%", minHeight: COMPOSER, padding: `8px ${ROW_IN}px`, border: 0,
  borderRadius: inner, cornerShape: innerShape, background: "none", color: vars.text, font: "inherit", fontSize: vars.textUi, textAlign: "left",
  cursor: "pointer",
  selectors: {
    "&:hover": { background: `color-mix(in srgb, ${vars.text} 5%, transparent)` },
    // Where it goes: lit as a menu's row is, and checked.
    '&[aria-pressed="true"]': { background: `color-mix(in srgb, ${vars.text} 7%, transparent)` },
    "&:focus-visible": { outline: `2px solid ${vars.fieldFocus}`, outlineOffset: "-2px" },
  },
});
export const picture = style({ flex: "none", display: "grid", placeItems: "center", width: 20, height: 20, color: vars.muted });
export const rowText = style({ flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 2 });
export const rowTitle = style({ ...ellipsis, lineHeight: "20px" });
export const rowLine = style({ ...ellipsis, fontSize: vars.textMeta, lineHeight: "18px", color: vars.muted });
export const rowMeta = style({ flex: "none", fontSize: vars.textMeta, color: vars.muted });
export const check = style({ flex: "none", color: vars.accent });

/** What the person adds and send, at the foot: a pill 12 in from the panel's corners, its corner theirs. */
export const composer = style({
  flex: "none", display: "flex", alignItems: "center", gap: 4, height: COMPOSER, boxSizing: "border-box", marginTop: 8,
  padding: `0 ${SEND_IN - 1}px 0 0`, border: `1px solid ${vars.lineStrong}`, borderRadius: inner, cornerShape: innerShape,
  transition: `border-color ${vars.dur} ${vars.easeOut}`,
  selectors: { "&:hover, &:focus-within": { borderColor: vars.fieldHover } },
});
export const field = style({
  flex: 1, minWidth: 0, height: "100%", padding: `0 8px 0 ${ROW_IN - 1}px`, border: 0, outline: "none", background: "none",
  color: vars.text, font: "inherit", fontSize: vars.textInput,
  selectors: { "&::placeholder": { color: vars.subtle } },
});
/** Send: round, as the chat's composer's is; its corner the pill's less the 4 it stands in by. */
export const send = style({
  flex: "none", display: "grid", placeItems: "center", width: SEND, height: SEND, padding: 0, border: 0,
  borderRadius: `calc(${inner} - ${SEND_IN}px)`, cornerShape: innerShape,
  background: vars.text, color: vars.canvas, cursor: "pointer", transition: `background ${vars.dur} ${vars.easeOut}`,
  selectors: {
    "&:hover:not(:disabled)": { background: `color-mix(in srgb, ${vars.text} 82%, ${vars.canvas})` },
    "&:disabled": { background: `color-mix(in srgb, ${vars.text} 18%, ${vars.raised})`, color: vars.raised, cursor: "default" },
  },
});
globalStyle(`${list} > ${row} + ${row}`, { marginTop: 2 });
