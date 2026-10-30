// still.fail's design system (ember web/ui: styles/tokens.css.ts, the values
// in web/src/styles/global.css.ts, the phone's in mobile/styles/root.css.ts),
// for mbui: its colours, type and measures, said once here, so a view built
// with them looks as still.fail's own pages do.
//
// One palette on every screen and with either input (the phone's, as the Android app: warm paper, white cards on it,
// its own greys and tones), light and dark: the screen says how things are laid out and the native input how large
// they are, neither what colour they are. `begin` picks light or dark each frame from the appearance set. The web's
// own tones (a white page, grey cards on it) stay only where the message's Markdown has them on every screen
// (markdown.mbt `web`).

///|
/// The colours a view reads (the web's names: `text` is --text, `bg` the
/// page's ground, the warm paper; `card` and `canvas` what stands on it, white).
pub(all) struct Palette {
  bg : Int64
  canvas : Int64
  /// what floats over the page (a bar, a capsule)
  raised : Int64
  sidebar : Int64
  list : Int64
  text : Int64
  muted : Int64
  subtle : Int64
  /// what is drawn to be seen with nothing in it (a line, a gauge's empty cell, a placeholder's block, a grip): the
  /// ink at an opacity, as far off whatever it lies on (mbui's Theme `line`)
  line : Int64
  line_strong : Int64
  hover : Int64
  selected : Int64
  paper : Int64
  accent : Int64
  accent_text : Int64
  accent_bg : Int64
  green : Int64
  /// green and amber as words, dark enough to read on paper (Theme.kt greenInk, warnInk; the web's --green,
  /// --amber)
  green_ink : Int64
  warn_ink : Int64
  red : Int64
  red_bg : Int64
  /// the grounds of a pill in a tone (parts.css.ts pill: --green-bg, --blue-bg, --amber-bg; the amber's ink is
  /// warn_ink), as red_bg and accent_bg: the tone's ink at an opacity (tone_light, tone_dark), so each stands a step
  /// off whatever it lies on, the page, a card, a menu, a selected row, as neutral_bg does
  green_bg : Int64
  blue_bg : Int64
  amber_bg : Int64
  /// a station online (--online: a status dot, parts.css.ts statusDot)
  online : Int64
  /// a quiet ground under what is in it (a pill's, a bubble's): the ink at an opacity, a step off whatever it lies on
  neutral_bg : Int64
  overlay : Int64
  shadow : Int64
  primary : Int64
  primary_hover : Int64
  on_primary : Int64
  /// a card's ground on the page
  card : Int64
  /// what sits a step apart on a card: a command's box (Theme.kt surface2, root.css.ts --m-surface2)
  card2 : Int64
  /// the narrow screen's quiet button
  chip : Int64
  /// links (--blue)
  blue : Int64
  /// inline code's words (--code-inline), a code block's ground (the text
  /// at 4% in the canvas)
  code_ink : Int64
  code_ground : Int64
}

///|
/// Six roles of type, each a size with its line, and the three weights
/// (400; 500 to stand out; 600 for titles).
pub(all) struct Type {
  caption : Double
  caption_line : Double
  meta : Double
  meta_line : Double
  ui : Double
  ui_line : Double
  body : Double
  body_line : Double
  title : Double
  title_line : Double
  heading : Double
  heading_line : Double
  display : Double
  /// what a person writes, as it is typed in the composer, as it flies when sent and as it is read in its message
  /// (msgPlain, PersonWords): set alike in all three, so that sending it only moves it (SendText.kt: "the field,
  /// flying words and own messages share their typography and line breaks"; the breaks: the viewer's bubble as wide as
  /// the composer sets them, sfpages message.mbt mine_most); the body's size on its line, a phone's on a message's
  /// line as the agent's Markdown beside it (Chat.kt: 15 on 24.75). Not the web's 16 for what is typed on a phone,
  /// which is there so that iOS's browser does not zoom into it. In numbers, where a field takes them:
  /// Ctx::style_size.
  words : @ui.TextStyle
}

///|
/// A round control standing in a field's capsule (the composer's ＋ and send: mPlus, mSend; attachBtn, sendBtn): how
/// wide it shows and its glyph's size (a finger reaches it from round it as it reaches any target smaller than the
/// system's least: @ui's press_reach).
pub(all) struct Round {
  side : Double
  glyph : Double
}

///|
pub(all) struct Theme {
  dark : Bool
  /// the native input is touch (native_input): the sizes (words, rows, controls, what a press reaches) a finger's, on
  /// every screen; keyboard and mouse's on every screen else, a narrow window's too
  touch : Bool
  p : Palette
  t : Type
  /// what a row is on this screen (Rows)
  rows : Rows
  /// how tall a control is at least (a field, a select): the web's 36 with keyboard and mouse; with touch a finger's 44,
  /// what a press needs
  control_h : Double
  /// what a page's bar of keys is on this screen (Bars)
  bars : Bars
  /// the round controls standing in a field's capsule (Round)
  round : Round
  /// what a list's item is on this screen (Items)
  items : Items
  /// what a chats' list is on this screen (ChatList: its rows' sizes and density, by the native input alone): not
  /// `items`, a list's one-line row (files, picks), but the chats' own anatomy (two lines, faces, the state line, the
  /// days' headings, its panes' motion)
  chat_list : ChatList
}

///|
/// A page's bar of keys (page_bar.mbt) on the screen in force: its keys round, `key` across with a `icon` icon, its
/// capsule `field` high. The web's and the phone's alike (PreviewBar's iconBtn 28, its icons 14, previewAddress 30;
/// Preview.kt the same): a finger reaches a key from round it (press_reach), so a phone's are drawn no larger.
pub(all) struct Bars {
  key : Double
  icon : Double
  field : Double
}

///|
/// A row's roles on the screen in force (docs/architecture.md, the same on every screen and what differs): how high it
/// is at least (the items' least: one height for a row by the native input), its title's words and its note's, a
/// tick's box, a short field and a switch in it. Touch's: a finger's (the phone's mRowTitle, its body's 15, the
/// scale's Lg on 21, its mRowNote 13; a box 22, a field 72 by 36, a switch 44 by 26, its mSwitch); keyboard and
/// mouse's: a list row's (the web's SwitchRow title, 13 on 20, its note 12; a box 18, a field 52 by 28, a switch 36
/// by 22).
pub(all) struct Rows {
  /// a row of a picker or a menu in a small panel at least: keyboard and mouse's 34 (a menu's row), a finger's 44
  pick : Double
  title : @ui.TextStyle
  /// what is said under a row's title (its note), muted
  note : @ui.TextStyle
  check : Double
  /// a short field in a row (a number typed: a page's width)
  field_w : @ui.Len
  field_h : @ui.Len
  check_corner : Double
  switch_w : Double
  switch_h : Double
}

///|
/// A list's item on the screen in force (a folder's entries, the folders pinned): how high it is at least, the one
/// least row height of every row (rule 2's room: 44 with touch, 36 with keyboard and mouse, the user, 2026-10-27), its
/// name's words and what is said of it (its size, its time: muted), its kind's mark. Touch's: a finger's (the phone's
/// mRow: its name the body's 15 on 20, mMeta 12 on 16, the mark 22); keyboard and mouse's: the web's Drive row's (its
/// name 13, its meta 12, KindIcon 20).
pub(all) struct Items {
  least : Double
  name : @ui.TextStyle
  meta : @ui.TextStyle
  mark : Double
  /// a line as high as the mark (L6 20, L7 22): words with the mark in the middle of their first line
  mark_line : @ui.Leading
}

// ---------------------------------------------------------------------------
// Measures (docs/ui-panels.md; styles/align.ts, pages.css.ts)

// (a small panel's padding, its words' room and its pills: align.mbt panel_pad, text_in, panel_pill)

///|
/// The corner ladder (docs/ui-panels.md「圆角阶梯」): the few corners nested things are round by, outermost first, each
/// the one before it concentric `corner_inset` in (smooth.mbt concentric: that over 1.25 less): a pane of the frame
/// (the tape's panels laid out Medium, a dialog), a card (a page's card, a sheet, the composer), a row or a block on a
/// card, a small block on a row. What has a ground and lies in a container's corner stands `corner_inset` in from both
/// its edges and is round by the next step (mbui works its corner out: corners.mbt), or is a capsule or a circle `its
/// half less than the container's corner` in. The theme's (Theme::corner_ladder): screen tests hold every corner with
/// something in it, and what is there, to these.
pub let pane_corner : Double = 34.0

///|
pub let corner_inset : Double = 10.0

///|
pub let card_corner : Double = @ui.concentric(pane_corner, corner_inset)

///|
pub let row_corner : Double = @ui.concentric(card_corner, corner_inset)

///|
pub let small_corner : Double = @ui.concentric(row_corner, corner_inset)

///|
// kept across runs: a value (no field of it changes)
pub let corner_ladder : Array[Double] = [pane_corner, card_corner, r_menu, row_corner, small_corner]

///|
/// How far apart two things that light up under the hand stand at least (Theme::lit_apart, the spacing rules): the
/// web's sidebar rows (Sidebar.css.ts navRow, `& + &` 2 over the one before), so two lit grounds never read as one.
pub let lit_apart : Double = 2.0

///|
/// How far in from the sides of what holds it a row that lights up under the hand stands, where it runs across it
/// (Theme::lit_reach, the spacing rules' 7): a small panel's padding, so a menu's rows, a list card's and a card of
/// options' alike (docs/ui-panels.md 列表卡; the user, 2026-10-26: a card of options' grounds 10 in, 「6px 就差不多了」).
pub let lit_reach : Double = panel_pad

///|
/// What the corner rule may make of what lies in a container's corner to be concentric with it (docs/ui-panels.md 圆角
/// 阶梯, 适应范围; the theme's Theme::corner_fit): a corner 6 at least (squarer reads as square) and the ladder's
/// outermost at most, standing 4 to 16 from the container's edges. The outermost container is the window, its corner
/// the system's (@ui.window_corner: a Mac's 16, Windows 11's 8, square filling the screen): what none of these makes
/// concentric with what it lies in stands as it would alone, the ladder's own.
// kept across runs: a value (no field of it changes)
pub let corner_fit : @ui.CornerFit = { least: 6.0, most: pane_corner, near: 4.0, far: 16.0 }

///|
/// The corner of the tape's panels (laid out Medium) where they stand alone: less round than the ladder's pane corner a
/// dialog has (the user, 2026-10-25: 中屏的页面圆角想办法搞小一点点, 34 to 30; 2026-10-26: 最好能把这个中屏的页面圆角搞小
/// 点点, 30 to 28). Linked (tape_corners), what lies in their corners follows it there (a composer, a bar's buttons, the
/// rail's grounds), round as that makes it; what is in the middle of a page keeps the ladder's. A composer's capsule 48
/// high is as high as stands concentric in it (28 less its half, 24: corner_fit's nearest, 4), and a finger's comes down
/// to it (foot_capsule_h); opened, it is a card less round than the ladder's there (pane_foot_corner: 24.8, 4 in).
pub let tape_corner : Double = 28.0

///|
/// The tape's one line (laid out Medium): how far under its panels' tops their first row's round buttons stand, as far
/// as a bar's (32 across) are concentric with the tape's corner (28 less their half, 12): every bar of the tape
/// (tape_bar_over) and the sidebar's first row on it, whatever a panel's own corners are (the user, 2026-10-25: a page's
/// bar and the sidebar's first row each where it stood alone, not on one line). The tape's own place for its own
/// corner (corner_fit, for what follows a corner it does not choose: a window's).
pub let tape_line : Double = capsule_in(tape_corner, 32.0)

///|
/// Whether a corner `k` round is one corner_fit lets what lies in a corner have.
fn corner_fits(k : Double) -> Bool {
  k >= corner_fit.least - 0.5 && k <= corner_fit.most + 0.5
}

///|
/// Whether `d` from a container's edges is a place corner_fit lets what lies in its corner stand.
fn place_fits(d : Double) -> Bool {
  d >= corner_fit.near - 0.5 && d <= corner_fit.far + 0.5
}

///|
/// How far from the window's edges what stands along them does (the tape's panels, the closed bar: shell.css.ts dock's
/// 6).
pub let window_in : Double = 6.0

///|
/// The corner of what stands `window_in` from the window's edges in its corners (the tape's panels where they stand at
/// its edge, the closed bar), linked to the window's (@ui.CornerOf: the window's less that where corner_fit lets it be
/// so, a Mac's 16: 11.2), else `alone` (a square window, Windows 11's 8: too square for it).
pub fn window_follow(alone : Double) -> @ui.CornerOf {
  Follow(Window, window_in, alone)
}

///|
/// The corner of the tape's panels (laid out Medium) where they stand at the window's edge, linked to the window's,
/// else the tape's corner, as they stand alone (tape_corners: a panel's other corners the tape's).
pub let tape_edge : @ui.CornerOf = window_follow(tape_corner)

///|
/// A panel of the tape's corners (top left, top right, bottom right, bottom left), each linked to the one it is in: on
/// the side it stands at the window's edge when it is in use (`left`: the sidebar's; `right`: the side panel's, the
/// page's with none open beside it) the window's (tape_edge); the others, never in the window's corners, the tape's
/// corner. Whether the panel is in use now or on its way over: where it will be.
pub fn tape_corners(left~ : Bool, right~ : Bool) -> FixedArray[@ui.CornerOf] {
  // (along a screen whose corners the host says, an iPhone Duo's: concentric with them, so the screen cuts none of a
  // panel's line, the user 2026-10-27: native_bars.mbt)
  // (each corner the screen's there: an iPhone Duo's outer screen square along its hinge)
  let edge = fn(k : Int) -> @ui.CornerOf {
    if native_card_corner() > 0.0 {
      Own(native_card_corner_at(k))
    } else {
      tape_edge
    }
  }
  let l = if left { edge(0) } else { Own(tape_corner) }
  let r = if right { edge(1) } else { Own(tape_corner) }
  // (their foot corners away from the screen's edges, beside the system's action at the column's foot: the one the
  // composer stands concentric in on its line, native_foot_set)
  let foot : @ui.CornerOf = match native_foot_corner() {
    Some(k) => Own(k)
    None => Own(tape_corner)
  }
  [l, r, if right { edge(2) } else { foot }, if left { edge(3) } else { foot }]
}

///|
/// A panel of the tape's corners `k` (tape_corners: top left, then round it) as a style's corner, each linked to where
/// it comes from: the tape's panels' alone (frame.mbt), their corners at the window's edge its, the others the tape's.
pub fn corners_radius(k : FixedArray[@ui.CornerOf]) -> @ui.Radius {
  // det-ok(corners-each): the tape's panels: their corners at the window's edge follow the window's, the others the tape's 28 (the user, 2026-10-25, 2026-10-26)
  LinkedEach(k[0], k[1], k[2], k[3])
}

///|
/// Corners `k`'s radii now (top left, then round it).
pub fn corner_radii(k : FixedArray[@ui.CornerOf]) -> FixedArray[Double] {
  k.map(fn(c) { c.radius() })
}

///|
/// The sidebar's panel on the tape: at the window's left edge in use.
pub fn tape_side_corners() -> FixedArray[@ui.CornerOf] {
  tape_corners(left=true, right=false)
}

///|
/// Where a capsule `height` high stands in a corner `corner` round: as far in as makes it concentric (capsule_in) where
/// corner_fit lets it stand there, else `alone`, where it stands with no corner to follow (a panel too square for it).
pub fn capsule_fit(corner : Double, height : Double, alone : Double) -> Double {
  let d = capsule_in(corner, height)
  if place_fits(d) {
    d
  } else {
    alone
  }
}

///|
/// Whether a capsule `height` high may stand concentric in a corner `corner` round (capsule_fit: corner_fit lets it
/// stand as far in as that takes).
pub fn capsule_fits(corner : Double, height : Double) -> Bool {
  place_fits(capsule_in(corner, height))
}

///|
/// `x` as a style's room (room, for the frame's packages).
pub fn room_of(x : Double) -> @ui.Space {
  room(x)
}

///|
/// The same in a corner `corner` round, as a style's room `less` the room it has already.
pub fn capsule_fit_room(corner : Double, height : Double, alone : Double, less? : Double = 0.0) -> @ui.Space {
  room(capsule_fit(corner, height, alone) - less)
}

///|
/// The corners of the panel of its own the view is built in (the tape's, laid out Medium: tape_corners; top left, then
/// round it), None in a window's whole: what a page stands in that panel's foot or top corners stands where it is
/// concentric with the corner it is in (`foot_capsule`, `pane_foot_in`, `pane_top_right`), each corner linked to where
/// it comes from.
// kept across runs: said by the frame round each panel of its own it builds
pub let pane_round : Ref[FixedArray[@ui.CornerOf]?] = Ref(None)

///|
/// The corners of the panel of its own the view is built in now (pane_round's radii), None in a window's whole.
pub fn pane_radii() -> FixedArray[Double]? {
  match pane_round.val {
    Some(k) => Some(corner_radii(k))
    None => None
  }
}

///|
/// The top right corner of the panel of its own the view is built in (pane_round), None in a window's whole.
pub fn pane_top_right() -> Double? {
  match pane_radii() {
    Some(k) => Some(k[1])
    None => None
  }
}

///|
/// Whether the page being built is in a panel of its own (pane_round): what stands in its corners stands concentric
/// with the panel's.
pub fn in_pane() -> Bool {
  pane_round.val is Some(_)
}

///|
/// Where a capsule `height` high across a page's foot (a wide button) stands from the panel's left, its right and its
/// foot: in a panel of its own (pane_round), each end in the foot corner it is in, as far in as makes it concentric
/// with it where corner_fit lets it stand there (capsule_fit), its foot as far in as such an end (the left's, where
/// both are: the right's apart from it there alone); an end that cannot, `side` in, as alone; none, `side` and `foot`
/// in, as in a window's whole, its right end past the window's corner there.
pub fn foot_capsule(height : Double, side : Double, foot : Double) -> (Double, Double, Double) {
  match pane_radii() {
    // (in a window's whole its right end in the window's foot corner: past it, window_corner_past)
    None => (side, window_corner_past(side), foot)
    // (beside the system's action at the column's foot, as high as it: on its line, in the foot left corner made for
    // it (native_foot_corner) however far in that is, its other end as far from what it stands in)
    Some(k) if native_capsule_h() is Some(h) && (h - height).abs() < 0.5 && native_foot_corner_now(k[3]) => {
      let d = capsule_in(k[3], height)
      (d, d, d)
    }
    Some(k) => {
      let at_l = capsule_in(k[3], height)
      let at_r = capsule_in(k[2], height)
      let fits_l = place_fits(at_l)
      let fits_r = place_fits(at_r) && (!fits_l || (at_r - at_l).abs() <= 0.5)
      let b = if fits_l {
        at_l
      } else if fits_r {
        at_r
      } else {
        foot
      }
      // (an end that cannot follow its corner as far in as one that does: the capsule as far from both its sides)
      let alone = if fits_l {
        at_l
      } else if fits_r {
        at_r
      } else {
        side
      }
      (if fits_l { at_l } else { alone }, if fits_r { at_r } else { alone }, b)
    }
  }
}

///|
/// Where a smooth box (a card, a block) stands in a corner `corner` round, `inset` in by the ladder: as far in and as
/// round as makes it concentric with it, the place nearest `inset` where corner_fit lets it stand and have the corner
/// that takes; where none does (a corner too square for one, or too round), `inset` in and `alone` round, as it would
/// stand alone. (How far in, its corner.)
pub fn box_fit(corner : Double, inset : Double, alone : Double) -> (Double, Double) {
  match fit_places(corner) {
    Some((nearest, furthest)) => {
      let d = dmin(dmax(inset, nearest), furthest)
      (d, @ui.concentric(corner, d))
    }
    None => (inset, alone)
  }
}

///|
/// The places a smooth box may stand in a corner `corner` round where its corner, concentric there, is one corner_fit
/// lets it have (further in, squarer), at least `least` round (what it holds in its own corner followed by it: holds_least):
/// the nearest and the furthest; None where none is (a corner too square for one, or too round).
fn fit_places(corner : Double, least? : Double = corner_fit.least) -> (Double, Double)? {
  let nearest = dmax(corner_fit.near, (corner - corner_fit.most) * @ui.smooth_scale)
  let furthest = dmin(corner_fit.far, (corner - dmax(least, corner_fit.least)) * @ui.smooth_scale)
  if nearest > furthest {
    None
  } else {
    Some((nearest, furthest))
  }
}

///|
/// How far a smooth box across a foot (a composer, a card) stands in from the sides and foot of a panel whose foot
/// corners are `left` and `right` round, `inset` in by the ladder: one place for both, the nearest `inset` where it is
/// concentric with each it may follow (fit_places: in both's places; where one is too square or too round for it, that
/// corner left to stand alone by, the other's), else `inset`, as it stands alone. Its corners there mbui works out
/// (concentric where it lies in a corner, its own where not).
pub fn foot_fit(left : Double, right : Double, inset : Double, least? : Double = corner_fit.least) -> Double {
  let span = match (fit_places(left, least~), fit_places(right, least~)) {
    (Some((a, b)), Some((c, d))) if dmax(a, c) <= dmin(b, d) => Some((dmax(a, c), dmin(b, d)))
    // (the two's places apart: the squarer's, the rounder then standing alone where it cannot follow)
    (Some(l), Some(r)) => Some(if left <= right { l } else { r })
    (Some(l), None) => Some(l)
    (None, Some(r)) => Some(r)
    (None, None) => None
  }
  match span {
    Some((nearest, furthest)) => dmin(dmax(inset, nearest), furthest)
    None => inset
  }
}

///|
/// How far in from the sides and foot of what is built a box at its foot stands (a composer, a card): the ladder's
/// inset in a window's whole; in a panel of its own (pane_round), where foot_fit puts it in the panel's foot corners,
/// following only a corner that leaves it round enough for a circle `holds` across in its own corner to follow it in
/// turn (a composer's ＋ and send: holds_least), else standing alone there (the user, 2026-10-25: a composer's corner
/// followed a window's its send could not).
pub fn pane_foot_in(holds? : Double = 0.0) -> Double {
  match pane_radii() {
    Some(k) => foot_fit(k[3], k[2], foot_inset(dmax(k[3], k[2])), least=holds_least(holds))
    None => corner_inset
  }
}

///|
/// Where a card stands in from a panel's corner `corner` round to be a card's corner of the ladder's there (the
/// ladder's inset in a pane corner's 34, 10; in one of 30, 5), as near as corner_fit lets where that is nearer (the
/// tape's 28: 4, less round than a card there, pane_foot_corner).
fn foot_inset(corner : Double) -> Double {
  dmax(corner_fit.near, (corner - card_corner) * @ui.smooth_scale)
}

///|
/// The corner of a box across the foot of what is built standing pane_foot_in(holds) in (a composer opened): concentric
/// with the roundest of the panel's foot corners it follows from there, all its corners alike (one it cannot follow, a
/// Mac window's at the page's right, as that one: InnerOr's own); a card's of the ladder's where it follows none (a
/// window's whole, a panel's foot corners all too square). The tape's 28, 4 in: 24.8.
pub fn pane_foot_corner(holds? : Double = 0.0) -> Double {
  match pane_radii() {
    Some(k) => {
      let d = pane_foot_in(holds~)
      let least = holds_least(holds)
      let mut out = card_corner
      let mut roundest = -1.0
      for r in [k[3], k[2]] {
        match fit_places(r, least~) {
          Some((nearest, furthest)) if d >= nearest - 0.5 && d <= furthest + 0.5 && r > roundest => {
            roundest = r
            out = @ui.concentric(r, d)
          }
          _ => ()
        }
      }
      out
    }
    None => card_corner
  }
}

///|
/// How high a capsule across the foot of what is built is (a composer's one line), `own` high alone, round controls
/// `holds` across in its ends: in a panel of its own whose foot corners are too square for it to stand concentric in
/// them as high as that, as high as stands so `window_in` (6) from its edges, as the panel itself stands from the
/// window's (the user, 2026-10-27: 中屏 composer 胶囊的时候，边上距离小), or nearer where what it holds would stand
/// nearer than 4 in its own ends, at corner_fit's nearest (4) at most; else `own`. In the tape's 28 (a circle reads it
/// as 26.78): keyboard and mouse's 48 (its 32 buttons) 41.6, 6 in; a finger's 52 (its 36) 44, 4.8 in.
pub fn foot_capsule_h(own : Double, holds : Double) -> Double {
  // (beside the system's action at the column's foot: as high as it, one row with it)
  if in_pane() && native_capsule_h() is Some(h) {
    return h
  }
  match pane_radii() {
    Some(k) => {
      let r = @ui.round_like(dmax(k[2], k[3]))
      let most = 2.0 * (r - corner_fit.near)
      let least = holds + 2.0 * corner_fit.near
      if own > most + 0.5 && most >= least - 0.5 {
        dmin(most, dmax(2.0 * (r - window_in), least))
      } else {
        own
      }
    }
    None => own
  }
}

///|
/// The least a box's corner is where a circle `holds` across in it follows it (its half and the nearest place a
/// circle following a corner stands, corner_fit near); the theme's least where it holds none.
pub fn holds_least(holds : Double) -> Double {
  if holds > 0.0 {
    @ui.round_like_out(holds / 2.0 + corner_fit.near)
  } else {
    corner_fit.least
  }
}

///|
/// A card across the foot of what is built (a side panel's job picked): as far in from its sides and foot as
/// pane_foot_in, a card's corner (in the panel's foot corners concentric with them: mbui works them out).
pub fn pane_foot_card() -> @ui.Style {
  let d = pane_foot_in()
  @ui.style(mx=room(d), mb=room(d), radius=rounded(card_corner))
}

///|
/// How far in from a corner of the ladder's `corner` a capsule or a circle `height` high stands, concentric with it
/// (ui-panels.md: 外圆角 = 距离 + 半高, the corner as a circle reads it: @ui.round_like, wholly smooth; a capsule's end,
/// `room` its half, as round as it is).
pub fn capsule_in(corner : Double, height : Double, room? : Double = 1.0e30) -> Double {
  @ui.round_like(corner, room~) - height / 2.0
}

///|
/// How far in a capsule `height` high stands from a card's sides and foot where it is in the card's foot corners (a
/// button, a field there: concentric with the card's corner), and its ground reaching past the card's words (card_pad
/// in) to there: across the card, or at its start with its words where they were (`words_in`: its own padding).
/// `corner`: the card's, where it is not the ladder's card step (a card in a message: ask_corner); one too tight for
/// the capsule (its end as round as the corner or rounder, pressing it to the card's edges) has it follow the corner
/// instead, square, corner_inset in (@sf.button under foot_round).
pub fn card_foot_in(height : Double, corner? : Double = card_corner) -> Double {
  let d = capsule_in(corner, height)
  // (a capsule pressed to the card's edges, capsule_least in or less, does not stand in its corner: it follows it)
  if d > capsule_least {
    d
  } else {
    corner_inset
  }
}

///|
/// How far in a capsule must stand to stand in a corner (card_foot_in): any nearer, it is pressed to the edges.
let capsule_least : Double = 4.0

///|
/// A card in a message (a question's, a login's, a post's options): as round as a message's bubble, the ladder's row
/// step (18), as all else a message carries (message_file_corner): one corner for what is in a chat's list.
pub let ask_corner : Double = row_corner

///|
/// What scrolls in a small panel held to the room it has (@kit.in_room's `reach`): its box out across the panel's
/// padding, so that it and its bar reach the panel's sides; what it holds (`style`) back in as far.
pub fn held_reach() -> @ui.Style {
  @ui.style(w=Full, mx=room(-panel_pad))
}

///|
pub fn held_in() -> @ui.Style {
  @ui.style(w=Full, px=room(panel_pad))
}

///|
pub fn foot_across(height : Double) -> @ui.Style {
  @ui.style(mx=room(card_foot_in(height) - card_pad))
}

///|
pub fn foot_start(height : Double, words_in : Double) -> @ui.Style {
  @ui.style(ml=room(card_foot_in(height) - card_pad), pl=room(words_in + card_pad - card_foot_in(height)))
}

///|
/// A card's rows `row_h` high, each with something `end_h` high in its middle at its end (a key's button): reaching into
/// the card's padding over the first and under the last by as much as that stands in from a row's top and foot, so the
/// first's and the last's stand in the card's corners as far from both its edges (round by the ladder's there: mbui
/// works it out).
pub fn card_rows_reach(row_h : Double, end_h : Double) -> @ui.Style {
  @ui.style(my=room((end_h - row_h) / 2.0))
}

///|
/// A block (a command's box, a table) across a card's foot, its ground reaching past the card's words to the
/// ladder's inset: round by the ladder's next step there.
pub let block_across : @ui.Style = @ui.style(mx=room(corner_inset - card_pad))

///|
/// A card's foot with a capsule `height` high in its corners: as far in as makes it concentric (card_foot_in).
pub fn foot_pad(height : Double) -> @ui.Style {
  @ui.style(pb=room(card_foot_in(height)))
}

///|
/// A card's first row with a capsule `height` high at its start (a field, a button): reaching past the card's words to
/// where it stands concentric with its top corner (card_foot_in), at its start and its top.
pub fn head_reach(height : Double) -> @ui.Style {
  let out = room(card_foot_in(height) - card_pad)
  @ui.style(ml=out, mt=out)
}

///|
/// What follows the capsule in such a row, at its start where the row runs on to another line: back where the card's
/// words stand (as far in as head_reach took the row out).
pub fn head_back(height : Double) -> @ui.Style {
  @ui.style(ml=room(card_pad - card_foot_in(height)))
}

///|
/// A card's last row with capsules `height` high at its ends (a card card_pad in, as a page's): reaching past the
/// card's words to where they stand concentric with its foot corners (card_foot_in), at both its sides and its foot;
/// `start`: what leads it is that high instead (a field before a button: the row as high as the higher, the lower in
/// its middle stands as much further from the foot as it is less high, each concentric with its corner); `words_first`:
/// words lead it (where the card's words stand), only its end reaching.
pub fn foot_reach(height : Double, start? : Double, words_first? : Bool = false, corner? : Double = card_corner) -> @ui.Style {
  let out = room(card_foot_in(height, corner~) - card_pad)
  if words_first {
    return @ui.style(mr=out, mb=out)
  }
  let lead = start.unwrap_or(height)
  let under = room(card_foot_in(dmax(height, lead), corner~) - card_pad)
  @ui.style(ml=room(card_foot_in(lead, corner~) - card_pad), mr=out, mb=under)
}

///|
/// What stands over such a row of capsules `height` high, across the card (a field over its buttons): out to the sides
/// they reach (foot_reach), so that its ends and theirs line up, the buttons' words then where the field's are, not at
/// its edge.
pub fn over_foot_reach(height : Double, corner? : Double = card_corner) -> @ui.Style {
  let out = room(card_foot_in(height, corner~) - card_pad)
  @ui.style(ml=out, mr=out)
}

///|
/// The ladder's steps and inset as a style's: a card's corner, a row's or a block's, a small block's; the inset; a
/// list card's padding (list_pad) and its rows' words' room in them (a row's own, text_in: list_pad and that from the
/// card's edge, 16, as a menu's words in its panel); what a card's corner keeps clear past its words (its corner less
/// card_pad).
pub let card_radius : @ui.Radius = rounded(card_corner)

///|
pub let row_radius : @ui.Radius = rounded(row_corner)

///|
pub let small_radius : @ui.Radius = rounded(small_corner)

///|
pub let inset_room : @ui.Space = room(corner_inset)

///|
pub let list_room : @ui.Space = room(list_pad)

///|
pub let list_words_room : @ui.Space = room(text_in)

///|
pub let corner_clear_room : @ui.Space = room(card_corner - card_pad)

///|
/// How far in from a corner of `corner` a capsule `height` high stands concentric with it (capsule_in), as a style's
/// room; `less`, less what already stands between (a row's own inset, a line over it).
pub fn capsule_room(corner : Double, height : Double, less? : Double = 0.0) -> @ui.Space {
  room(capsule_in(corner, height) - less)
}

///|
/// How far in from a capsule's ends (`outer` high) one `height` high stands in it, concentric with them (a dot, a
/// button in a capsule's end), as a style's room.
pub fn capsule_end_room(outer : Double, height : Double) -> @ui.Space {
  room(capsule_in(outer / 2.0, height, room=outer / 2.0))
}

///|
/// `more` under the system's bar at the window's top (a phone's status bar; 0 where the host lays the app out under it):
/// where what floats at the top of a layer over the whole window stands.
pub fn system_top_room(more : Double) -> @ui.Space {
  room(more + @ui.system_bars().top)
}

///|
/// `more` in from either side, and past what the system has at the window's sides while the app has turned the device
/// sideways (@hostapi.turned_sideways: a film or a screen over all of the window, a phone's cutout over its edge; else
/// the shell keeps the page beside them), as a style's room: where what floats over such a page stands.
pub fn sides_clear(more : Double) -> @ui.Style {
  let b = if @hostapi.turned_sideways() { @ui.system_bars() } else { { top: 0.0, bottom: 0.0, left: 0.0, right: 0.0 } }
  @ui.style(pl=room(more + dmax(0.0, b.left)), pr=room(more + dmax(0.0, b.right)))
}

///|
/// How far under a page's bar what is drawn from the page's top stands (the bar 45, in a panel of its own as much taller
/// as puts its buttons in the panel's corner concentric with it: tape_bar_over).
pub fn under_bar_room() -> @ui.Space {
  room(wide_bar_h + (if in_pane() { tape_bar_over() } else { 0.0 }))
}

///|
/// Where a page's capsule `height` high stands at its foot (foot_capsule): in from its panel's sides by as much more
/// than the page's own `side` room as makes each end concentric with the corner it is in (a margin, `side` less that),
/// and over its foot.
pub fn foot_corner(height : Double, side : Double, foot : Double) -> @ui.Style {
  let (l, r, b) = foot_capsule(height, side, foot)
  @ui.style(ml=room(l - side), mr=room(r - side), pb=room(b))
}

///|
/// A page card of words: this in from every side.
pub let card_pad : Double = 20.0

///|
/// A command's box's corner: a block's on a card, its copy button corner_inset in from its corner.
pub let command_box_corner : Double = row_corner

///|
/// A button's height (36): a capsule, capsule_in(card_corner, 36) in from a card's corner where it stands in one.
pub let button_h : Double = 36.0

///|
/// A card of pressable rows (a list card, a card of options): the rows this far in, as a menu's are in its panel
/// (lit_reach), each round by the ladder's row corner concentric with the card's (list_card_corner).
pub let list_pad : Double = lit_reach

///|
/// A settings row's icon, before its name (SettingParts.kt ROW_ICON).
pub let row_icon : Double = 22.0

///|
/// A finger's list row in from its box's left (SidebarList.css.ts phone: a chat row's 22).
pub let phone_row_in : @ui.Space = room(22.0)

///|
/// An empty list's illustration and words in from its sides (Home.kt Empty: 30).
pub let empty_in : @ui.Space = room(30.0)

///|
/// The account's picture and the workspace's mark, each on its card atop settings (SettingsHome.kt): 46.
pub let identity_mark : Double = 46.0

///|
/// The workspace's mark's square (SettingsHome.kt WorkspaceTile): the account's picture's size beside it, in its row's
/// corners the ladder's inset in (a row's 18, 10 in), so concentric with them: the small block's 10, all four alike;
/// what it holds in its middle.
pub let workspace_tile : @ui.Style = @ui.style(
  w=Fixed(identity_mark),
  h=Fixed(identity_mark),
  radius=small_radius,
  align=ACenter,
  justify=JCenter,
  clip=true,
)

///|
/// A mark of the workspace's own (one of still.fail's icons, an emoji) in its square: 26.
pub let workspace_tile_mark : Double = 26.0

///|
/// A workspace's first letter in its square, where it has no mark: 22 on a line of 22 (Xl3, L7: SettingsHome.kt's
/// lineHeight, near the account's initial beside it, half its picture), semibold, muted (Rail.css.ts workspaceItem).
pub let workspace_letter : @ui.TextStyle = @ui.text_style(size=Heading, leading=L7, weight=Semibold, color=Muted, wrap=false)

///|
/// A chip whose ground fills from the left (an allowance's, a machine's load, a download's: Parts.kt FILL_CHIP_CORNER):
/// round by the ladder's small corner (a small one's 16 a capsule); in a card's or a row's corner concentric with it
/// (mbui works it out).
pub let fill_chip_corner : Double = small_corner

///|
/// Corners (--r-*): a field's, a card's, a dialog's, the nav's, a menu's,
/// an option's.
pub let r_field : Double = 12.0

///|
pub let r_card : Double = 20.0

///|
pub let r_dialog : Double = 32.0

///|
/// (a small panel's: a menu, a popover, a hover's card, and a list card: a taller row at its padding (panel_pad) the
/// ladder's row corner, 18, concentric with it, 18 + 6 / 1.25 = 22.8: the ladder's small panels (corner_ladder). What
/// stands further in in it is round by the ladder's next steps as a card's is: what has a ground on its words' line 10.
/// Its rows 34 high are capsules: they stand where that is concentric with it (menu_row_reach), a little nearer its
/// edges.)
pub let r_menu : Double = surface_corner(panel_pad, row_corner)

///|
/// How far a small panel's row `height` high reaches past its padding: a capsule (as high as twice the corner it would
/// have there, or less) to where it is concentric with the panel's corner (capsule_in: a mouse's 34, 4.81 in, 1.19
/// past), as every capsule in a corner stands (the user, 2026-10-27: a capsule in a smooth corner, off its curve);
/// a taller row, rounded, none.
pub fn menu_row_reach(height : Double) -> Double {
  if height / 2.0 <= small_panel_inner(r_menu) + 0.5 {
    dmax(0.0, panel_pad - capsule_in(r_menu, height))
  } else {
    0.0
  }
}

///|
pub let r_option : Double = 12.0

///|
/// Where a desktop's window, which no system classes, goes from one layout to the next (layout): the widths at which
/// Android's WindowSizeClass goes from compact to medium and from medium to expanded, so a window as wide is laid out
/// alike whatever the system.
pub let medium_from : Double = 600.0

///|
pub let large_from : Double = 840.0

// ---------------------------------------------------------------------------

///|
/// How opaque a tone's ink is as its ground (a pill's, a mention's, an error's card: green_bg, red_bg…), in the light
/// themes and the dark: far enough off whatever it lies on to be seen (1.25 to 1 and more, docs/ui-panels.md 对比度),
/// and its ink on it still read (4.5 to 1). Grounds fitted to the page alone, opaque, were 1.0 to 1.1 to 1 off a card
/// in the dark (a pull request's 开启, 2026-10-27): its words seen, not its pill.
let tone_light : Double = 0.18

///|
let tone_dark : Double = 0.16

///|
/// A ground in a tone the palette has none for (a merged pull request's purple): its ink at the theme's opacity, as
/// green_bg is green_ink's.
pub fn tone_ground(ink : Int64) -> Int64 {
  alpha(ink, if current.val.dark { tone_dark } else { tone_light })
}

///|
/// The web's own tones (a white page, grey cards on it): what the message's Markdown keeps of them (markdown.mbt `web`),
/// and what the palette's names not its own mean (light_palette).
let web_light : Palette = {
  bg: 0xFFFFFFFFL,
  canvas: 0xFFFFFFFFL,
  raised: 0xE4E4E8FFL,
  sidebar: 0xF6F5F1FFL,
  list: 0xFBFAF9FFL,
  text: 0x24272BFFL,
  muted: 0x565B62FFL,
  subtle: 0x565B62FFL,
  line: 0x322D2424L,
  line_strong: 0xC1C4C9FFL,
  hover: 0x26211711L,
  selected: 0xEBE7E1FFL,
  paper: 0xF6F2EAFFL,
  accent: 0xDC5929FFL,
  accent_text: 0x982E01FFL,
  accent_bg: alpha(0x982E01FFL, tone_light),
  green: 0x006A3FFFL,
  green_ink: 0x026039FFL,
  warn_ink: 0x6E4802FFL,
  red: 0x9A2830FFL,
  red_bg: alpha(0x9A2830FFL, tone_light),
  green_bg: alpha(0x026039FFL, tone_light),
  blue_bg: alpha(0x0047AEFFL, tone_light),
  amber_bg: alpha(0x6E4802FFL, tone_light),
  online: 0x45B164FFL,
  neutral_bg: 0x24272B13L,
  overlay: 0x13161B33L,
  shadow: 0x13161B1AL,
  primary: 0x24272BFFL,
  primary_hover: 0x41464CFFL,
  on_primary: 0xFFFFFFFFL,
  // the text at 4% over the canvas (pages.css.ts cardGround)
  card: 0xF6F6F7FFL,
  card2: 0xFBFAF7FFL,
  chip: 0xEFECE6FFL,
  blue: 0x0047AEFFL,
  code_ink: 0x7C3FA0FFL,
  code_ground: 0xF5F5F5FFL,
}

///|
let web_dark : Palette = {
  bg: 0x1F2023FFL,
  canvas: 0x1F2023FFL,
  raised: 0x2A2C31FFL,
  sidebar: 0x19191BFFL,
  list: 0x1C1D20FFL,
  text: 0xE9E9EAFFL,
  muted: 0xA8AAAEFFL,
  subtle: 0xA8AAAEFFL,
  line: 0xE9E9EA19L,
  line_strong: 0x3D3F44FFL,
  hover: 0xFFFFFF0DL,
  selected: 0x323338FFL,
  paper: 0x26272BFFL,
  accent: 0xE97342FFL,
  accent_text: 0xFF9E71FFL,
  accent_bg: alpha(0xFF9E71FFL, tone_dark),
  green: 0x68C894FFL,
  green_ink: 0x6ACA96FFL,
  warn_ink: 0xE6B55DFFL,
  red: 0xFF9A97FFL,
  red_bg: alpha(0xFF9A97FFL, tone_dark),
  green_bg: alpha(0x6ACA96FFL, tone_dark),
  blue_bg: alpha(0x8EB8FEFFL, tone_dark),
  amber_bg: alpha(0xE6B55DFFL, tone_dark),
  online: 0x45B164FFL,
  neutral_bg: 0xE9E9EA0EL,
  overlay: 0x00000080L,
  shadow: 0x00000073L,
  primary: 0xECEDEDFFL,
  primary_hover: 0xD3D4D6FFL,
  on_primary: 0x1F2023FFL,
  card: 0x28292CFFL,
  card2: 0x2C2D31FFL,
  chip: 0x313237FFL,
  blue: 0x8EB8FEFFL,
  code_ink: 0xC9A2E6FFL,
  code_ground: 0x26272AFFL,
}

///|
/// still.fail's palette on every screen (the phone's, root.css.ts m): warm paper, white cards on it, its own greys;
/// what the web's names mean there.
let light_palette : Palette = {
  ..web_light,
  bg: 0xF5F3EFFFL,
  canvas: 0xFFFFFFFFL,
  raised: 0xFFFFFFFFL,
  text: 0x24272BFFL,
  // the greys and the red Android's (Theme.kt Light), what the app on a phone matches, not the narrow web's
  muted: 0x535559FFL,
  subtle: 0x535559FFL,
  line: 0x322D2424L,
  accent: 0xCC5A34FFL,
  accent_text: 0x8F2B01FFL,
  accent_bg: alpha(0x8F2B01FFL, tone_light),
  green: 0x2F8F5BFFL,
  green_ink: 0x045B33FFL,
  red: 0x991302FFL,
  red_bg: alpha(0x991302FFL, tone_light),
  green_bg: alpha(0x045B33FFL, tone_light),
  // its placeholders in its bubbles' grey, a step darker than the page
  neutral_bg: 0x322D2413L,
  card: 0xFFFFFFFFL,
  // Android's C.chip (Theme.kt), what the app on a phone matches, not the narrow web's EFECE6
  chip: 0xE8E4DCFFL,
  hover: 0x24272B0FL,
  // the sidebar beside the page (a tablet's Medium and Large): a step under the page's ground as the web's is under
  // its canvas (FFFFFF → F6F5F1), the panes told apart by their grounds; what is chosen in it a step under that, as
  // the web's (F6F5F1 → EBE7E1). The web's own, over this page's beige, were the page's colour
  sidebar: 0xECE9E1FFL,
  selected: 0xE1DBD1FFL,
}

///|
let dark_palette : Palette = {
  ..web_dark,
  bg: 0x1B1C1FFFL,
  canvas: 0x26272BFFL,
  raised: 0x2A2C31FFL,
  text: 0xECECEDFFL,
  muted: 0xB8BBC1FFL,
  // Android's (Theme.kt Dark)
  subtle: 0xB8BBC1FFL,
  line: 0xECECED1FL,
  accent: 0xE8734FFFL,
  accent_text: 0xF6A383FFL,
  accent_bg: alpha(0xF6A383FFL, tone_dark),
  green: 0x5CC08AFFL,
  green_ink: 0x66CA93FFL,
  warn_ink: 0xEEAA44FFL,
  red: 0xFE9D8CFFL,
  red_bg: alpha(0xFE9D8CFFL, tone_dark),
  green_bg: alpha(0x66CA93FFL, tone_dark),
  blue_bg: alpha(0x8EB8FEFFL, tone_dark),
  amber_bg: alpha(0xEEAA44FFL, tone_dark),
  neutral_bg: 0xECECED1BL,
  // an outline a step lighter than the web's (3D3F44), as the grounds it lies on are (its canvas 1F2023 → 26272B): a
  // quote's bar on a card's chip still seen
  line_strong: 0x44464BFFL,
  card: 0x26272BFFL,
  chip: 0x313237FFL,
  // the sidebar a step under the page's ground, as the web's dark one under its canvas (1F2023 → 19191B)
  sidebar: 0x151517FFL,
  hover: 0xECECED14L,
}

///|
let wide_type : Type = {
  caption: 11.0,
  caption_line: 16.0,
  meta: 12.0,
  meta_line: 18.0,
  ui: 13.0,
  ui_line: 20.0,
  body: 14.0,
  body_line: 22.0,
  title: 16.0,
  title_line: 24.0,
  heading: 22.0,
  heading_line: 30.0,
  display: 28.0,
  // (the body's line, the web's --leading-body 22: msgPlain's 1.55 is 21.7, off the scale)
  words: @ui.text_style(size=Body, leading=L7, color=Fg),
}

///|
/// A control's height (Theme::control_h): the web's (controls.css.ts input, select: 36), a finger's (44).
let wide_control_h : Double = 36.0

///|
let narrow_control_h : Double = 44.0

///|
/// What a row takes at least: one least row height for the native input (the theme's `items.least`: 36 with keyboard
/// and mouse, 44 with touch), narrow rows and wide, a sidebar's and a list's alike, what it shows in its middle (rule 2:
/// a press's room 36 or 44 at least; a row's room is its own height, its neighbours right over and under it). A button is drawn its own size: a press reaches one drawn smaller from round it (mbui's press_reach).
pub fn row_least_h() -> @ui.Style {
  @ui.style(min_h=Fixed(theme().items.least))
}

///|
/// The height row_least_h holds a row to at least.
pub fn row_least() -> Double {
  theme().items.least
}

///|
/// The phone's: a size up, as Android's.
let narrow_type : Type = {
  ..wide_type,
  caption: 12.0,
  meta: 13.0,
  meta_line: 18.0,
  ui: 15.0,
  ui_line: 22.0,
  body: 15.0,
  body_line: 22.0,
  words: message,
}

///|
/// The computer's round controls (attachBtn, sendBtn: 32, the arrow 16).
let wide_round : Round = { side: 32.0, glyph: 16.0 }

///|
/// The phone's (mPlus, mSend: 36, both glyphs 18).
let narrow_round : Round = { side: 36.0, glyph: 18.0 }

///|
/// It: `side` round, what it shows in its middle.
pub fn round_face() -> @ui.Style {
  let r = theme().round
  @ui.style(w=Fixed(r.side), h=Fixed(r.side), radius=InnerOr(Full), align=ACenter, justify=JCenter)
}

///|
let bars_drawn : Bars = { key: 28.0, icon: 14.0, field: 30.0 }

///|
// kept across runs: a value (no field of it changes)
let wide_items : Items = {
  least: 36.0,
  name: @ui.text_style(size=Ui, color=Fg, wrap=false),
  meta: @ui.text_style(size=Meta, color=Muted, wrap=false),
  mark: 20.0,
  mark_line: L6,
}

///|
// kept across runs: a value (no field of it changes)
let narrow_items : Items = {
  least: 44.0,
  name: @ui.text_style(size=Ui, leading=L6, color=Fg, wrap=false),
  meta: @ui.text_style(size=Meta, leading=L4, color=Muted, wrap=false),
  mark: 22.0,
  mark_line: L7,
}

///|
let wide_rows : Rows = {
  pick: menu_row_min,
  title: @ui.text_style(size=Ui, leading=L6, color=Fg),
  note: @ui.text_style(size=Meta, leading=L5, color=Muted),
  check: 18.0,
  field_w: Fixed(52.0),
  field_h: Fixed(28.0),
  check_corner: 6.0,
  switch_w: 36.0,
  switch_h: 22.0,
}

///|
let narrow_rows : Rows = {
  pick: narrow_control_h,
  title: @ui.text_style(size=Body, color=Fg),
  note: @ui.text_style(size=Ui, leading=L5, color=Muted),
  check: 22.0,
  field_w: Fixed(72.0),
  field_h: Fixed(36.0),
  check_corner: 7.0,
  switch_w: 44.0,
  switch_h: 26.0,
}

///|
/// Light or dark as set (set_dark): a signal, so what is made once of the theme's colours follows it (theme)
// kept across runs: put back as a Tester starts (icons.mbt)
let dark_set : @signals.Signal[Bool?] = @signals.signal(None, same=fn(a, b) { a == b })

///|
let current : Ref[Theme] = {
  val: {
    dark: false,
    touch: false,
    p: light_palette,
    t: wide_type,
    rows: wide_rows,
    control_h: wide_control_h,
    bars: bars_drawn,
    round: wide_round,
    items: wide_items,
    chat_list: mouse_chat_list,
  },
}

///|
/// Light or dark from now on (None: as the system, which hosts don't tell
/// yet: light).
pub fn set_dark(dark : Bool?) -> Unit {
  dark_set.set(dark)
}

///|
/// The native input (原生操控: docs/architecture.md, the terms): touch (`Finger`) or keyboard and mouse (`Mouse`), as
/// the app is started, the same the whole run: the theme's sizes (words, rows, what a press reaches), how what shows
/// only under a pointer is reached, what Enter does, scroll bars, and with the screen's tier how the presenters show
/// (a sheet or beside what opened it) and how search is opened (a field over the list or ⌘K). As the host tells it at
/// launch (@ui.native_pointing: an iPad started with a pointer, Android with a mouse or a touchpad, keyboard and mouse;
/// Windows with a touch screen and no mouse, touch), the platform's where it cannot. How things answer the hand of the
/// moment is not this: the current input, @ui.pointing.
pub fn native_input() -> @ui.Pointing {
  @ui.native_pointing()
}

///|
/// How the app's panes are laid out, by the screen alone: how much room its window has and what kind of screen it is.
/// Never by what it is pointed with (@ui.pointing): each is pointed at with a mouse or a finger alike.
pub(all) enum Layout {
  /// one page at a time, the whole window (a phone held upright, a narrow window)
  Small
  /// the panes side by side as on a large screen, more of them than the window shows: the one in use whole, those
  /// beside it showing past its edges, one tapped coming over before what it holds answers (sfdesk's frame.mbt)
  Medium
  /// the panes side by side, all of them shown: the rail and the sidebar, the page, the page's side panel
  Large
} derive(Eq, Show, Debug)

///|
/// The layout of a window `width` wide, in points, on every screen alike (medium_from, large_from): neither which way up
/// it is held, nor its height, nor how large it is says how many panes there are (the user, 2026-10-25); the height
/// only how much of them shows. One thing else: a fold half open on its back half is Small where the system has no tabs of its own for the app (a chat across the window,
/// its composer under the fold: sfapp's tabletop.mbt). While
/// the app has the device turned sideways itself (a film, a station's screen over all of it: @hostapi.sideways), the
/// one it had as it turned: the screen is the same, only what is over all of it turned.
pub fn layout(width : Double) -> Layout {
  let now = screen_layout(width)
  if !@hostapi.sideways() {
    layout_held.val = None
    return now
  }
  match layout_held.val {
    Some(held) => held
    None => {
      layout_held.val = Some(now)
      now
    }
  }
}

///|
/// The layout as the app turned the device sideways (layout), while it has it so.
// kept across runs: let go as the device is upright again
let layout_held : Ref[Layout?] = Ref(None)

///|
/// The layout by the screen alone (layout).
fn screen_layout(width : Double) -> Layout {
  // a fold half open, its crease across: a chat over the crease, whatever its width (the one thing other than the width);
  // not where the system lays out the app's tabs itself in every pose (an iPhone Duo's: native_able, the user,
  // 2026-10-26)
  if (native_input() is Finger) && @ui.system_tabletop() is Some(_) && !native_able() {
    return Small
  }
  if width < medium_from {
    Small
  } else if width < large_from {
    Medium
  } else {
    Large
  }
}

///|
/// The theme for this frame (docs/architecture.md, the terms): its sizes by the native input alone (rule 4: the screen
/// says how things are laid out, never how large they are), a finger's on a touch device (Android's app, a tablet's
/// too), keyboard and mouse's on a computer, its window narrow or not; its colours one palette on every screen, light
/// or dark as set: call at the top of a view.
pub fn begin(_c : @ui.Ctx) -> Theme {
  let dark = @signals.untracked(fn() { dark_set.get() }).unwrap_or(false)
  let touch = native_input() is Finger
  current.val = {
    dark,
    touch,
    p: if dark { dark_palette } else { light_palette },
    t: if touch { narrow_type } else { wide_type },
    rows: if touch { narrow_rows } else { wide_rows },
    control_h: if touch { narrow_control_h } else { wide_control_h },
    bars: bars_drawn,
    round: if touch { narrow_round } else { wide_round },
    items: if touch { narrow_items } else { wide_items },
    chat_list: if touch { touch_chat_list } else { mouse_chat_list },
  }
  current.val
}

///|
/// A link's ink: the accent's ink (its darker one on paper, its lighter one in the dark), which reads in words; the
/// accent itself in the dark was 4.3 to 1 on a raised ground (docs/ui-panels.md 对比度).
pub fn link_ink() -> Int64 {
  theme().p.accent_text
}

///|
/// What `body` draws on ground `bg` in place of the page's: the palette's and the styles' `Bg` both (a panel behind
/// the one in use on the tape: behind_ground).
pub fn with_ground(c : @ui.Ctx, bg : Int64, body : () -> Unit) -> Unit {
  let was = current.val
  current.val = { ..was, p: { ..was.p, bg, } }
  c.with_theme({ ..c.theme(), bg, }, body)
  current.val = was
}

///|
/// The ground of a panel behind the one in use (the tape's): the page's a step darker, what is on it as it is
/// (pengxiao, 2026-10-25: which one is in use told apart, the words of the others as readable); `k` of the way there.
pub fn behind_ground(k? : Double = 1.0) -> Int64 {
  let t = current.val
  let veil = if t.dark { behind_dark } else { behind_light }
  // (`k` of the way there: as a panel goes behind or comes in front with the tape's move)
  let a = ((veil & 0xFFL).to_double() * k).round().to_int64()
  over(t.p.bg, (veil & 0xFFFFFF00L) | a)
}

///|
/// How much darker it is: black at 4% on paper, at 35% in the dark.
let behind_light : Int64 = 0x0000000AL

///|
let behind_dark : Int64 = 0x00000059L

///|
/// The theme `begin` picked.
pub fn theme() -> Theme {
  // (read as a signal: what is made once of it filled anew as light or dark is set)
  dark_set.get() |> ignore
  current.val
}

///|
/// The palette, light or dark (what a page drawn apart from the frame's own is told: a visualization's, viz_file.mbt).
pub fn palette_of(dark : Bool) -> Palette {
  if dark {
    dark_palette
  } else {
    light_palette
  }
}

// ---------------------------------------------------------------------------
// Colours mixed as the web's color-mix does

///|
/// `top` laid over `base` (alpha compositing; base opaque or not).
pub fn over(base : Int64, top : Int64) -> Int64 {
  let ta = (top & 0xFFL).to_double() / 255.0
  let ba = (base & 0xFFL).to_double() / 255.0
  let oa = ta + ba * (1.0 - ta)
  if oa <= 0.0 {
    return 0L
  }
  let ch = fn(shift : Int) -> Int64 {
    let t = ((top >> shift) & 0xFFL).to_double()
    let b = ((base >> shift) & 0xFFL).to_double()
    let v = (t * ta + b * ba * (1.0 - ta)) / oa
    v.round().to_int64()
  }
  (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | (oa * 255.0).round().to_int64()
}

///|
/// `c` at `share` of its opacity (color-mix with transparent).
pub fn alpha(c : Int64, share : Double) -> Int64 {
  let a = (c & 0xFFL).to_double() * share
  (c & 0xFFFFFF00L) | a.round().to_int64()
}

///|
/// `share` of `a` and the rest of `b` (color-mix in srgb).
pub fn mix(a : Int64, share : Double, b : Int64) -> Int64 {
  let ch = fn(shift : Int) -> Int64 {
    let x = ((a >> shift) & 0xFFL).to_double()
    let y = ((b >> shift) & 0xFFL).to_double()
    (x * share + y * (1.0 - share)).round().to_int64()
  }
  (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)
}

///|
/// `share` of `a` and the rest of `b` as each is seen over anything: their colours weighed by how opaque each is
/// (mixed premultiplied), so that what is under the mix shows through as much as between theirs; a ground going from a
/// see-through colour to a solid one passes through no darker one.
pub fn mix_seen(a : Int64, share : Double, b : Int64) -> Int64 {
  let aa = (a & 0xFFL).to_double() / 255.0
  let ba = (b & 0xFFL).to_double() / 255.0
  let opacity = aa * share + ba * (1.0 - share)
  if opacity <= 0.0 {
    return 0L
  }
  let ch = fn(shift : Int) -> Int64 {
    let x = ((a >> shift) & 0xFFL).to_double() * aa
    let y = ((b >> shift) & 0xFFL).to_double() * ba
    ((x * share + y * (1.0 - share)) / opacity).round().to_int64()
  }
  (ch(24) << 24) | (ch(16) << 16) | (ch(8) << 8) | (opacity * 255.0).round().to_int64()
}

// ---------------------------------------------------------------------------
// mbui's tokens (its docs/style.md): what still.fail's styles (styles.mbt) say by name. The numbers are here and
// nowhere else; a value off mbui's scale is one of the few `Exact`s below.

///|
/// still.fail's sizes of words on mbui's scale (Tailwind's names, still.fail's values), the eight the Android app
/// has, each with the line it has where a `Text` there says no `lineHeight` (ui/Theme.kt WebType: 1.4em, the web
/// phone's root.css.ts), and mbui's two under Xs (Xs3 10, Xs2 11) on the same rule: Xs 12 (120 places), Sm 13 (292), Base 14 (156), Lg 15 (206: the body), Xl 16 (a bar's
/// title, Parts.kt:527), Xl2 17 (back, Parts.kt:491), Xl3 22 (a title, bold: Security.kt:473, NewChat.kt:183,
/// Usage.kt:130, Workspaces.kt:191), Xl4 32 (a large title, Parts.kt:559); past them Tailwind's own, on lines as tall as
/// they are, for a number standing alone in a picture (the card shared of the agents at work: Xl6 60).
pub let text_scale : @ui.TextScale = {
  // (the roles: each screen's own, Type's, set by ui_theme: text_roles)
  caption: (11.0, 16.0),
  meta: (12.0, 18.0),
  ui: (13.0, 20.0),
  body: (14.0, 22.0),
  title: (16.0, 24.0),
  heading: (22.0, 30.0),
  display: (28.0, 36.0),
  xs3: (10.0, 14.0),
  xs2: (11.0, 15.4),
  xs: (12.0, 16.8),
  sm: (13.0, 18.2),
  base: (14.0, 19.6),
  lg: (15.0, 21.0),
  xl: (16.0, 22.4),
  xl2: (17.0, 23.8),
  xl3: (22.0, 30.8),
  xl4: (32.0, 44.8),
  xl5: (48.0, 48.0),
  xl6: (60.0, 60.0),
  xl7: (72.0, 72.0),
}

///|
/// The scale with the type's roles this screen has (Type: the web's text-caption … text-display, web/ui
/// tokens.css.ts; a phone's a size up), each on its own line: what a style says by a role (TextSize Caption …
/// Display) is the same size the web's says by it.
fn text_roles(t : Type) -> @ui.TextScale {
  {
    ..text_scale,
    caption: (t.caption, t.caption_line),
    meta: (t.meta, t.meta_line),
    ui: (t.ui, t.ui_line),
    body: (t.body, t.body_line),
    title: (t.title, t.title_line),
    heading: (t.heading, t.heading_line),
    display: (t.display, text_scale.display.1),
  }
}

///|
/// The lines Android says (`lineHeight`), in place of the size's own (Leading): L4 16 (a row's small line in a list:
/// OpenJobs.kt:98, AgentSheet.kt:217, DriveScreen.kt:409, Attach.kt:197), L5 18 (a note, a meta line: Security.kt:110,
/// 485), L6 20 (a file's or a link's card's name: Composer.kt:781, 803; ChatFiles.kt:567; DriveScreen.kt:408), L7 22
/// (a lead, a paragraph: Security.kt:105, 106, 286; Composer.kt:562, 708).
pub let leading_scale : @ui.LeadingScale = {
  ..@ui.LeadingScale::tailwind(),
  l4: 16.0,
  l5: 18.0,
  l6: 20.0,
  l7: 22.0,
}

///|
/// still.fail's corners on mbui's scale (in order): Xl1_5 16 (Smooth(16.dp): a 32 high button or choice, 接管's),
/// Xl2 18 (what waits in the composer, where it is in none of the capsule's corners: Glass.kt InComposerFiles,
/// concentric(ComposerCorner 26, ComposerFilesIn 10), what Android gives Smooth), Xl3 22 (a settings page's card and
/// the waiting cards' shapes: Parts.kt CARD_CORNER, Waiting.kt:185), Xl4 24 (a capsule round a 40 button 4 in: the
/// remote screen's folded tools).
pub let radii : @ui.RadiusScale = {
  ..@ui.RadiusScale::tailwind(),
  xl1_5: 16.0,
  xl2: 18.0,
  xl3: card_corner,
  xl4: 24.0,
}

///|
/// A large title's letters drawn closer (Parts.kt:559, 562 LargeTitle: letterSpacing -0.6sp): off Tailwind's scale
/// (Tight is -0.8 at 32).
pub let large_title_tracking : @ui.Tracking = Exact(-0.6)

///|
/// A message's line (24.75: Chat.kt:1363, 1367, 1374), the one place Android says it.
pub let message_line : @ui.Leading = Exact(24.75)

///|
/// A list card's corner: concentric round its rows (row_corner, list_pad in: 22.8, the ladder's small panels' step, a
/// column of rows as a small panel is; docs/ui-panels.md 圆角阶梯), as Android works it out (Parts.kt:640
/// LIST_CARD_CORNER = concentricOut(LIST_ROW_CORNER, LIST_PAD)); its rows take theirs from it (radius=Inner).
pub let list_card_corner : Double = surface_corner(list_pad, row_corner)

///|
pub let list_card_radius : @ui.Radius = rounded(list_card_corner)

///|
/// A long list's card, drawn a row at a time (page.mbt group_row: the card's corner), and a row's ground at its ends:
/// concentric in it, list_pad in.
pub let group_corner : Double = list_card_corner

///|
pub let group_row_end_radius : @ui.Radius = rounded(inner_corner(group_corner, list_pad))

///|
/// A card with a Seg (rounded 10) in its top corners: concentric with it (Usage.kt:204 concentricOut(10, CARD_PAD)):
/// worked out as Android does, no step of the scale.
pub let seg_card_radius : @ui.Radius = surface(card_pad, 10.0).radius()

///|
/// The usage page's days (Usage.kt Days): the plot 150 high (PLOT), a bar 16 wide at most (BAR), how far a line of the
/// scale's words stand over it (their line, Xs3's 14, and 2), and a part's corner (4; 2 with many days: Base, Sm).
pub let usage_plot : Double = 150.0

///|
pub let usage_plot_h : @ui.Len = Fixed(usage_plot)

///|
pub let usage_bar_max : @ui.Len = Fixed(16.0)

///|
pub let usage_tick_rise : Double = 16.0

///|
pub let usage_part_r : Double = 4.0

///|
pub let usage_part_r_many : Double = 2.0

///|
/// A small dot's side, how a thing stands (7: PageParts.kt:465 PresenceDot, Security.kt:101 Dot).
pub let dot_size : @ui.Len = Fixed(7.0)

///|
/// An option of a segmented choice in the wide frame, at its narrowest (the web's 105, controls.css.ts seg, less the
/// track's inset on both sides).
pub let seg_pill_min : @ui.Len = Fixed(101.0)

///|
/// A code's box's edge: the words' colour at 18%.
pub let code_edge : @ui.Color = A(Fg, Exact(0.18))

///|
/// A column a phone's width at most, in the middle (phone_column): its widest.
pub let phone_max : @ui.Len = Fixed(420.0)

///|
/// A bar's round button (Parts.kt NavButton): 34 across.
pub let nav_button_side : @ui.Len = Fixed(34.0)

///|
/// A hairline across (0.5: a panel's rule over its foot).
pub let hairline : @ui.Len = Fixed(0.5)

///|
/// The theme as mbui's (its Theme's roles over this frame's palette: the paper's, light or dark), with still.fail's
/// sizes of words: what the styles' tokens are looked up in.
pub fn ui_theme() -> @ui.Theme {
  let t = current.val
  // (the same one while its palette and its sizes of words are: what was built in it is as it would be built again,
  // a list's rows kept so, mbui's kept_nodes.mbt)
  match ui_theme_made.val {
    Some((p, tt, made)) if physical_equal(p, t.p) && physical_equal(tt, t.t) => return made
    _ => ()
  }
  let made = ui_theme_of(t)
  ui_theme_made.val = Some((t.p, t.t, made))
  made
}

///|
/// The theme as mbui's last made (ui_theme), and the palette and sizes of words it was made of.
// kept across runs: worked out of a table and the palette, the same for the same
let ui_theme_made : Ref[(Palette, Type, @ui.Theme)?] = Ref(None)

///|
fn ui_theme_of(t : Theme) -> @ui.Theme {
  let base = if t.dark { @ui.Theme::narrow_dark() } else { @ui.Theme::narrow_light() }
  // a link's ink: the accent's ink (the darker one on paper, the lighter in the dark), which reads in words; the
  // accent itself in the dark was 4.3 to 1 on a raised ground (docs/ui-panels.md 对比度)
  {
    ..base,
    text: text_roles(t.t),
    leading: leading_scale,
    radii,
    link: t.p.accent_text,
    // a tone's ink and ground the palette's (a ground the ink at an opacity: tone_light), what a style's AccentText,
    // AccentBg, Danger, DangerBg and WarnInk say, not mbui's own still.fail theme's opaque grounds
    accent_text: t.p.accent_text,
    accent_bg: t.p.accent_bg,
    danger: t.p.red,
    danger_bg: t.p.red_bg,
    warn_ink: t.p.warn_ink,
    // the greys Android's (Theme.kt C.muted, C.subtle: the palette's), not mbui's own paper theme's lighter dark ones:
    // what a style's Muted and Subtle say
    muted: t.p.muted,
    subtle: t.p.subtle,
    // the outline the palette's too: what a style's Border says is `p.line_strong`
    border: t.p.line_strong,
    // the panes' grounds the palette's (touch's sidebar a step under its beige page, what is chosen a step
    // under that): what a style's Sidebar and Selected say, not mbui's narrow theme's, which has the web's
    sidebar: t.p.sidebar,
    selected: t.p.selected,
    // a line of words that say none 1.4 of their size, as the web's root (`line-height: 1.4`) and Android's (Theme.kt
    // WebType: 1.4.em)
    text_line: 1.4,
    corner_ladder,
    corner_fit: Some(corner_fit),
    lit_apart,
    lit_reach,
    // the app's own words with digits all one width, as the web's root (`font-variant-numeric: tabular-nums`): a
    // percentage, a time running, a count keep their width as they change; what people wrote keeps the font's own
    tabular: true,
  }
}

///|
/// The composer's files' row: the gap between what waits in it (Composer.kt: 6 and a remove button's reach past a
/// picture), and the room kept at its end for the last button's reach (Composer.kt `beyond + PictureRemoveOut`).
pub let files_gap : @ui.Space = Exact(11.0)

///|
pub let files_row_end : @ui.Space = Exact(7.0)

///|
/// A page's bar (Parts.kt NavBar): the title kept 84 clear of the bar's sides; the gap in the line under the title (5).
pub let nav_title_clear : @ui.Space = Exact(84.0)

///|
pub let nav_sub_gap : @ui.Space = space_5

///|
/// 5, off the scale's 4 and 6: the gap in the line under a bar's title (nav_sub_gap), a row's room above and under in
/// a sheet of chats (Composer.kt askToShare: padding(vertical = 5)).
pub let space_5 : @ui.Space = S1_25

///|
/// A tag's widest (PageParts.kt StationTag: widthIn(max = 104)).
pub let tag_max : @ui.Len = Fixed(104.0)

///|
/// A chat in the `@` menu at its lowest (Composer.kt ChatRefMenu: heightIn(min = 44)).
pub let ref_row_min_h : @ui.Len = Fixed(44.0)

///|
/// The sign-in page's (SignIn.kt): its title 28, bold, on the font's own line (28.sp), off the scale between Xl3's
/// 22 and Xl4's 32; its sides 30 (padding(horizontal = 30.dp)), between S7's 28 and S8's 32.
pub let sign_in_title_size : @ui.TextSize = Exact(28.0, 39.2)

///|
pub let sign_in_side : @ui.Space = Exact(30.0)

///|
/// The card shared of the agents at work (sfpages' stations_now.mbt): the same in either theme, as a poster is, and in
/// still.fail's own colours (design/brand: words and one orange dot; 2026-10-26 用户「分享卡片的颜色搞高级点」): night,
/// plain (a faint orange light at its top was seen as a brown stain), its words white and white thinned for what is
/// said of them, its cards the white barely, still.fail's orange only for its dot, its first ring, today and what is
/// at work now, the other rings white and grey.
pub let share_ground : Int64 = 0x111114FFL

///|
/// How wide it is laid out: one picture whatever it is seen on (2026-10-26 用户「感觉分享图片不应该分电脑和手机…按最合理的
/// 布局生成」), a portrait poster as a phone shows what is shared (1080 pixels across at a phone's 3), laid out the one
/// way (narrower only where its room is), drawn smaller where it has not the room's height (a short window:
/// @sf.whole_fitted).
pub let share_w_most : Double = 360.0

///|
pub let share_ink : Int64 = 0xF4F4F5FFL

///|
/// (thinned to 62%: 7.0 to 1 on the night, 6.5 on a card: docs/ui-panels.md 对比度)
pub let share_dim : Int64 = 0xF4F4F59EL

///|
/// A span's card: the white at 6% over the night, no shadow (none is seen on it).
pub let share_card : Int64 = 0xF4F4F50FL

///|
/// What a day's bar is drawn in (today's still.fail's orange): the white thinned, seen on the night.
pub let share_bar : Int64 = 0xF4F4F52EL

///|
/// The rings of the subscriptions' weekly quota, one a kind, in this order: still.fail's orange, its white, a grey.
// kept across runs: a table, never written
pub let share_rings : Array[Int64] = [share_orange, share_ink, share_ring_grey]

///|
/// The third ring's grey, between the white and the night.
pub let share_ring_grey : Int64 = 0x8E8E95FFL

///|
/// A ring's turn past its first (@sf.rings: a share past 1): this much of the turn before's colour, the rest black,
/// as Activity's ring going round again is deeper.
pub let ring_turn_keep : Double = 0.82

///|
/// still.fail's orange (design/brand), words in it too: 6.1 to 1 on the night.
pub let share_orange : Int64 = 0xE5704AFFL

///|
/// The card shared's other looks (2026-10-27 用户：「再搞几版骚气的分享图片模板，让用户可以选择」), chosen under it, each
/// the same in either theme as the night is. 大字报: still.fail's orange to its edges, the night's black on it (6.1 to 1),
/// said of in that black at 82% (4.9 to 1), the dot of still.fail white; its band of figures the black, the orange on
/// it.
pub let share_poster_ground : Int64 = 0xE5704AFFL

///|
pub let share_poster_ink : Int64 = 0x111114FFL

///|
pub let share_poster_dim : Int64 = 0x111114D1L

///|
/// Its number: the scale's largest (Xl7, 72) drawn larger, as its line holds four of its figures and the percent (104);
/// 1234% and past, 80.
pub let share_poster_number_scale : Double = 1.45

///|
pub let share_poster_number_less : Double = 1.12

///|
/// Its insides at least this tall: the picture 360 by 480, a portrait's three to four, as a post shows one whole.
pub let share_poster_least_h : @ui.Len = Fixed(440.0)

///|
/// 小票: a till's paper, its ink nearly black (15.2 to 1), said of in that ink at 62% (4.6 to 1), in the code face;
/// still.fail's orange deepened for the paper (4.6 to 1: words in it too), its dashes the ink thinned.
pub let share_receipt_ground : Int64 = 0xF5F2EAFFL

///|
pub let share_receipt_ink : Int64 = 0x1C1C1EFFL

///|
pub let share_receipt_dim : Int64 = 0x1C1C1E9EL

///|
pub let share_receipt_orange : Int64 = 0xB84A28FFL

///|
pub let share_receipt_rule : Int64 = 0x1C1C1E59L

///|
/// A dash of its torn lines: a point and a half high.
pub let share_receipt_dash_h : @ui.Len = Fixed(1.5)

///|
/// 终端: a terminal's black, its words a light grey (15.4 to 1), said of in it at 62% (6.3 to 1), in the code face;
/// still.fail's orange its prompt, its first meter, today and its cursor (6.2 to 1); a meter's cells unfilled the grey
/// thinned.
pub let share_terminal_ground : Int64 = 0x0E0F11FFL

///|
pub let share_terminal_ink : Int64 = 0xE6E6E6FFL

///|
pub let share_terminal_dim : Int64 = 0xE6E6E69EL

///|
pub let share_terminal_cell : Int64 = 0xE6E6E624L

///|
/// Its cursor: a block 8 by 16, as a line of its words is tall (the palette's colours as tall).
pub let share_terminal_cursor_w : @ui.Len = Fixed(8.0)

///|
pub let share_terminal_cursor_h : @ui.Len = Fixed(16.0)

///|
/// A line's key's column: as wide as its longest key (devices, archived) in the code face.
pub let share_terminal_key_w : @ui.Len = Fixed(64.0)

///|
/// Its palette, as a fetch shows the terminal's: still.fail's orange, deepened and on paper, the greys from the
/// light to the night's.
// kept across runs: a table, never written
pub let share_terminal_palette : Array[Int64] = [
  share_orange, share_receipt_orange, share_receipt_ground, share_terminal_ink, share_ring_grey, 0x5A5B61FFL, 0x45464CFFL,
  0x2E2F34FFL,
]

///|
/// Its window's three dots: the grey thinned.
pub let share_terminal_dot : Int64 = 0xE6E6E640L

///|
/// The looks to choose under the card shared, each a small picture of it: a portrait 36 by 48 in its own ground (a
/// small block's corner), a ring round the chosen one 3 out (concentric), its name under it.
pub let share_look_tile : @ui.Style = @ui.style(w=Fixed(36.0), h=Fixed(48.0), radius=small_radius, clip=true)

///|
pub let share_look_in : @ui.Space = room(3.0)

///|
pub let share_look_ring : @ui.Radius = rounded(@ui.concentric_out(small_corner, 3.0))

///|
/// A picture shown alone to be handed out (a panel's `stage`: the card to share): the window under it the night at
/// 92% (all but gone: at 80% a phone's bars and their notch showed through round its buttons), whatever the theme (2026-10-26 用户「分享的弹窗有点丑，感觉应该给分享特制一个逼格高点的」), the picture's edge a
/// hairline of the white over it (the night on the night otherwise), its buttons under it on the night.
pub let stage_scrim : Int64 = 0x0B0B0DEBL

///|
pub let stage_edge : Int64 = 0xF4F4F51FL

///|
/// A button on the stage (button's, `on_night`): the primary the white, its words the night; the others the white at
/// 12%, a step more pointed at, their words the white.
pub let stage_plain : Int64 = 0xF4F4F51FL

///|
pub let stage_plain_lit : Int64 = 0xF4F4F533L

///|
/// A picking row's line under its words (Controls.kt PickRow: 12.sp on 17.sp), between L4's 16 and L5's 18.
pub let pick_sub_line : @ui.Leading = Exact(17.0)

///|
/// The search (Search.kt): its field on the ink at 6% (as high as what stands over a sidebar's list: ChatList band_h,
/// 38 with touch as FIELD); a row found 66 high (HitRow, ItemRow; 50 an item with no line of words), its first line 22;
/// what a row found says starts 22 in.
pub let search_ground : @ui.Color = A(Fg, Exact(0.06))

///|
pub let found_row_h : @ui.Len = Fixed(66.0)

///|
pub let found_row_short_h : @ui.Len = Fixed(50.0)

///|
pub let found_line_h : @ui.Len = Fixed(22.0)

///|
pub let found_start : @ui.Space = Exact(22.0)

///|
/// What takes the room left in a row or a column (Compose's `weight(1f)`).
pub let grow : @ui.Len = Grow(1.0)

///|
/// Words on one line given the room left in their row, cut there with an ellipsis (Compose's Text with maxLines = 1
/// in a Row: measured in what is left).
pub let line_left : @ui.Size = Fill(1.0)

///|
/// A card as wide as what holds it (card's `fill`): one whose words change as it is answered, its width not with them.
pub let card_across : @ui.Size = Fill(1.0)

///|
/// A visualization in a message (Android ui/Viz.kt, chat/VizFiles.kt): its place while it comes (120 high), the ways
/// under it (22 boxes); a whole page's corners (Smooth 20, the web's card) on its paper (#F6F2EA, dark #26272B); the
/// full screen's name 18 in (Viz.kt VizFull).
pub let viz_wait_h : @ui.Len = Fixed(120.0)

///|
pub let viz_way_side : @ui.Len = Fixed(22.0)

///|
pub let viz_card_radius : @ui.Radius = Exact(20.0)

///|
pub let viz_paper : @ui.Color = Exact(0xF6F2EAFFL)

///|
pub let viz_paper_dark : @ui.Color = Exact(0x26272BFFL)

///|
pub let viz_full_in : @ui.Space = S4_5

///|
/// Marking a service's page (Preview.kt MarkMode, MarksOver, Note): its bar 30 high (a capsule), 添加到对话 (24 high)
/// and the dot's ring (13) in its ends where they are concentric with them (capsule_end_room: 3 in at its end, 8.5 at
/// its start), 添加到对话's icon and words 5 apart; the edit key's ground the accent's 14%, the ring's 22%, an open
/// mark's 8%; what floats over the page frosted thick (the surface at 94%; dark, surface2's); a pin's number 11; what is
/// said of a mark 26 high.
pub let mark_bar_h : @ui.Len = Fixed(mark_bar_side)

///|
let mark_bar_side : Double = 30.0

///|
pub let mark_bar_end : @ui.Space = capsule_end_room(mark_bar_side, mark_put_side)

///|
let mark_put_side : Double = 24.0

///|
pub let mark_bar_start : @ui.Space = capsule_end_room(mark_bar_side, mark_ring_side)

///|
pub let mark_put_gap : @ui.Space = space_5

///|
pub let mark_ring : @ui.Len = Fixed(mark_ring_side)

///|
let mark_ring_side : Double = 13.0

///|
pub let mark_key_on : @ui.Color = A(Accent, Exact(0.14))

///|
pub let mark_ring_bg : @ui.Color = A(Accent, Exact(0.22))

///|
pub let mark_open_bg : @ui.Color = A(Accent, Exact(0.08))

///|
pub let mark_bubble : @ui.Color = A(Card, Exact(0.94))

///|
pub let mark_bubble_dark : @ui.Color = Exact(0x2C2D31F0L)

///|
pub let mark_pin_size : @ui.TextSize = Exact(11.0, 15.4)

///|
pub let mark_said_h : @ui.Len = Fixed(26.0)

///|
/// How much of a file has come (FilePreview.kt FileProgress): 220 wide.
pub let file_progress_w : @ui.Len = Fixed(220.0)

///|
/// A size typed (Preview.kt CustomSize): its fields 72 wide, 10 round.
pub let custom_field_w : @ui.Len = Fixed(72.0)

///|
pub let custom_field_r : @ui.Radius = Exact(10.0)

///|
/// The same field with keyboard and mouse (ViewportSize.css.ts field: 52 wide).
pub let custom_field_dense_w : @ui.Len = Fixed(52.0)

// ---------------------------------------------------------------------------
// A station's screen, seen and driven (Android app/remote/ScreenViewer.kt): its sizes off the steps, as Android says
// them.

///|
/// A sidebar's row, every sidebar's (Sidebar.css.ts navRow, navSession; SidebarList.css.ts item): the ladder's row
/// (row_corner), as a list card's rows and a menu's are. The web's nav corner (12, as a field's and an option's) is a
/// row's; on the ladder a row is 18, so a one-line row (32) is round at its ends as a menu's row is, and a chat's (54)
/// as a list card's.
pub let side_row_radius : @ui.Radius = row_radius

///|
/// A chat's row in the wide frame's sidebar (Sidebar.css.ts navSession: two lines, 20 and 18, 2 apart, 7 above and
/// under).
pub let side_row_h : @ui.Len = Fixed(54.0)

///|
/// A person's picture after the first at a sidebar row's end (RowPicture.css.ts: 16 across, 3 over the one before):
/// the room it takes.
pub let side_face_step : @ui.Len = Fixed(13.0)

///|
/// The same at a finger's row's end (mobile/Home.tsx RowAside size 18): 15 the room after the first, the starter's ring
/// 22 across (2 past the face's ground).
pub let touch_face_step : @ui.Len = Fixed(15.0)

///|
pub let touch_face_ring : @ui.Len = Fixed(22.0)

///|
/// The dot before a chat that wants the viewer in 待处理's panel (Attention.css.ts dot): 7 across.
pub let attention_dot : @ui.Len = Fixed(7.0)

///|
/// The side rail (60), a file's key (34), a progress track's height (3), the bounds of what floats over the frame
/// (接管 480, the rail's line 280, what an ended view says 320).
pub let rail_w : @ui.Len = Fixed(60.0)

///|
pub let row_key : @ui.Len = Fixed(34.0)

///|
pub let track_h : @ui.Len = Fixed(3.0)

///|
pub let take_over_max : @ui.Len = Fixed(480.0)

///|
pub let rail_say_max : @ui.Len = Fixed(280.0)

///|
pub let ended_max : @ui.Len = Fixed(320.0)

///|
/// A button's height on the phone (Controls.kt BUTTON_HEIGHT 38).
pub let button_38 : @ui.Len = Fixed(38.0)

///|
/// A link's card in a message (ScreenLinks.kt, AdbLinks.kt): 236 wide; a screen's with its preview over its words 280.
pub let link_card_w : @ui.Len = Fixed(236.0)

///|
pub let peek_card_px : Double = 280.0

///|
pub let peek_card_w : @ui.Len = Fixed(peek_card_px)

///|
/// How far in from the card's top and sides its preview lies (its corners concentric with the card's).
/// (S1 in its style: screen_links.mbt peek_card)
pub let peek_card_in_px : Double = 4.0

///|
/// The preview's width: the card's less its room on both sides.
pub let peek_frame_px : Double = peek_card_px - 2.0 * peek_card_in_px

///|
/// A link's card's mark, 30 wide (36 high: S9), as the web's.
pub let link_mark_w : @ui.Len = Fixed(30.0)

///|
/// A quiet ground under what is grouped on a sheet (Publish.kt: the ink at 4%).
pub let faint_ground : @ui.Color = A(Fg, Exact(0.04))

///|
/// How wide a face's status at its row's end may be (Fonts.kt:142).
pub let face_status_most : @ui.Len = Fixed(140.0)

///|
/// A Slack app's icon as it is in its look (SlackApp.kt AppLook: 72 square), off the scale.
pub let app_icon_side : @ui.Len = Fixed(72.0)

///|
/// A choice's line on a card (Parts.kt PickLine): 11 over and under (as files_gap), rounded 10 (as custom_field_r),
/// its check in a room 18 wide at its end.
pub let pick_line_y : @ui.Space = files_gap

///|
pub let pick_line_r : @ui.Radius = custom_field_r

///|
pub let check_room_w : @ui.Len = Fixed(18.0)

///|
/// A person's initial on their colour (Parts.kt Avatar: Color.White), on every theme.
pub let face_ink : Int64 = 0xFFFFFFFFL

///|
/// A sheet's grabber (Sheet.kt SheetGrab): 38 × 5, round at its ends (its 3 capped at half its height, as every
/// renderer draws it; its colour the palette's line, said where it is drawn).
// kept across runs: a value (no field of it changes)
pub let sheet_grabber : @ui.Style = @ui.css("w=Fixed(38.0) h=Fixed(5.0) radius=Full")

///|
/// A tip's widest (the web's parts.css.ts tooltip: 300).
pub let tip_max : @ui.Len = Fixed(300.0)

///|
/// A login card's on a desktop's width (the web's MachineLogins.css.ts card): 360 at least where there is the room
/// (min(100%, 360px)), and its corner its padding and its × pill's half (8 + 12: the web's card's 20, as a
/// visualization's).
pub let login_card_least : @ui.Len = Within(360.0)

///|
/// A login card's widest (the web's card: min(100%, 560px), a vault item's card's): what it holds past that wraps.
pub let login_card_most : @ui.Len = Fixed(560.0)

///|
/// An agent's request about a vault item as its card in a chat (the web's VaultAsk.css.ts card): as wide as what it
/// says, 320 at least where there is the room (min(100%, 320px)), 560 at most and never wider than the room (min(100%,
/// 560px): a Cut box's max in a column).
// kept across runs: a value (no field of it changes)
pub let ask_card_room : @ui.Style = @ui.css("w=Cut min_w=Within(320) max_w=Fixed(560)")

///|
/// The same as wide as it may be whatever it says (560, never wider than the room): one whose words change as it is
/// answered (a file picked on it) and is not to change its width with them.
// kept across runs: a value (no field of it changes)
pub let ask_card_room_most : @ui.Style = @ui.css("w=Cut min_w=Within(560) max_w=Fixed(560)")

///|
pub let login_card_corner : @ui.Radius = rounded(ask_corner)

///|
pub let file_sheet_w : @ui.Len = Fixed(30.0)

///|
pub let file_sheet_h : @ui.Len = Fixed(36.0)

///|
/// A file card's own button (Chat.css.ts fileCardRemove: 22 round).
pub let file_card_button : @ui.Len = Fixed(22.0)

///|
/// A name over a message at its widest (Chat.css.ts msgHead msgName: 240).
pub let name_max : @ui.Len = Fixed(240.0)

///|
/// A small square button beside a line (the web's activityStop, a file card's remove: 22).
pub let small_button : @ui.Len = Fixed(22.0)

///|
/// The pill offering to quote what is picked (the web's Chat.css.ts quotePop: 26 high).
pub let quote_pop_h : @ui.Len = Fixed(26.0)

///|
/// The widest a page is laid out as the web's narrow app lays its pages out (max-width 640, where its narrow app takes
/// over): wider, as its desktop pages are. A page's own width, not the tier (docs/architecture.md Pages).
pub let page_narrow_most : Double = 640.0

///|
/// A choice standing over the composer (the web's mobile NewChat.css.ts mChooser: 30 high, a capsule of the
/// composer's glass), the widest a station's name in it is.
pub let glass_chooser_h : @ui.Len = Fixed(30.0)

///|
pub let glass_chooser_station_most : @ui.Len = Fixed(128.0)

///|
/// A page's bar in the wide frame (the web's sidebar.css.ts pageBar: 45 high).
pub let wide_bar_h_size : @ui.Len = Fixed(wide_bar_h)

///|
pub let wide_bar_h : Double = 45.0

///|
/// A bar's round button's side (icon_button's 32: drawn so on either hand, a finger reaching it from round it).
pub let bar_key_side : Double = 32.0

///|
/// The room between keys `size` across side by side (a bar's, a player's, a viewer's tools): as much as makes each a
/// press's room across (@ui.room_least: 36 with keyboard and mouse, 44 with touch; rule 2: drawn smaller, its room is
/// not), `least` at least (the look's own room between them, where it has more: 2). Only the room between keys: one
/// at a row's end stands where it stood (concentric with its corner).
pub fn keys_gap(size? : Double = bar_key_side, least? : Double = 2.0) -> @ui.Space {
  room(keys_apart(size~, least~))
}

///|
/// keys_gap's room as a number (where it is worked into a width: a key coming in with the room before it).
pub fn keys_apart(size? : Double = bar_key_side, least? : Double = 2.0) -> Double {
  dmax(least, @ui.room_least() - size)
}

///|
/// A row of tools' own room between them (tools_line, a folder's actions: 6), keys_gap's least there.
pub let tools_apart : Double = 6.0

///|
/// A row of keys `size` across (a bar's, a player's group, a viewer's tools): keys_gap between them, in its middle.
pub fn keys_row(size? : Double = bar_key_side) -> @ui.Style {
  keys_row_look.then(@ui.style(gap=keys_gap(size~)))
}

///|
// kept across runs: a value (no field of it changes)
let keys_row_look : @ui.Style = @ui.css("row align=ACenter")

///|
/// A page's bar in a panel of the tape (laid out Medium, its corners pane_round): its buttons (32 across) on the tape's
/// one line, where they are concentric with the tape's corner, its bar as much taller over them
/// (`tape_bar_over`: every bar of the tape and the sidebar's first row on it); at its end as far in as makes the last
/// concentric with the panel's top right corner (capsule_fit), else clear of it (as far in as it is round, or where it
/// stands in the wide frame, `alone`, if that is further: nothing of the bar's in a corner it can not be concentric
/// with: a Mac's page at the window's edge, its corner the window's) (`tape_bar_end`); a round button at its start (a
/// settings page's back) so in its top left one (`tape_bar_start`); `side` the last's height (a round button's 32:
/// line_end_in; a capsule's of words, its own).
pub fn tape_bar_end(alone : Double, side? : Double = bar_key_side) -> Double {
  // (the panel at the window's right edge, the window's own buttons over its top right corner where they are the
  // app's: its bar's last before them, alone: window_keys)
  if pane_at_window_right() && @ui.window_keys_own() {
    return window_keys_room_tape() - window_in + alone
  }
  match pane_top_right() {
    Some(k) => line_end_in(k, alone, side~)
    None => alone
  }
}

///|
/// Whether the panel of its own the view is built in stands at the window's right edge (its top right corner the
/// window's, tape_corners' `right`).
pub fn pane_at_window_right() -> Bool {
  match pane_round.val {
    Some(k) => k[1] == tape_edge
    None => false
  }
}

///|
pub fn tape_bar_start(alone : Double, side? : Double = bar_key_side) -> Double {
  match pane_radii() {
    Some(k) => line_end_in(k[0], alone, side~)
    None => alone
  }
}

///|
/// How far in from its side the round button ending a row on the tape's line (a bar's, the sidebar's first row's filter)
/// stands in a corner `corner` round (tape_bar_end, tape_bar_start), `side` across (a bar's 32; a capsule of words its
/// height): on the line in the tape's corner, concentric with it (tape_line: a taller one as far in as makes it so, its
/// middle on the line); in one that follows the window (too square for a button there) clear of it.
pub fn line_end_in(corner : Double, alone : Double, side? : Double = bar_key_side) -> Double {
  if (corner - tape_corner).abs() <= 0.5 || capsule_fits(corner, side) {
    capsule_in(corner, side)
  } else {
    dmax(alone, corner)
  }
}

///|
/// How far in from the window's side a bar's last button stands at the window's top corner in a window's whole: where
/// the bar's buttons follow the window's corner (bar_keys_link: a Mac's 16), as far as from the bar's top, so concentric
/// with it; else `alone`, as in a square window.
pub fn window_end_in(alone : Double) -> Double {
  // (the window's own buttons there where the app draws them: the bar's last before them, alone: window_keys)
  if @ui.window_keys_own() {
    return window_keys_room() + alone
  }
  match bar_keys_link() {
    Some(link) if link.follows() => bar_keys_top()
    _ => alone
  }
}

///|
/// How far in from the window's side what ends a bar stands at the window's top corner where it is a long capsule (⌘F's
/// field, 复制图片, 只看/控制): past the window's corner by `alone` (window_corner_past); before the window's own buttons
/// where they are the app's.
pub fn window_clear_in(alone : Double) -> Double {
  if @ui.window_keys_own() {
    return window_keys_room() + alone
  }
  window_corner_past(alone)
}

///|
/// How far in from the window's side a long capsule stands that would be by the window's corner `alone` in (its other
/// edge in the corner's band: a bar's, a page's foot's): past the corner by `alone` (a Mac's 16, 12: 28), not by an arc
/// it cannot follow (the user, 2026-10-30: 只有长胶囊不行, a circle there a block following it, bar_keys_link); `alone`
/// where that is past it already (Windows 11's 8), or there is none.
pub fn window_corner_past(alone : Double) -> Double {
  let window : @ui.CornerOf = Window
  let r = window.radius()
  if r > 0.0 && alone < r + corner_fit.near {
    r + alone
  } else {
    alone
  }
}

///|
/// How far in from both its edges a circle floating in a corner of the window stands (a remote screen's 全屏 tools,
/// its mouse's buttons): clear of a corner too square for it to be concentric with (a Mac's 16 for a 44 circle), as
/// far in as it is round; else `alone`. Not a block following it: a floating button keeps its shape.
pub fn window_corner_clear(alone : Double) -> Double {
  let window : @ui.CornerOf = Window
  dmax(alone, window.radius())
}

///|
/// The corner a bar's buttons share in a window's whole (a page's bar, a side panel's, the files' page's: one for all of
/// them, as the rail's places' grounds, the settings' among them, have one): the window's followed from as far in as
/// the last stands from the bar's top and side at its corner (window_end_in), a block concentric with it where the
/// window's corner lets one follow it (a Mac's 16, 6 in: 11.2); round where it does not (a square window's, Windows 11's
/// 8). Not a circle beside an arc it could never follow (the user, 2026-10-25: as the settings' ground is). None in a
/// panel of its own on the tape, where the bar's buttons are round on the tape's line, concentric with its corner.
pub fn bar_keys_link() -> @ui.CornerOf? {
  // (not in the window's corner where its own buttons are there, the app's: window_keys)
  if in_pane() || @ui.window_keys_own() {
    return None
  }
  Some(window_corner_key())
}

///|
/// The corner of a bar's key standing at the window's top corner (bar_keys_link, the window's own buttons' last):
/// the window's followed from as far in as it stands from the top (bar_keys_top), round where it cannot be.
pub fn window_corner_key() -> @ui.CornerOf {
  Follow(Window, bar_keys_top(), bar_key_side / 2.0)
}

///|
/// How far under a bar's top its buttons stand (a bar 45 high, its line under it; a 32 button's 6).
pub fn bar_keys_top() -> Double {
  dmax(0.0, (wide_bar_h - hairline_h - bar_key_side) / 2.0)
}

///|
/// How far in from its start a bar whose first thing stands wherever the room left puts it (the files' bar: what is done
/// to the folder, at its end) keeps clear of the panel's top left corner: as far in as it is round, or `alone`, if that
/// is further.
pub fn tape_bar_clear_start(alone : Double) -> Double {
  match pane_radii() {
    Some(k) => dmax(alone, k[0])
    None => alone
  }
}

///|
pub fn tape_bar_over() -> Double {
  dmax(0.0, tape_line - (wide_bar_h - hairline_h - 32.0) / 2.0)
}

///|
pub fn tape_bar_over_room() -> @ui.Space {
  room(tape_bar_over())
}

///|
/// A bar's line under it (its pb: SPx).
let hairline_h : Double = 1.0

///|
/// A card over what the pointer rests on (the web's Hover.css.ts card: 320 wide; a tile's 220 at least, 420 at most),
/// and an agent's in it (AgentCard.css.ts: 288).
pub let hover_card_w : @ui.Len = Fixed(320.0)

///|
pub let hover_tile_least : @ui.Len = Fixed(220.0)

///|
pub let hover_tile_most : @ui.Len = Fixed(420.0)

///|
pub let agent_card_w : @ui.Len = Fixed(288.0)

///|
/// parts.tsx's measures off the scale (parts.css.ts, own.css.ts, styles/spinner.css.ts): a switch (36 by 22, its thumb
/// 2 in; small 26 by 16), a pill (22 high, 9 in), a status dot's ring (1.5), a section's note (3 under its title, 52em
/// of its 12 at most), the first one (480 at most, its line 34em of its 13), a spinner (14; in a line of small text 12).
pub let switch_w : Double = 36.0

///|
pub let switch_h : Double = 22.0

///|
pub let switch_small_w : Double = 26.0

///|
pub let switch_small_h : Double = 16.0

///|
pub let switch_in : Double = 2.0

///|
pub let pill_h : Double = 22.0

///|
pub let pill_in : Double = 9.0

///|
pub let status_ring : Double = 1.5

///|
pub let section_note_gap : Double = 3.0

///|
pub let section_note_most : @ui.Len = Fixed(624.0)

///|
pub let first_most : @ui.Len = Fixed(480.0)

///|
pub let first_lead_most : @ui.Len = Fixed(442.0)

///|
pub let spinner_size : Double = 14.0

///|
pub let spinner_inline : Double = 12.0

///|
/// A dialog's widths (parts.css.ts dialog 520, dialogWide 640), how far short of the window's it stays at most (32),
/// and its close button (32 round).
pub let dialog_w : Double = 520.0

///|
pub let dialog_wide_w : Double = 640.0

///|
pub let dialog_margin : Double = 32.0

///|
pub let dialog_close : Double = 32.0

///|
/// A dialog's corner (DIALOG_PAD 24 and a pill's half height 18) and shadow (0 24px 64px: a blur's deviation half its
/// CSS radius).
pub let dialog_r : Double = pane_corner

///|
pub let dialog_shadow : Double = 32.0

///|
pub let dialog_shadow_y : Double = 24.0

///|
/// A select (parts.css.ts select: 200 wide by default; its chevron 14), choices 8 apart; a confirm (dialogAlert, 420
/// wide); a small panel's icon button's icon (16); a chooser's chevron (12); a copy's check (1.6 s).
pub let select_w : Double = 200.0

///|
pub let select_chevron : Double = 14.0

///|
pub let choice_gap : Double = 8.0

///|
pub let confirm_w : Double = 420.0

///|
pub let panel_icon_size : Double = 16.0

///|
pub let chooser_chevron : Double = 12.0

///|
/// A menu's item at least with keyboard and mouse (controls.css.ts menuItem: 34 high), a capsule its panel's padding in
/// from its corner, concentric with it (capsule_in(r_menu, 34) = panel_pad: what r_menu is made of). With touch a
/// finger's 44 (Theme::rows pick), its words in its middle, round as a row taller than the capsule is (panel_in: the
/// ladder's 18).
pub let menu_row_min : Double = 34.0

///|
/// A small panel's row (a menu's item, the `@` menu's chat, a picker's) as high as the screen's at least (Theme::rows
/// pick: keyboard and mouse's 34, a finger's 44, docs/architecture.md: touch targets 44 at least with touch), for a row
/// given as a style.
pub fn pick_high() -> @ui.Style {
  if theme().touch {
    pick_high_narrow
  } else {
    pick_high_wide
  }
}

///|
/// A small panel's row's margins over and under it reaching `reach` past the panel's padding where it is the `first`
/// or the `last` in it (menu_row_reach), none where it is not.
pub fn ends_reach(reach : Double, first : Bool, last : Bool) -> (Double, Double) {
  let none = 0.0
  (if first { -reach } else { none }, if last { -reach } else { none })
}

///|
/// A small panel's row as high as pick_high, its words text_in in from its ground (a menu's item): reaching past the
/// panel's padding where it is a capsule, to stand concentric with the panel's corners (menu_row_reach), its words
/// where they were.
pub fn pick_reach() -> @ui.Style {
  let r = menu_row_reach(theme().rows.pick)
  @ui.style(mx=room(-r), px=room(text_in + r))
}

///|
// kept across runs: a value (no field of it changes)
let pick_high_wide : @ui.Style = @ui.style(min_h=Fixed(wide_rows.pick))

///|
// kept across runs: a value (no field of it changes)
let pick_high_narrow : @ui.Style = @ui.style(min_h=Fixed(narrow_rows.pick))

///|
/// Over and under a menu's item's line of words (20): as high as menu_row_min (menuItem: 7).
pub let menu_row_over : Double = 7.0

///|
/// Where a small panel's button (a 24 pill or circle: panel_pill) stands at the end of a menu's row: in the row's
/// capsule end, concentric with it, past the row's padding to there, the row no taller for it (a row of words is as
/// high, its ＋ or × in it or not).
pub let menu_row_end : @ui.Style = @ui.style(
  mr=room(capsule_in(menu_row_min / 2.0, panel_pill, room=menu_row_min / 2.0) - text_in - menu_row_reach(menu_row_min)),
  my=room((menu_row_min - 2.0 * menu_row_over - panel_pill) / 2.0),
)

///|
/// A line between a small panel's parts (@sf.menu_rule): 1 high, as wide as where it is, the words' ink faintly (in
/// dark the panel is lighter than the page: its line a groove; kit's menu_rule_look).
pub let rule_line : @ui.Style = @ui.css("w=Full h=SPx")

///|
pub fn rule_ink(c : @ui.Ctx) -> Int64 {
  @ui.alpha(c.theme().fg, 0.12)
}

///|
/// Nothing under it, no ring round it.
pub let no_ground : Int64 = 0L

///|
pub let no_ring : Double = 0.0

///|
/// A length off the scale, as a style's room (padding, margins: below 0 for a margin): align.mbt's.
fn room(x : Double) -> @ui.Space {
  Exact(x)
}

///|
/// A corner off the scale, as a style's: align.mbt's.
fn rounded(x : Double) -> @ui.Radius {
  Exact(x)
}

///|
/// A toast (toast.css.ts): 20 round, a capsule while its words fit one line (20 high, 10 over and under them), 18 in
/// from its start, 560 wide at most, 24 over the window's foot, a floating shadow (0 8px 24px), coming in from 8 below.
/// Its button (an archive's 撤销) a capsule 28 high in its end, concentric with it (capsule_in: 6 from its top, foot
/// and end), its words as far from the toast's end as the toast's words are from its start (6 + 12 = 18).
pub let toast_r : Double = 20.0

///|
/// (its words' line: L6)
pub let toast_line : Double = leading_scale.l6

///|
pub let toast_py : Double = toast_r - toast_line / 2.0

///|
pub let toast_px : Double = 18.0

///|
pub let toast_action_h : Double = 28.0

///|
pub let toast_action_in : Double = capsule_in(toast_r, toast_action_h, room=toast_r)

///|
pub let toast_max : Double = 560.0

///|
pub let toast_bottom : Double = 24.0

///|
pub let toast_shadow : Double = 12.0

///|
pub let toast_shadow_y : Double = 8.0

///|
pub let toast_rise : Double = 8.0


///|
/// A column's edge (parts.css.ts resizeHandle, own.css.ts): a strip 7 wide, 4 of it past the column's edge; its bar 5
/// wide, 24 high and 48 on the strip; its line 8 short of the strip's ends, in 40 steps of its fade; dragged once 3
/// from where it went down.
pub let handle_w : Double = 7.0

///|
pub let handle_out : Double = 4.0

///|
pub let edge_bar_w : Double = 5.0

///|
pub let edge_line_steps : Int = 40

///|
/// How far past its gap an edge between two panels takes a finger's presses, into the panel beside the one it sizes
/// (edge_reach).
pub let edge_finger_reach : Double = 24.0

///|
/// A tip that follows the pointer along an edge (usePointerTip): 300 ms after the pointer comes, 14 beside it.
pub let edge_tip_ms : Double = 300.0

///|
pub let edge_tip_gap : Double = 14.0

// ---------------------------------------------------------------------------
// The desktop's sidebar and rail (sfdesk: ember web/src/Rail.css.ts, ChatMark.css.ts, styles/shell.css.ts)

///|
/// An agent's and a chat's marks' colours, bright in both themes, one meaning each wherever they are (ChatMark.css.ts:
/// #3b82f6 the viewer's turn, unread or waited on; #e5484d gone wrong; #f2b01e at work).
pub let mark_blue : @ui.Color = Exact(0x3B82F6FFL)

///|
pub let mark_red : @ui.Color = Exact(0xE5484DFFL)

///|
pub let mark_yellow : Int64 = 0xF2B01EFFL

///|
/// The rail's places 8 from its edges open (Rail.css.ts rail: 9 under the last, its 38s 9 in; here where they stand in
/// the closed bar, 6 + its 2, so folding moves none and their grounds, 12 in, are concentric with a Mac window's corner
/// as the bar's are through it: rail_ground_radius).
pub let rail_in : @ui.Space = room(8.0)

///|
/// The same as the sidebar's panel on the tape (laid out Medium, its left corners tape_side_corners'): the places in
/// its left corners (a 38 to press, its ground 30 round in its middle) as far in as makes their grounds concentric with
/// them; where the corner is too square for a circle (it follows a Mac window's), as far in as makes a ground's corner
/// there concentric with it (box_fit: the grounds boxes as round, rail_ground_radius); else 9 as open.
pub fn rail_in_tape() -> Double {
  let ground_in = (38.0 - rail_ground_side) / 2.0
  let corner = tape_side_corners()[3].radius()
  let d = capsule_in(corner, rail_ground_side)
  if place_fits(d) {
    d - ground_in
  } else {
    box_fit(corner, 9.0 + ground_in, 0.0).0 - ground_in
  }
}

///|
pub fn rail_in_tape_room() -> @ui.Space {
  room(rail_in_tape())
}

///|
/// The corner of the composer being built, opened (its place's: @sfpages.ComposerPlace), what waits in it and its round
/// controls following it (composer_inner, composer_round_in): a card's of the ladder's alone (a new chat's in the
/// middle of its page, a phone's); at a panel's foot, concentric with its corners where it stands (pane_composer_corner).
// kept across runs: said by the composer as it builds, from where it stands
pub let composer_round : Ref[Double] = Ref(card_corner)

///|
/// The composer's box's corner (composer_round).
pub fn composer_corner() -> Double {
  composer_round.val
}

///|
/// The composer's box's corner at a panel's foot: concentric with its foot corners where it stands, its round controls
/// followed in turn (pane_foot_corner: the tape's 28, 24.8).
pub fn pane_composer_corner() -> Double {
  pane_foot_corner(holds=theme().round.side)
}

///|
/// How far in from the composer's box its round controls stand in its foot corners (concentric with its corner as round
/// ones are: capsule_in; below its padding where they are larger than it leaves room for: a phone's 36).
pub fn composer_round_in() -> Double {
  capsule_in(composer_corner(), theme().round.side)
}

///|
/// The composer's padding as a style's (composer_pad).
pub let composer_pad_room : @ui.Space = room(composer_pad)

///|
/// Where a dialog's buttons stand in its foot corner (the theme's button: a capsule): as far from its foot and its side
/// as makes the last concentric with its corner (dialog_r), the row reaching past its sides' room `pad` to there.
pub fn dialog_corner_foot(pad : Double) -> @ui.Style {
  let at = capsule_in(dialog_r, button_height())
  @ui.style(pb=room(at), mr=room(at - pad))
}

///|
/// Where a small panel's buttons stand in its foot corners (the theme's button: a capsule): as far from its foot and its
/// sides as makes the last, and what stands at the foot's start (the model panel's account), concentric with its corner
/// (r_menu), the row reaching past its padding (panel_pad) to there at both ends.
pub fn panel_corner_foot() -> @ui.Style {
  let at = room(capsule_in(r_menu, button_height()) - panel_pad)
  @ui.style(ml=at, mr=at, mb=at)
}

///|
/// A place's ground in the rail (a place's, a workspace's): 30 round, so where it stands in a panel's corner it is
/// concentric with it (Rail.css.ts item, workspaceItem: 9 round, the web's).
pub let rail_ground_side : Double = 30.0

///|
/// Its corner, all its places' grounds one (one layer, one corner: the web's 9 each), `ground_in` from the edges of the
/// rail's corner `corner` (the closed bar's, the tape's sidebar panel's): linked to it, concentric with it; where that
/// is as round as the ground's half, a circle (a corner round enough for one: a pane's 34, 19 in; a bar's 21, 6 in).
pub fn rail_ground_radius(corner : @ui.CornerOf, ground_in : Double, alone? : Double = small_corner) -> @ui.Radius {
  let link : @ui.CornerOf = Follow(corner, ground_in, alone)
  // (as round as its half or rounder there, a circle: a corner round enough for one)
  if link.radius() >= rail_ground_side / 2.0 - 0.5 {
    Full
  } else {
    Linked(link)
  }
}

///|
/// A small panel's corner (a menu's, a popover's: r_menu) as a style's, for one drawn by a style of its own.
pub let panel_radius : @ui.Radius = rounded(r_menu)

///|
/// What sits in a small panel's corner (--panel-in: a menu's rows, a popover's), concentric with the panel's.
pub let panel_in : @ui.Radius = rounded(small_panel_inner(r_menu))

///|
/// The `@` menu over the composer (ChatRef.css.ts refMenu: a small panel, padded panel_pad) and its rows' corner
/// (refItem: concentric with it); its rows as high as a menu's (pick_high).
pub let ref_menu_corner : @ui.Radius = rounded(r_menu)

///|
pub let ref_item_corner : @ui.Radius = panel_in


///|
/// The closed bar's corner, `window_in` from the window's left, top and foot, its places' grounds `ground_in` from its
/// edges: all four one, a strip along the window's edge (laid out Large; not one of the Medium tape's panes side by
/// side, whose corners at the window's edge alone follow it: tape_corners): linked to the window's (window_follow),
/// else as round as makes its places' grounds concentric with it (as narrow as the rail, a capsule's
/// end by that; shown a while as wide as the sidebar, no rounder: not a pane's 34). Where it follows the window, too
/// square for a ground's circle, its grounds are boxes as round as makes them concentric with it (rail_ground_radius).
pub fn closed_bar_corner(ground_in : Double) -> @ui.Radius {
  Linked(closed_bar_of(ground_in))
}

///|
/// The same as a link.
pub fn closed_bar_of(ground_in : Double) -> @ui.CornerOf {
  window_follow(ground_in + rail_ground_side / 2.0)
}



///|
/// The sidebar's edge's look 3 in its strip (Rail.css.ts edge: its line 6 in, its bar 4 in, the library's 7 wide).
pub let edge_in : @ui.Space = room(3.0)

///|
/// A chat's row in the sidebar 7 in from its top and foot (Sidebar.css.ts navSession: padding 7 10).
pub let row_in : @ui.Space = room(row_in_y)

///|
pub let row_in_y : Double = 7.0

///|
/// A chat's row's title's line (mouse_head_h, 20) with its middle as far down as the middle of a key concentric with the
/// row's top corner (row_corner_keys: the row's corner, 18), so the marks at that line's end and its 归档 stand on one
/// line (the user, 2026-10-27): 8 in from its top; the web's 7 and 7 kept between top and foot, 6 under its last line.
pub let row_top_in_y : Double = row_corner - mouse_head_h / 2.0

///|
pub let row_foot_in_y : Double = 2.0 * row_in_y - row_top_in_y

///|
/// What is a capsule while its words fit one line `line_h` high (with its padding), wrapped to more: as round as that
/// one line makes it, not round all its height (the toast's toast_r, a notice over a chat's composer).
pub fn line_capsule_corner(line_h : Double) -> @ui.Radius {
  rounded(line_h / 2.0)
}

///|
/// An agent's mark `side` across (the web's ui.css.ts agentMark): its corner .3 of its side (a 28 one's 8.4: an agent's
/// card).
pub fn agent_mark_corner(side : Double) -> @ui.Radius {
  rounded(side * 0.3)
}

///|
/// A chat's jobs (the web's Jobs.css.ts): a job's action 26 high, the popover's foot's rows 38.
pub let job_action_h : @ui.Len = Fixed(26.0)

///|
pub let jobs_row_h : @ui.Len = Fixed(38.0)


///|
/// A tab of a chat's side panel (the web's ChatPage.css.ts sideTab: 30 high).
pub let side_tab_h : @ui.Len = Fixed(side_tab_side)

///|
pub let side_tab_side : Double = 30.0

///|
/// A device's code read aloud, large (Security.css.ts bigCode): the web's display size, 28, its line 1.3 of it, off
/// the scale; its letters 6 apart.
pub let code_big_size : @ui.TextSize = Exact(28.0, 36.4)

///|
pub let code_big_tracking : @ui.Tracking = Exact(6.0)

///|
/// A chat's bar (the web's ChatPage.css.ts): its station's tag 160 wide at most, 7 in; an agent's station's part 140 at
/// most, in by .19 of its 20 tile and 1.
pub let chat_station_most : @ui.Len = Fixed(160.0)

///|
pub let chat_station_in : @ui.Space = room(7.0)

///|
pub let agent_station_most : @ui.Len = Fixed(140.0)

///|
/// Whether a two-part tile (a chat's bar's agent and the station it runs on, each pressed for its own with keyboard
/// and mouse: its history, its station's card; each card under the pointer) is pressed whole: with touch, whose press
/// wants more room than either half (20 across, meeting) has, and which rests on nothing; a tap is the first's, a hold
/// both cards in one (the native input's; the user, 2026-10-27: 它们是一体的).
pub fn tile_whole() -> Bool {
  native_input() is Finger
}

///|
pub let agent_station_in : @ui.Space = room(20.0 * 0.19 + 1.0)

///|
/// A person in a chat's stack of people (the web's later.css.ts peopleStack): 16 ringed 1.5.
pub let person_ringed : @ui.Len = Fixed(19.0)

///|
/// The people a day's usage is split by, in the order the core's usage view ranks them (the web's Usage.css.ts, the
/// phone's Usage.kt): four of their own in light and in dark, the first still.fail's accent.
// kept across runs: a table, never written
let usage_light : Array[Int64] = [0xEF6A3CFFL, 0x2A78D6FFL, 0x1BAF7AFFL, 0x4A3AA7FFL]

///|
// kept across runs: a table, never written
let usage_dark : Array[Int64] = [0xE0602FFFL, 0x3987E5FFL, 0x199E70FFL, 0x9085E9FFL]

///|
/// The `i`th person's colour in the theme shown.
pub fn usage_series(i : Int) -> Int64 {
  (if theme().dark { usage_dark } else { usage_light })[i % 4]
}

///|
/// An agent's history's steps (the web's History.css.ts, ToolStep.css.ts): the turn's rail 9.5 in, how much of a wait
/// has gone a bar 3 high; a diff's line 22 in, its mark 9.
pub let history_rail_in : @ui.Space = room(9.5)

///|
pub let wait_bar_h : @ui.Len = Fixed(3.0)

///|
pub let diff_line_in : @ui.Space = room(22.0)

///|
pub let diff_mark_in : @ui.Space = room(9.0)

///|
/// How far a message's picture stands out in the margin before its words (align.ts columns.avatar: 29): what holds the
/// message keeps that much room before them (the chat's list its sides, a picture of the chat its own).
pub let message_avatar_reach : Double = 29.0

///|
/// A message's picture out in the margin before its words (message_avatar_reach), 3 down (Chat.css.ts msgRow >
/// msgAvatar).
pub let message_avatar_out : @ui.Space = room(-message_avatar_reach)

///|
pub let message_avatar_down : @ui.Space = room(3.0)

///|
/// A message's head in past its picture where the picture is over its start (Chat.css.ts inlineHeads: 25).
pub let message_head_in : @ui.Space = room(25.0)

///|
/// What says a chat is archived or its station down, over its composer (Chat.css.ts offlineNotice: 760 at most, 64
/// less than the pane).
pub let notice_w : @ui.Len = Fixed(760.0)

///|
/// A service's address in its bar beside the chat (Preview.css.ts previewAddress: 30 high).
pub let preview_address_h : @ui.Len = Fixed(30.0)

///|
/// A message's video (Chat.css.ts msgVideo, msgVideoPlay, msgVideoName): black under its still, black at 65% under its
/// play mark and its name, which are white.
pub let video_ground : @ui.Color = Data(0x000000FFL)

///|
pub let video_shade : @ui.Color = Data(0x000000A6L)

///|
pub let white_ink : @ui.Color = Data(0xFFFFFFFFL)

///|
pub let white : Int64 = 0xFFFFFFFFL
