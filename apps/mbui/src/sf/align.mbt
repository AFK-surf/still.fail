// How things line up, said once (the web's web/ui/src/styles/align.ts): every surface, every ground that reaches past
// its words, every column another lines up with is one of these, so no page writes a negative margin or works out a
// corner by hand. The cases, as the web has them:
//
// 1. A surface and what sits at its corners (menus, panels, dialogs, ⌘K, notices, cards, floating bars): it says its
//    padding and the inner corner of what sits in it; its own corner is the two together (concentric), and what sits
//    at a corner takes its `inner`.
// 2. A ground reaching past its words across (a list's rows wider than the page's column, a text button, a field drawn
//    as text, a name renamed in place): `bleed_x(x)`, its padding and the margin taking it back one number.
// 3. The same up and down (a control in a line of text that must not make the line taller): `bleed_y(y)`.
// 4. Lined up with another's column (a message's head with the avatars', a count under the menu button above it): the
//    column's owner says where it is (`columns`), the other reads it; no copied numbers.
// 5. Centred while placed over another (a layer): `centred`, by its alignment, not a margin.
// 6. Laid over one another on purpose (faces in a stack): `overlap(x)`.
// 7. Room above taken back by a negative margin: never; the parent's room is changed instead.
//
// still.fail's corner rule (docs/ui-panels.md, "所有带圆角的东西"): what lies in a rounded container's corner stands as
// far from its two edges, and its own corner is concentric with the container's. Corners here are mbui's smooth ones
// (the web's superellipse(1.5) with --corner-scale 1.25, Android's Corners.kt Smooth: drawn a quarter larger than they
// are given), so the web's `calc(inner + pad)` is `inner + pad / 1.25` here and its `calc(outer - pad)` is
// `@ui.concentric(outer, pad)`. A circle or a capsule in a corner is round and not smoothed: the container is drawn
// round it (`around`).

///|
/// How much longer a smooth corner (Corners.kt Smooth, the web's superellipse(1.5): --corner-scale) is drawn than the
/// radius it is given: Corners.kt SMOOTH_SCALE.
pub let smooth_scale : Double = 1.25

///|
/// The corner of a smooth box round one of corner `inner`, `inset` in from its edges (align.ts surfaceCorner, Corners.kt
/// concentricOut: the inset taken a quarter smaller, as Smooth draws a corner a quarter larger than it is given).
pub fn concentric_out(inner : Double, inset : Double) -> Double {
  inner + inset / smooth_scale
}

///|
/// The corner of what sits `pad` in from a smooth corner `outer` (the web's `calc(outer - pad)`, smallPanelInner): concentric
/// with it.
pub fn inner_corner(outer : Double, pad : Double) -> Double {
  @ui.concentric(outer, pad)
}

///|
/// The corner of a container whose corner holds a whole circle (or a capsule) of `inner` radius `inset` in from both
/// edges: round with it, the container's corner its inset plus its radius (a circle is not cut to the container: the
/// container is drawn round it).
pub fn around(inset : Double, inner : Double) -> Double {
  inset + inner
}

///|
/// A surface (align.ts surface): its padding, and the corner of what sits in it (a pill: its half height; a row: what it
/// has). Its own corner is the two together; what sits at its corner takes `inner` (the web's var(--panel-in)).
pub(all) struct Surface {
  pad : Double
  inner : Double
} derive(Eq, Show)

///|
/// A surface `pad` in, what sits at its corners rounded `inner`.
pub fn surface(pad : Double, inner : Double) -> Surface {
  { pad, inner }
}

///|
/// Its own corner (surfaceCorner): what sits in it and its padding together, concentric.
pub fn Surface::corner(self : Surface) -> Double {
  concentric_out(self.inner, self.pad)
}

///|
/// Its own corner as a style's.
pub fn Surface::radius(self : Surface) -> @ui.Radius {
  rounded(self.corner())
}

///|
/// Its padding and its corner (surface's padding and borderRadius).
pub fn Surface::style(self : Surface) -> @ui.Style {
  @ui.style(p=room(self.pad), radius=self.radius())
}

///|
/// What sits at its corner, as a style's corner (inner).
pub fn Surface::inner_radius(self : Surface) -> @ui.Radius {
  rounded(self.inner)
}

///|
/// The corner of what sits in `s`, or `fallback` where it stands in none (innerOr).
pub fn inner_or(s : Surface?, fallback : Double) -> Double {
  match s {
    Some(s) => s.inner
    None => fallback
  }
}

///|
/// A surface's corner as a value, for one whose padding is drawn otherwise (rows reaching its edge, a bar on top):
/// surfaceCorner.
pub fn surface_corner(pad : Double, inner : Double) -> Double {
  concentric_out(inner, pad)
}

///|
/// The corner a surface's own corner leaves for what sits `pad` in from it when that is a pill `height` high (pillInner):
/// the surface's corner the pill's half height and the pad together, round as the pill is, so a pill too short for a
/// larger corner never leaves a crescent beside it.
pub fn pill_inner(pad : Double, height : Double) -> Double {
  @ui.concentric(around(pad, height / 2.0), pad)
}

///|
/// A ground reaching `x` past its words on either side: they stand where they would without it (bleedX).
pub fn bleed_x(x : Double) -> @ui.Style {
  @ui.style(px=room(x), mx=room(-x))
}

///|
/// The same at its start only, its end where it is (bleedStart).
pub fn bleed_start(x : Double) -> @ui.Style {
  @ui.style(pl=room(x), ml=room(-x))
}

///|
/// The same at its end only (bleedEnd).
pub fn bleed_end(x : Double) -> @ui.Style {
  @ui.style(pr=room(x), mr=room(-x))
}

///|
/// A ground reaching `y` above and below: the line it sits in no taller for it (bleedY).
pub fn bleed_y(y : Double) -> @ui.Style {
  @ui.style(py=room(y), my=room(-y))
}

///|
/// Taller than its line by `extra` without making it taller: a control `extra` higher than the words beside it (inLine).
pub fn in_line(extra : Double) -> @ui.Style {
  let half = extra / 2.0
  @ui.style(my=room(-half))
}

///|
/// The columns others line up with, each said once by what makes it (case 4): how far its words stand in from its box,
/// or how far a part reaches out into the room before the column (align.ts columns).
pub(all) struct Columns {
  /// the model control's words stand in by its padding (10) and border (1): words above or below it line up with them
  model_control : Double
  /// a chat's avatars stand in the list's padding (40), as far from its edge as from the name: 11 + 18 avatar
  avatar : Double
  /// on a narrow screen, in its 6 padding: 3 out
  avatar_narrow : Double
  /// an agent's activity line: its 24 avatar and the 11 beside it, out in the list's padding
  activity : Double
  activity_narrow : Double
  /// where a message went or came from, under an inline head: from the row's start (its avatar's 14 and 11 after)
  route : Double
  /// the sidebar's rows: their padding, which a part at a row's end reaches into (the count under the menu button)
  nav_row : Double
}

///|
// kept across runs: a table, never written
pub let columns : Columns = {
  model_control: 11.0,
  avatar: 29.0,
  avatar_narrow: 3.0,
  activity: 35.0,
  activity_narrow: 9.0,
  route: 25.0,
  nav_row: 10.0,
}

///|
/// Moved back by a column's offset: a part that starts in the column before it (intoColumn).
pub fn into_column(offset : Double) -> @ui.Style {
  @ui.style(ml=room(-offset))
}

///|
/// What a layer holds centred in it, both ways (centred: the web's by translate, placed absolutely).
// kept across runs: a value (no field of it changes)
pub let centred : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

///|
/// Centred across only (centredX).
// kept across runs: a value (no field of it changes)
pub let centred_x : @ui.Style = @ui.css("w=Full align=ACenter")

///|
/// Centred up and down only (centredY).
// kept across runs: a value (no field of it changes)
pub let centred_y : @ui.Style = @ui.css("h=Full justify=JCenter")

///|
/// Each after the first laid `x` over the one before (faces in a stack): overlap.
pub fn overlap(x : Double) -> @ui.Style {
  @ui.style(ml=room(-x))
}

///|
/// Reaching `x` past its box on either side, its own room as it was (a list whose rows carry the padding): outset.
pub fn outset(x : Double) -> @ui.Style {
  @ui.style(mx=room(-x))
}

///|
pub fn outset_start(x : Double) -> @ui.Style {
  @ui.style(ml=room(-x))
}

///|
pub fn outset_end(x : Double) -> @ui.Style {
  @ui.style(mr=room(-x))
}

///|
pub fn outset_top(y : Double) -> @ui.Style {
  @ui.style(mt=room(-y))
}

///|
pub fn outset_bottom(y : Double) -> @ui.Style {
  @ui.style(mb=room(-y))
}

///|
/// Drawn `x` larger on every side than the room it takes (art with air round it): oversize.
pub fn oversize(x : Double) -> @ui.Style {
  @ui.style(m=room(-x))
}

///|
/// `x` taken away, for a value that needs it inside another (neg).
pub fn neg(x : Double) -> Double {
  -x
}

///|
/// A row in surface `s` reaching `x` into its padding, its words where the surface's other words are (case 2 inside
/// case 1): as far from the surface's sides as from its top (`first`) or foot (`last`), its corner the surface's inner
/// one and that distance together, concentric, whatever the surface's padding is (edgeRow).
pub fn edge_row(s : Surface, x : Double, first? : Bool = false, last? : Bool = false) -> @ui.Style {
  let row = @ui.style(px=room(x), mx=room(-x), radius=rounded(concentric_out(s.inner, x)))
  let row = if first { row.then(@ui.style(mt=room(-x))) } else { row }
  if last {
    row.then(@ui.style(mb=room(-x)))
  } else {
    row
  }
}

///|
/// Words in a small panel have room of their own (2026-10-15): the panel is padded only as far as what has a ground
/// (rows, buttons) stands from its edge: the corner ladder's inset (tokens.mbt corner_ladder: a small panel is a card
/// of the ladder's, its rows as a list card's).
pub let panel_pad : Double = corner_inset

///|
/// Its words stand in by a row's own padding more (TEXT_IN), so a card's words and a menu's rows' words are on one
/// line, panel_pad + text_in from its edge (card_pad, as a page's card's).
pub let text_in : Double = 10.0

///|
/// A small panel's buttons: pills this high, its icon buttons circles as wide (PANEL_PILL).
pub let panel_pill : Double = 24.0

///|
/// The corner of what sits in a small panel of corner `outer`, its padding in (smallPanelInner): concentric.
pub fn small_panel_inner(outer : Double) -> Double {
  inner_corner(outer, panel_pad)
}
