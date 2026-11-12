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
// 8. A round mark hung on another's corner (a picture's remove button): its centre on that corner's curve, reaching
//    past both its edges alike (`on_corner`); on the corner, not in it, so no corner of its own to keep concentric.
//
// still.fail's corner rule (mbui's ui/corners.mbt): what lies in a rounded container's corner stands as
// far from its two edges, and its own corner is concentric with the container's. Corners here are mbui's smooth ones
// (paint/smooth.mbt), laid out by the radius they are given and smoothed only
// as they are drawn (the user, 2026-11-03: 「平滑圆角只是在原有圆角的描述上做平滑」「边距应该是整数」): the web's
// `calc(inner + pad)` is `inner + pad` here and its `calc(outer - pad)` is `@ui.concentric(outer, pad)`, `outer - pad`;
// a circle or a capsule in a corner stands its half less than the corner in (`around`, `capsule_in`).
//
// Numbers here are not written by pages (the user, 2026-10-25: 「所有菜单浮窗的边距需要规范一下」).

///|
/// The corner of a container whose corner holds a whole circle (or a capsule) of `inner` radius `inset` in from both
/// edges: round with it, the container's corner its inset plus its radius (a
/// circle is not cut to the container: the container is drawn round it).
pub fn around(inset : Double, inner : Double) -> Double {
  (inset + inner)
}

///|
/// How far a round mark `size` across reaches past both edges of the box it hangs on, its centre on that box's corner
/// of `corner` where the curve turns 45° (@ui.smooth_middle): a picture's remove button
/// over its top right corner. `room`: half that box's shorter side, where its corner may be too round to be wholly
/// smooth (@ui.corner_middle: a circle's, a capsule's end).
pub fn on_corner(corner : Double, size : Double, room? : Double) -> Double {
  match room {
    Some(room) => size / 2.0 - @ui.corner_middle(corner, room)
    None => size / 2.0 - @ui.smooth_middle(corner)
  }
}

///|
/// A surface (align.ts surface): its padding, and the corner of what sits in it (a pill: its half height; a row: what it
/// has). Its own corner is the two together; what sits at its corner takes `inner` (the web's var(--panel-in)).
#derive(Eq, Debug)
pub(all) struct Surface {
  pad : Double
  inner : Double
}

///|
/// A surface `pad` in, what sits at its corners rounded `inner`.
pub fn surface(pad : Double, inner : Double) -> Surface {
  { pad, inner }
}

///|
/// Its own corner (surfaceCorner): what sits in it and its padding together, concentric.
pub fn Surface::corner(self : Surface) -> Double {
  @ui.concentric_out(self.inner, self.pad)
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
  route: 25.0,
  nav_row: 10.0,
}

///|
/// What a layer holds centred in it, both ways (centred: the web's by translate, placed absolutely).
// kept across runs: a value (no field of it changes)
pub let centred : @ui.Style = @ui.css("w=Full h=Full align=ACenter justify=JCenter")

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
/// Words in a small panel have room of their own (2026-10-15): the panel is padded only as far as what has a ground
/// (rows, buttons) stands from its edge. A small panel is a list of rows floating over the page, denser than a card
/// (2026-10-25 用户：「菜单的 hover 后背景距离边上是不是太远了」): its rows' grounds 6 from its edges, as a menu's
/// highlight hugs it (the web's PANEL_PAD, the systems' menus), its corner theirs (r_menu: concentric with them), its
/// words 16 in (text_in more), as the web's are.
pub let panel_pad : Double = 6.0

///|
/// Its words stand in by a row's own padding more (TEXT_IN), so a card's words and a menu's rows' words are on one
/// line, panel_pad + text_in from its edge (the ladder's inset: what stands on a row's words round by its small step,
/// 18 less 8, 10).
pub let text_in : Double = 16.0

///|
/// A small panel's buttons: pills this high, its icon buttons circles as wide (PANEL_PILL).
pub let panel_pill : Double = 24.0

///|
/// The corner of what sits in a small panel of corner `outer`, its padding in (smallPanelInner): concentric.
pub fn small_panel_inner(outer : Double) -> Double {
  @ui.concentric(outer, panel_pad)
}
