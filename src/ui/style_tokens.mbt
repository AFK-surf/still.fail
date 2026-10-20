// Styles (docs/style.md): what a box or a line of words looks like, said once as a value and named, built of the
// theme's tokens, not of numbers. A style says token names (`px=S4`, `bg=Card`, `radius=Xl2`); what they come to is
// looked up in the theme in force as the node is built (Ctx::box, Ctx::text), so one style is a constant, right in
// light and dark, wide and narrow. Its states (pressed, hovered, focused, selected, disabled, dark, narrow) are blocks
// in it, picked by the framework from the node's own state; nothing in it moves by itself (no transition): a state
// changed is the other value from the frame that sees it, as an app's own `if c.pressed(id)` was.

///|
/// Spacing, Tailwind's scale (v3.4: a step 4 px): padding, gaps, a size. `Exact(v)` a value off the scale, said in an
/// app's token file only (detlint's `style-literal` counts it anywhere else, `style-exact` everywhere).
pub(all) enum Space {
  S0
  SPx
  S0_5
  S1
  S1_5
  S2
  S2_5
  S3
  S3_5
  S4
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
/// What a spacing token comes to, in logical pixels.
pub fn Space::px(self : Space) -> Double {
  match self {
    S0 => 0.0
    SPx => 1.0
    S0_5 => 2.0
    S1 => 4.0
    S1_5 => 6.0
    S2 => 8.0
    S2_5 => 10.0
    S3 => 12.0
    S3_5 => 14.0
    S4 => 16.0
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
/// A width or a height: what it holds (`Hug`, the default), all of the parent's (`Full`), a share of what is left
/// along the parent's main axis (`Grow(k)`), a spacing token, or `Fixed(v)` (a value worked out as the view builds: a
/// list's width; in a token file, a value off the scale).
pub(all) enum Len {
  Hug
  Full
  Grow(Double)
  Fixed(Double)
  S0
  SPx
  S0_5
  S1
  S1_5
  S2
  S2_5
  S3
  S3_5
  S4
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
    S1_5 => Some(S1_5)
    S2 => Some(S2)
    S2_5 => Some(S2_5)
    S3 => Some(S3)
    S3_5 => Some(S3_5)
    S4 => Some(S4)
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
    Full => Fill(1.0)
    Grow(k) => Fill(k)
    Fixed(v) => Px(exact_ok(v, "Len"))
    l => Px(l.space().unwrap().px())
  }
}

///|
/// A length as a bound (min_w, max_w…): `Hug` none (`none_is`), `Full` none as well.
fn Len::bound(self : Len, none_is : Double) -> Double {
  match self {
    Hug | Full | Grow(_) => none_is
    Fixed(v) => exact_ok(v, "Len")
    l => l.space().unwrap().px()
  }
}

///|
/// A corner, the theme's scale (Tailwind's names), a pill (`Full`: half the shorter side), or `Inner`: the corner of
/// the rounded container it lies in less how far in it lies, so that what lies in a container's corner is concentric
/// with it by how it is written (worked out once laid out: corners.mbt's corners_after_layout).
pub(all) enum Radius {
  Sharp
  Sm
  Base
  Md
  Lg
  Xl
  Xl2
  Xl3
  Full
  Inner
  Exact(Double)
} derive(Eq, Show, Debug)

///|
/// A size of words with its line's height, the theme's scale (Tailwind's names), or `Exact(size, line)`.
pub(all) enum TextSize {
  Xs
  Sm
  Base
  Lg
  Xl
  Xl2
  Xl3
  Xl4
  Exact(Double, Double)
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
  A(Color, Opacity)
  Over(Color, Color)
  Exact(Int64)
} derive(Eq, Show, Debug)

///|
/// An edge's width (Tailwind's border widths).
pub(all) enum Stroke {
  B0
  B1
  B2
  B4
  B8
} derive(Eq, Show, Debug)

///|
fn Stroke::px(self : Stroke) -> Double {
  match self {
    B0 => 0.0
    B1 => 1.0
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
} derive(Eq, Show, Debug)

///|
/// A shadow's blur and how far down it falls.
fn Shadow::blur_y(self : Shadow) -> (Double, Double) {
  match self {
    NoShadow => (0.0, -1.0)
    Sm => (2.0, 1.0)
    Base => (3.0, 1.0)
    Md => (6.0, 4.0)
    Lg => (15.0, 10.0)
    Xl => (25.0, 20.0)
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
