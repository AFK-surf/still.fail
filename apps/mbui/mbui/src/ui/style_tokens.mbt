// Styles (docs/style.md): what a box or a line of words looks like, said once as a value and named, built of the
// theme's tokens, not of numbers. A style says token names (`px=S4`, `bg=Card`, `radius=Xl2`); what they come to is
// looked up in the theme in force as the node is built (Ctx::box, Ctx::text), so one style is a constant, right in
// light and dark, wide and narrow. Its states (pressed, hovered, focused, selected, disabled, dark, narrow) are blocks
// in it, picked by the framework from the node's own state; nothing in it moves by itself (no transition): a state
// changed is the other value from the frame that sees it, as an app's own `if c.pressed(id)` was.

///|
/// Spacing, Tailwind's scale (v3.4: a step 4 px; v4's quarter steps where still.fail's Android app says them: S1_25 5,
/// S4_5 18): padding, gaps, a size. `Exact(v)` a value off the scale, said in an app's token file only (detlint's `style-literal` counts it anywhere else, `style-exact` everywhere).
pub(all) enum Space {
  S0
  SPx
  S0_5
  S1
  S1_25
  S1_5
  S2
  S2_5
  S3
  S3_5
  S4
  S4_5
  S5
  S6
  S7
  S8
  S9
  S10
  S11
  S12
  S14
  S16
  S20
  S24
  S28
  S32
  S36
  S40
  S44
  S48
  S52
  S56
  S60
  S64
  S72
  S80
  S96
  Exact(Double)
} derive(Eq, Show, Debug)

///|
/// The spacing scale: every named step, in order (what each comes to: Space::px). What measures spacing against the
/// scale (gaps.mbt's rule 6) reads it here, so the scale is said once.
pub fn space_scale() -> Array[Space] {
  [
    S0,
    SPx,
    S0_5,
    S1,
    S1_25,
    S1_5,
    S2,
    S2_5,
    S3,
    S3_5,
    S4,
    S4_5,
    S5,
    S6,
    S7,
    S8,
    S9,
    S10,
    S11,
    S12,
    S14,
    S16,
    S20,
    S24,
    S28,
    S32,
    S36,
    S40,
    S44,
    S48,
    S52,
    S56,
    S60,
    S64,
    S72,
    S80,
    S96,
  ]
}

///|
/// Where a named step stands in the scale (space_scale), -1 for an `Exact` one: said for every step, so one added to
/// Space is added to the scale (space_scale_wbtest.mbt holds the two together).
fn Space::step(self : Space) -> Int {
  match self {
    S0 => 0
    SPx => 1
    S0_5 => 2
    S1 => 3
    S1_25 => 4
    S1_5 => 5
    S2 => 6
    S2_5 => 7
    S3 => 8
    S3_5 => 9
    S4 => 10
    S4_5 => 11
    S5 => 12
    S6 => 13
    S7 => 14
    S8 => 15
    S9 => 16
    S10 => 17
    S11 => 18
    S12 => 19
    S14 => 20
    S16 => 21
    S20 => 22
    S24 => 23
    S28 => 24
    S32 => 25
    S36 => 26
    S40 => 27
    S44 => 28
    S48 => 29
    S52 => 30
    S56 => 31
    S60 => 32
    S64 => 33
    S72 => 34
    S80 => 35
    S96 => 36
    Exact(_) => -1
  }
}

///|
/// What a spacing token comes to, in logical pixels.
pub fn Space::px(self : Space) -> Double {
  match self {
    S0 => 0.0
    SPx => 1.0
    S0_5 => 2.0
    S1 => 4.0
    S1_25 => 5.0
    S1_5 => 6.0
    S2 => 8.0
    S2_5 => 10.0
    S3 => 12.0
    S3_5 => 14.0
    S4 => 16.0
    S4_5 => 18.0
    S5 => 20.0
    S6 => 24.0
    S7 => 28.0
    S8 => 32.0
    S9 => 36.0
    S10 => 40.0
    S11 => 44.0
    S12 => 48.0
    S14 => 56.0
    S16 => 64.0
    S20 => 80.0
    S24 => 96.0
    S28 => 112.0
    S32 => 128.0
    S36 => 144.0
    S40 => 160.0
    S44 => 176.0
    S48 => 192.0
    S52 => 208.0
    S56 => 224.0
    S60 => 240.0
    S64 => 256.0
    S72 => 288.0
    S80 => 320.0
    S96 => 384.0
    Exact(v) => exact_ok(v, "Space")
  }
}

///|
/// What a spacing token comes to as a margin: as `px`, and an `Exact` below 0 too (CSS's margins: one taking back a
/// padding, a list reaching past its column), not NaN.
pub fn Space::margin_px(self : Space) -> Double {
  match self {
    Exact(v) => {
      if v != v {
        abort("style: a margin's Exact is NaN")
      }
      v
    }
    s => s.px()
  }
}

///|
/// A width or a height: what it holds (`Hug`, the default; `Cut` cut short where its row has less), all of the parent's (`Full`), a share of what is left
/// along the parent's main axis (`Grow(k)`), a share of the parent's room in percent (`Pct(p)`, CSS's 50%; a size only,
/// not a bound), a spacing token, or `Fixed(v)` (a value worked out as the view builds: a list's width; in a token
/// file, a value off the scale); as a least across (`min_w`), `Within(v)`: `v` where the parent has the room, all of it
/// where it has less (CSS's `min(100%, 320px)`).
pub(all) enum Len {
  Hug
  /// as wide as what it holds, cut short where its row has less (words on one line in an ellipsis)
  Cut
  Full
  Grow(Double)
  Fixed(Double)
  Pct(Double)
  /// a least across: as many points where the parent has the room, all of the parent's where it has less
  Within(Double)
  S0
  SPx
  S0_5
  S1
  S1_25
  S1_5
  S2
  S2_5
  S3
  S3_5
  S4
  S4_5
  S5
  S6
  S7
  S8
  S9
  S10
  S11
  S12
  S14
  S16
  S20
  S24
  S28
  S32
  S36
  S40
  S44
  S48
  S52
  S56
  S60
  S64
  S72
  S80
  S96
} derive(Eq, Show, Debug)

///|
/// The spacing token a length names, if it names one.
fn Len::space(self : Len) -> Space? {
  match self {
    S0 => Some(S0)
    SPx => Some(SPx)
    S0_5 => Some(S0_5)
    S1 => Some(S1)
    S1_25 => Some(S1_25)
    S1_5 => Some(S1_5)
    S2 => Some(S2)
    S2_5 => Some(S2_5)
    S3 => Some(S3)
    S3_5 => Some(S3_5)
    S4 => Some(S4)
    S4_5 => Some(S4_5)
    S5 => Some(S5)
    S6 => Some(S6)
    S7 => Some(S7)
    S8 => Some(S8)
    S9 => Some(S9)
    S10 => Some(S10)
    S11 => Some(S11)
    S12 => Some(S12)
    S14 => Some(S14)
    S16 => Some(S16)
    S20 => Some(S20)
    S24 => Some(S24)
    S28 => Some(S28)
    S32 => Some(S32)
    S36 => Some(S36)
    S40 => Some(S40)
    S44 => Some(S44)
    S48 => Some(S48)
    S52 => Some(S52)
    S56 => Some(S56)
    S60 => Some(S60)
    S64 => Some(S64)
    S72 => Some(S72)
    S80 => Some(S80)
    S96 => Some(S96)
    _ => None
  }
}

///|
/// A length as a node's size.
fn Len::size(self : Len) -> Size {
  match self {
    Hug => Auto
    Cut => Cut
    Full => Fill(1.0)
    Grow(k) => Fill(k)
    Pct(p) => Pct(exact_ok(p, "Len Pct"))
    Fixed(v) => Px(exact_ok(v, "Len"))
    Within(v) => abort("style: Within(\{v}) is a least across (min_w), not a size")
    l => Px(l.space().unwrap().px())
  }
}

///|
/// A length as a bound (min_w, max_w…): `Hug` none (`none_is`), `Full` none as well.
fn Len::bound(self : Len, none_is : Double) -> Double {
  match self {
    Hug | Cut | Full | Grow(_) => none_is
    Pct(p) => abort("style: a bound is not a share (Pct(\{p}))")
    Fixed(v) | Within(v) => exact_ok(v, "Len")
    l => l.space().unwrap().px()
  }
}

///|
/// A corner, the theme's scale (Tailwind's names, and Xl1_5 between Xl and Xl2, Xl4 past Xl3), a pill (`Full`: half the shorter side), or `Inner`: the corner of
/// the rounded container it lies in less how far in it lies, so that what lies in a container's corner is concentric
/// with it by how it is written (worked out once laid out: corners.mbt's corners_after_layout); `InnerOr(r)` the same
/// where it lies in a rounded container's corner and `r` where it lies in none (the web's innerOr: a capsule standing
/// alone that, in a panel's corner, follows the panel's, which so is the panel's own to choose); `Around` the other way
/// round, the container's own corner from what lies in it.
pub(all) enum Radius {
  Sharp
  Sm
  Base
  Md
  Lg
  Xl
  Xl1_5
  Xl2
  Xl3
  Xl4
  Full
  Inner
  InnerOr(Radius)
  /// the other way from `Inner`: the corner round what lies in its corner, worked out once laid out (a circle or a
  /// capsule there: its distance from the two edges and its own corner; a smooth one: smooth.mbt concentric_out)
  Around
  Exact(Double)
  /// each corner its own (top left, top right, bottom right, bottom left: CSS's border-radius of four): a panel whose
  /// corners in the window's follow it and the others stand alone
  Corners(Double, Double, Double, Double)
  /// a corner linked to where it comes from (corner_of.mbt: the window's, another followed so far in): all four
  Linked(CornerOf)
  /// the same each its own (top left, then round it)
  LinkedEach(CornerOf, CornerOf, CornerOf, CornerOf)
} derive(Eq, Show, Debug)

///|
/// A size of words with its line's height: by what the words are (`Caption` … `Display`: the theme's roles, as a
/// design system's type tokens say them, each its own size on each screen), the theme's scale (Tailwind's names, and
/// Xs2, Xs3 under Xs, as Xl2, Xl3 over Xl; Xl5 … Xl7 past them, a picture's one number), or `Exact(size, line)`.
pub(all) enum TextSize {
  /// the smallest words: a time, a count on a badge, a small status
  Caption
  /// what is said about something: a row's second line, a note, a hint
  Meta
  /// an interface's words: a menu's, a button's, a row's title in a panel
  Ui
  /// what is read: a message, a paragraph
  Body
  /// a title: a page's, a bar's, a list's row
  Title
  /// a heading over a page's body
  Heading
  /// the largest: a page's one word on its own
  Display
  Xs3
  Xs2
  Xs
  Sm
  Base
  Lg
  Xl
  Xl2
  Xl3
  Xl4
  Xl5
  Xl6
  Xl7
  Exact(Double, Double)
} derive(Eq, Show, Debug)

///|
/// A line's height said apart from the words' size (which has one of its own, TextSize): the theme's scale
/// (Tailwind's leading-3 … leading-10 by default: 12, 16 … 40; L4_75, 19), `Font` the font's own, or `Exact(px)`.
pub(all) enum Leading {
  Font
  L3
  L4
  L4_75
  L5
  L6
  L7
  L8
  L9
  L10
  Exact(Double)
} derive(Eq, Show, Debug)

///|
/// Letter spacing (Tailwind's tracking, in ems of the words' size), or `Exact(px)` in pixels: added to each
/// cluster's advance, half before it and half after (Android's letterSpacing).
pub(all) enum Tracking {
  Tighter
  Tight
  Normal
  Wide
  Wider
  Widest
  Exact(Double)
} derive(Eq, Show, Debug)

///|
/// The spacing in pixels, for words of `size`.
pub fn Tracking::px(self : Tracking, size : Double) -> Double {
  match self {
    Tighter => -0.05 * size
    Tight => -0.025 * size
    Normal => 0.0
    Wide => 0.025 * size
    Wider => 0.05 * size
    Widest => 0.1 * size
    Exact(v) => v
  }
}

///|
/// How heavy words are.
pub(all) enum Weight {
  Normal
  Medium
  Semibold
  Bold
} derive(Eq, Show, Debug)

///|
pub fn Weight::value(self : Weight) -> Int {
  match self {
    Normal => 400
    Medium => 500
    Semibold => 600
    Bold => 700
  }
}

///|
/// How much of a colour shows, Tailwind's scale (`O35` is 0.35), or `Exact(a)`.
pub(all) enum Opacity {
  O0
  O5
  O10
  O15
  O20
  O25
  O30
  O35
  O40
  O45
  O50
  O55
  O60
  O65
  O70
  O75
  O80
  O85
  O90
  O95
  O100
  Exact(Double)
} derive(Eq, Show, Debug)

///|
pub fn Opacity::value(self : Opacity) -> Double {
  match self {
    O0 => 0.0
    O5 => 0.05
    O10 => 0.1
    O15 => 0.15
    O20 => 0.2
    O25 => 0.25
    O30 => 0.3
    O35 => 0.35
    O40 => 0.4
    O45 => 0.45
    O50 => 0.5
    O55 => 0.55
    O60 => 0.6
    O65 => 0.65
    O70 => 0.7
    O75 => 0.75
    O80 => 0.8
    O85 => 0.85
    O90 => 0.9
    O95 => 0.95
    O100 => 1.0
    Exact(v) => {
      if !(v >= 0.0 && v <= 1.0) {
        abort("style: Opacity Exact(\{v}) is not within 0 … 1")
      }
      v
    }
  }
}

///|
/// A colour by its role in the theme (Theme's fields), one of them at an opacity (`A(Fg, O5)`), one laid over another
/// (`Over(Card, A(Fg, O5))`), none (`Clear`), or `Exact(rrggbbaa)`.
pub(all) enum Color {
  Clear
  Bg
  Surface
  Raised
  Card
  Fg
  Muted
  Subtle
  Faint
  Line
  Border
  Accent
  AccentText
  AccentBg
  OnAccent
  Primary
  OnPrimary
  Positive
  Danger
  DangerBg
  OnDanger
  Neutral
  Hover
  Selected
  Focus
  Scrim
  Link
  ShadowC
  /// someone else at the controls, a wait to look at (still.fail's Theme.kt C.warn)
  Warn
  /// words in warn's colour: its amber dark enough to read (Theme's `warn_ink`, as AccentText is the accent's)
  WarnInk
  /// a quiet ground over whatever is under it (a key, a Seg's track, a remove button): the words' colour at 6%; and
  /// what is empty of what fills (a progress's track): the line's colour, as what is drawn with nothing in it is
  /// (Theme's `line`, contrast.mbt)
  Tint
  TintStrong
  /// what floats still over the page, nothing blurred under it (Glass.kt floatingStill: Raised at 72% over the page)
  Floating
  /// what a picture gone dark is under (a remote screen ended: black at 62% over its last frame, 92% over none), and
  /// what is said on it (white)
  Veil
  VeilDeep
  OnVeil
  /// the ground a picture is shown on alone, edge to edge (a video's, a remote screen's in 全屏): black
  Theater
  /// what is lifted out of a tinted track (a segmented choice's thumb: white; in the dark the ink at an opacity over the track)
  Lifted
  /// a quiet wash under what comes onto it (still.fail's Android app's way of the web's --hover: a screen's preview
  /// before its picture, ScreenLinks.kt; the offline note, Chat.kt), the same on every width
  Wash
  /// a sidebar's ground beside the page (still.fail's Sidebar.css.ts vars.sidebar): what stands in it is cut out of it
  /// (a row's people's pictures, RowPicture.css.ts --mark-around)
  Sidebar
  /// a list's ground, a step off the page (still.fail's --list): what a row of words to press lights to under the
  /// pointer (AutomaticDecisions.css.ts policyWords)
  ListGround
  /// a field's edge pointed at or written in, a column's edge in hand (still.fail's --field-hover)
  FieldHover
  A(Color, Opacity)
  Over(Color, Color)
  Exact(Int64)
  /// a colour that comes with what is shown, not the design's (an avatar's own ground, a colour a person typed): from
  /// data, never a number written in a view (one there is a style-literal)
  Data(Int64)
} derive(Eq, Show, Debug)

///|
/// An edge's width (Tailwind's border widths, and a hairline: B0_5; B1_5 a ring a little firmer than a line, as a dot
/// looked at is drawn round).
pub(all) enum Stroke {
  B0
  B0_5
  B1
  B1_5
  B2
  B4
  B8
} derive(Eq, Show, Debug)

///|
fn Stroke::px(self : Stroke) -> Double {
  match self {
    B0 => 0.0
    B0_5 => 0.5
    B1 => 1.0
    B1_5 => 1.5
    B2 => 2.0
    B4 => 4.0
    B8 => 8.0
  }
}

///|
/// A shadow (Tailwind's, its first layer: mbui draws one), in the theme's shadow colour.
pub(all) enum Shadow {
  NoShadow
  Sm
  Base
  Md
  Lg
  Xl
  /// a shadow said whole: its sigma, how far down, its colour (an app's own, worked out once where it says why)
  Cast(Double, Double, Int64)
} derive(Eq, Show, Debug)

///|
/// A shadow's blur (its sigma, as CALayer's shadowRadius) and how far down it falls.
pub fn Shadow::blur_y(self : Shadow) -> (Double, Double) {
  match self {
    NoShadow => (0.0, -1.0)
    Sm => (2.0, 1.0)
    Base => (3.0, 1.0)
    Md => (6.0, 4.0)
    Lg => (15.0, 10.0)
    Xl => (25.0, 20.0)
    Cast(b, y, _) => (b, y)
  }
}

///|
/// An off-scale value's check: a size, a gap, a corner is never below 0 (nor NaN); one that is fails here, naming
/// what it was, rather than drawn as 0.
fn exact_ok(v : Double, what : String) -> Double {
  if !(v >= 0.0) {
    abort("style: \{what} Exact(\{v}) is below 0")
  }
  v
}
