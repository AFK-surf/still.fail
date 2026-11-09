// How things line up, said once: every surface, every ground that reaches past its words, every column another lines
// up with is one of these, so no style writes a negative margin or works out a corner by hand (scripts/check.sh: "no
// hand-written negative margins"). The cases, as the web had them (2026-10-15):
//
// 1. A surface and what sits at its corners (menus, panels, dialogs, ⌘K, notices, cards, floating bars): it says its
//    padding and the inner corner of what sits in it; its own corner is the two together (concentric), and what sits
//    at a corner takes `inner`.
// 2. A ground reaching past its words across (a list's rows wider than the page's column, a text button, a field drawn
//    as text, a name renamed in place): `bleedX(x)`, its padding and the margin taking it back one number.
// 3. The same up and down (a control in a line of text that must not make the line taller): `bleedY(y)`.
// 4. Lined up with another's column (a message's head with the avatars', a count under the menu button above it): the
//    column's owner says where it is (`column`), the other reads it; no copied numbers.
// 5. Centred while placed absolutely: `centred`, by translate, not a margin.
// 6. Laid over one another on purpose (faces in a stack): `overlap(x)`.
// 7. Room above taken back by a negative margin: never; the parent's room is changed instead.

const px = (v: number | string) => (typeof v === "number" ? `${v}px` : v);

/** The padding of the surface something sits in, and the corner of what sits in it (the popover's names, kept). */
const PAD = "--panel-pad";
export const IN = "--panel-in";
const SHAPE = "--panel-shape";
/** What sits at a surface's corner: its corner, concentric with the surface's. */
export const inner = `var(${IN})`;

/**
 * A surface: `pad` its padding, `innerCorner` the corner of what sits in it (a pill: its half height; a row: what it
 * has). Its own corner is the two together; `shape` its corners' shape (round when not said), what sits in it the same.
 */
export function surface(pad: number | string, innerCorner: number | string, shape?: string) {
  return {
    vars: { [PAD]: px(pad), [IN]: px(innerCorner), ...(shape ? { [SHAPE]: shape } : {}) },
    padding: `var(${PAD})`,
    borderRadius: `calc(var(${IN}) + var(${PAD}))`,
    ...(shape ? { cornerShape: `var(${SHAPE})` } : {}),
  } as const;
}

/** A ground reaching `x` past its words on either side: they stand where they would without it. */
export function bleedX(x: number | string) {
  return { paddingInline: px(x), marginInline: `calc(-1 * ${px(x)})` } as const;
}
/** A ground reaching `y` above and below: the line it sits in no taller for it. */
function bleedY(y: number | string) {
  return { paddingBlock: px(y), marginBlock: `calc(-1 * ${px(y)})` } as const;
}

/** A column another lines up with: its owner sets `name` to where it starts; the other reads `column(name)`. */
export const column = (name: string) => `var(--col-${name})`;

/** Centred on its containing box while placed absolutely. */
export const centred = { left: "50%", top: "50%", translate: "-50% -50%" } as const;

/** Each after the first laid `x` over the one before (faces in a stack). */
export function overlap(x: number | string) {
  return { marginInlineStart: `calc(-1 * ${px(x)})` } as const;
}

/** Reaching `x` past its box on either side, its own room as it was (a list whose rows carry the padding). */
export function outset(x: number | string) {
  return { marginInline: `calc(-1 * ${px(x)})` } as const;
}
export const outsetStart = (x: number | string) => ({ marginInlineStart: `calc(-1 * ${px(x)})` } as const);
/** `x` taken away, for a value that needs it inside another (`max(neg(12), …)`). */
export const neg = (x: number | string) => `calc(-1 * ${px(x)})`;

/**
 * The columns others line up with, each said once by what makes it (case 4): how far its words stand in from its
 * box, or how far a part reaches out into the room before the column.
 */
export const columns = {
  /** The model control's words stand in by its padding (10) and border (1): text above or below it lines up with them. */
  modelControl: 11,
  /** A chat's avatars stand in the list's padding (40), as far from its edge as from the name: 11 + 18 avatar. */
  avatar: 29,
  /** On a narrow screen, in its 6px padding: 3 out. */
  avatarNarrow: 3,
  /** An agent's activity line: its avatar where a message's is, the line's 6px padding before it. */
  activity: 35,
  activityNarrow: 9,
  /** Where a message went or came from, under an inline head: from the row's start (its avatar's 14 and 11 after). */
  route: 25,
  /** The sidebar's rows: their padding, which a part at a row's end reaches into (the count under the menu button). */
  navRow: 10,
} as const;

/**
 * Words in a small panel have room of their own (2026-10-15): the panel is padded only as far as what has a ground
 * (rows, buttons) stands from its edge (6, as a menu); its words stand in by a row's own padding more (TEXT_IN),
 * so a card's words and a menu's rows' words are on one line, `PAD + TEXT_IN` from the edge.
 */
export const PANEL_PAD = 6;
export const TEXT_IN = 10;
/** A small panel's buttons: pills this high (ui.css.ts panelButton, panelIcon). */
export const PANEL_PILL = 24;
/** A block of words in a small panel: in by a row's padding, and a little room above and below. */
export const panelText = { paddingInline: px(TEXT_IN) } as const;
