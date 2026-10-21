// What the views built under it look like unless they say (SwiftUI's environment, Compose's CompositionLocal, egui's
// Style): the theme's colours, corners and sizes, and which way words and rows run. The app sets it once (it stays
// from frame to frame) or for a part of what it builds (Ctx::with_theme, Ctx::with_direction); the widgets read their
// defaults from it, and what a call says itself still wins. docs/components.md says how the components use it.

///|
/// The theme: colours RRGGBBAA, corners and sizes in logical pixels. Made from one of its kinds (Theme::light, …) and
/// changed where the app differs (`{ ..Theme::light(), accent: 0x… }`). By default still.fail's (its web and apps'
/// tokens: the wide screen's white canvas and ember orange, the phone's warm paper); iOS's colours, what mbui had
/// hard-coded, are Theme::ios_light and Theme::ios_dark.
pub(all) struct Theme {
  /// dark (what draws over it picks its own shades by it)
  dark : Bool
  /// the page's ground
  bg : Int64
  /// what lies over the page: panels, menus, dialogs, popovers
  surface : Int64
  /// words
  fg : Int64
  /// quieter words: a description, what is off
  muted : Int64
  /// quieter still: a placeholder, what is disabled
  subtle : Int64
  /// the ground of quiet parts: a track, a chip, a segmented control, an avatar
  faint : Int64
  /// a control's edge: a field's, a button's, a checkbox's, a switch that is off
  border : Int64
  /// quiet lines: a panel's edge, a separator
  line : Int64
  /// the one colour: what is on, chosen, filled, moving (a switch on, a slider, progress)
  accent : Int64
  /// words and marks over the accent
  on_accent : Int64
  /// the thing to do: a solid button, a checked box, a tooltip, a toast (still.fail's ink)
  primary : Int64
  /// words and marks over `primary`
  on_primary : Int64
  /// what went well, what is online
  positive : Int64
  /// what cannot be undone, what failed
  danger : Int64
  /// words and marks over `danger`
  on_danger : Int64
  /// laid over what is pointed at or pressed (a tint: its alpha says how much); a menu's lit item
  hover : Int64
  /// a control's edge pointed at
  field_hover : Int64
  /// the ring round what has the keyboard's focus
  focus : Int64
  /// the page under a modal (a dialog's)
  scrim : Int64
  /// what lies over the page casts
  shadow : Int64
  /// a switch's knob, a slider's thumb's ring
  thumb : Int64
  /// the corner of fields and of what holds rows (a button and a one-line field are pills: half their height)
  radius : Double
  /// the corner of what lies over the page (a menu, a popover, a toast)
  radius_lg : Double
  /// a dialog's corner
  radius_dialog : Double
  /// words' sizes: what controls say, the smaller (a description, a tooltip), a title, a dialog's heading
  font : Double
  font_sm : Double
  font_title : Double
  font_heading : Double
  /// a control's height (a button, a field, a select's trigger)
  control_h : Double
  /// the focus ring's width, and how far out of what it rings it lies
  focus_w : Double
  focus_gap : Double
  /// what floats over the page (a bar, a capsule): style.mbt's `Raised`
  raised : Int64
  /// a card's ground on the page
  card : Int64
  /// words in the accent's colour, and the accent's quiet ground (a chosen row, a badge)
  accent_text : Int64
  accent_bg : Int64
  /// the ground of what failed (an error's box)
  danger_bg : Int64
  /// a quiet pill's ground, a placeholder's grey
  neutral : Int64
  /// what is chosen in a list
  selected : Int64
  /// links
  link : Int64
  /// someone else at the controls (Color's Warn)
  warn : Int64
  /// what is lifted out of a tinted track (Color's Lifted)
  lifted : Int64
  /// a quiet wash under what comes onto it (Color's Wash)
  wash : Int64
  /// the sizes of words with their lines' heights (style.mbt's TextSize), the lines' heights said on their own
  /// (Leading), and the corners (Radius)
  text : TextScale
  leading : LeadingScale
  radii : RadiusScale
  /// the height of a line of words that say none, a size of words (1.4: CSS's `line-height: 1.4`, still.fail's
  /// apps'); 0: the host's own (its system's, about 1.42)
  text_line : Double
}

///|
/// The sizes of words, each with its line's height (size, line).
pub(all) struct TextScale {
  xs3 : (Double, Double)
  xs2 : (Double, Double)
  xs : (Double, Double)
  sm : (Double, Double)
  base : (Double, Double)
  lg : (Double, Double)
  xl : (Double, Double)
  xl2 : (Double, Double)
  xl3 : (Double, Double)
  xl4 : (Double, Double)
}

///|
/// Tailwind's (v3.4).
pub fn TextScale::tailwind() -> TextScale {
  {
    xs3: (10.0, 14.0),
    xs2: (11.0, 16.0),
    xs: (12.0, 16.0),
    sm: (14.0, 20.0),
    base: (16.0, 24.0),
    lg: (18.0, 28.0),
    xl: (20.0, 28.0),
    xl2: (24.0, 32.0),
    xl3: (30.0, 36.0),
    xl4: (36.0, 40.0),
  }
}

///|
/// The heights of lines said on their own (Leading's L3 … L10, and L4_75), in pixels.
pub(all) struct LeadingScale {
  l3 : Double
  l4 : Double
  l4_75 : Double
  l5 : Double
  l6 : Double
  l7 : Double
  l8 : Double
  l9 : Double
  l10 : Double
}

///|
/// Tailwind's (v3.4: leading-3 … leading-10, 0.75rem … 2.5rem; leading-4.75, 19).
pub fn LeadingScale::tailwind() -> LeadingScale {
  { l3: 12.0, l4: 16.0, l4_75: 19.0, l5: 20.0, l6: 24.0, l7: 28.0, l8: 32.0, l9: 36.0, l10: 40.0 }
}

///|
/// The corners.
pub(all) struct RadiusScale {
  sm : Double
  base : Double
  md : Double
  lg : Double
  xl : Double
  xl1_5 : Double
  xl2 : Double
  xl3 : Double
  xl4 : Double
}

///|
/// Tailwind's (v3.4).
pub fn RadiusScale::tailwind() -> RadiusScale {
  { sm: 2.0, base: 4.0, md: 6.0, lg: 8.0, xl: 12.0, xl1_5: 14.0, xl2: 16.0, xl3: 24.0, xl4: 32.0 }
}

///|
/// still.fail's light theme, the wide screen's (web/ui styles/tokens.css.ts): the white canvas, ink, ember orange.
pub fn Theme::light() -> Theme {
  {
    dark: false,
    bg: 0xFFFFFFFFL,
    surface: 0xFFFFFFFFL,
    fg: 0x24272BFFL,
    muted: 0x646970FFL,
    subtle: 0x73787DFFL,
    faint: 0xF1F1F2FFL,
    border: 0xC1C4C9FFL,
    line: 0xE3E1DEFFL,
    accent: 0xEF6A3CFFL,
    on_accent: 0xFFFFFFFFL,
    primary: 0x24272BFFL,
    on_primary: 0xFFFFFFFFL,
    positive: 0x006A3FFFL,
    danger: 0xA12F35FFL,
    on_danger: 0xFFFFFFFFL,
    hover: 0x26211711L,
    field_hover: 0x9A9EA3FFL,
    focus: 0x646970FFL,
    scrim: 0x13161B33L,
    shadow: 0x13161B1AL,
    thumb: 0xFFFFFFFFL,
    radius: 12.0,
    radius_lg: 20.0,
    radius_dialog: 42.0,
    font: 13.0,
    font_sm: 12.0,
    font_title: 16.0,
    font_heading: 22.0,
    control_h: 36.0,
    focus_w: 2.0,
    focus_gap: 2.0,
    raised: 0xE4E4E8FFL,
    card: 0xF6F6F7FFL,
    accent_text: 0xA23203FFL,
    accent_bg: 0xFFEFE6FFL,
    danger_bg: 0xFFF0EFFFL,
    neutral: 0xEDEFF1FFL,
    selected: 0xEBE7E1FFL,
    link: 0x1559C4FFL,
    warn: 0xD9962BFFL,
    lifted: 0xFFFFFFFFL,
    // #322D24 at 6.5%
    wash: 0x322D2411L,
    text: TextScale::tailwind(),
    leading: LeadingScale::tailwind(),
    text_line: 0.0,
    radii: RadiusScale::tailwind(),
  }
}

///|
/// still.fail's dark theme, the wide screen's.
pub fn Theme::dark() -> Theme {
  {
    ..Theme::light(),
    dark: true,
    bg: 0x1F2023FFL,
    surface: 0x2A2C31FFL,
    fg: 0xE9E9EAFFL,
    muted: 0xA3A5A9FFL,
    subtle: 0x8C8F94FFL,
    faint: 0x313237FFL,
    border: 0x3D3F44FFL,
    line: 0x2D2E32FFL,
    accent: 0xF57E4DFFL,
    primary: 0xECEDEDFFL,
    on_primary: 0x1F2023FFL,
    positive: 0x68C894FFL,
    danger: 0xF68482FFL,
    on_danger: 0x1F2023FFL,
    hover: 0xFFFFFF0DL,
    field_hover: 0x5D6066FFL,
    focus: 0x8A8D93FFL,
    scrim: 0x00000080L,
    shadow: 0x00000073L,
    raised: 0x2A2C31FFL,
    card: 0x28292CFFL,
    accent_text: 0xFC9B6FFFL,
    accent_bg: 0x43251AFFL,
    danger_bg: 0x442322FFL,
    neutral: 0x2A2B2FFFL,
    selected: 0x323338FFL,
    link: 0x81AEFAFFL,
    lifted: 0x3A3B40FFL,
    // white at 5%
    wash: 0xFFFFFF0DL,
  }
}

///|
/// still.fail's light theme on a phone (the narrow screen's, its Android app's): warm paper, its own greys, words a
/// size up, controls 38 high.
pub fn Theme::narrow_light() -> Theme {
  {
    ..Theme::light(),
    bg: 0xF5F3EFFFL,
    muted: 0x7A7D83FFL,
    subtle: 0xA6A8ACFFL,
    faint: 0xEFECE6FFL,
    line: 0xE7E3DCFFL,
    accent: 0xE5704AFFL,
    positive: 0x2F8F5BFFL,
    danger: 0xC9412EFFL,
    hover: 0x24272B0FL,
    font: 15.0,
    font_sm: 13.0,
    control_h: 38.0,
    raised: 0xFFFFFFFFL,
    card: 0xFFFFFFFFL,
    accent_text: 0xB9471FFFL,
    accent_bg: 0xFBE6DCFFL,
    neutral: 0xE8E4DCFFL,
  }
}

///|
/// still.fail's dark theme on a phone.
pub fn Theme::narrow_dark() -> Theme {
  {
    ..Theme::dark(),
    bg: 0x1B1C1FFFL,
    surface: 0x26272BFFL,
    fg: 0xECECEDFFL,
    muted: 0x9A9DA3FFL,
    subtle: 0x6E7177FFL,
    faint: 0x313237FFL,
    line: 0x34353AFFL,
    accent: 0xEF7A55FFL,
    positive: 0x5CC08AFFL,
    danger: 0xEB6B58FFL,
    hover: 0xECECED14L,
    font: 15.0,
    font_sm: 13.0,
    control_h: 38.0,
    raised: 0x2A2C31FFL,
    card: 0x26272BFFL,
    accent_text: 0xF6A383FFL,
    accent_bg: 0x4A2F25FFL,
    neutral: 0x313237FFL,
  }
}

///|
/// iOS's light colours, what mbui's widgets had before the theme was still.fail's (the demo's).
pub fn Theme::ios_light() -> Theme {
  {
    dark: false,
    bg: 0xFFFFFFFFL,
    surface: 0xFFFFFFFFL,
    fg: 0x1D1D1FFFL,
    muted: 0x8E8E93FFL,
    subtle: 0xAEAEB2FFL,
    faint: 0xE3E3E8FFL,
    border: 0xD1D1D6FFL,
    line: 0xD1D1D6FFL,
    accent: 0x0A84FFFFL,
    on_accent: 0xFFFFFFFFL,
    primary: 0x0A84FFFFL,
    on_primary: 0xFFFFFFFFL,
    positive: 0x34C759FFL,
    danger: 0xFF3B30FFL,
    on_danger: 0xFFFFFFFFL,
    hover: 0x0000000FL,
    field_hover: 0xAEAEB2FFL,
    focus: 0x0A84FF99L,
    scrim: 0x00000059L,
    shadow: 0x0000002EL,
    thumb: 0xFFFFFFFFL,
    radius: 10.0,
    radius_lg: 14.0,
    radius_dialog: 14.0,
    font: 15.0,
    font_sm: 13.0,
    font_title: 17.0,
    font_heading: 20.0,
    control_h: 36.0,
    focus_w: 2.0,
    focus_gap: 2.0,
    raised: 0xF2F2F7FFL,
    card: 0xF2F2F7FFL,
    accent_text: 0x0A84FFFFL,
    accent_bg: 0x0A84FF1FL,
    danger_bg: 0xFF3B301FL,
    neutral: 0xE5E5EAFFL,
    selected: 0xD1D1D6FFL,
    link: 0x0A84FFFFL,
    warn: 0xFF9F0AFFL,
    lifted: 0xFFFFFFFFL,
    // #322D24 at 6.5%
    wash: 0x322D2411L,
    text: TextScale::tailwind(),
    leading: LeadingScale::tailwind(),
    text_line: 0.0,
    radii: RadiusScale::tailwind(),
  }
}

///|
/// iOS's dark colours.
pub fn Theme::ios_dark() -> Theme {
  {
    ..Theme::ios_light(),
    dark: true,
    bg: 0x000000FFL,
    surface: 0x1C1C1EFFL,
    fg: 0xF5F5F7FFL,
    muted: 0x8E8E93FFL,
    subtle: 0x636366FFL,
    faint: 0x3A3A3CFFL,
    border: 0x38383AFFL,
    line: 0x38383AFFL,
    positive: 0x30D158FFL,
    danger: 0xFF453AFFL,
    hover: 0xFFFFFF17L,
    field_hover: 0x636366FFL,
    focus: 0x409CFFB3L,
    scrim: 0x0000008CL,
    shadow: 0x00000073L,
    raised: 0x2C2C2EFFL,
    card: 0x1C1C1EFFL,
    accent_text: 0x409CFFFFL,
    accent_bg: 0x0A84FF33L,
    danger_bg: 0xFF453A33L,
    neutral: 0x3A3A3CFFL,
    selected: 0x3A3A3CFFL,
    link: 0x409CFFFFL,
    lifted: 0x636366FFL,
    // white at 5%
    wash: 0xFFFFFF0DL,
  }
}

///|
/// The theme in force where the view is building.
pub fn Ctx::theme(self : Ctx) -> Theme {
  self.theme
}

///|
/// The theme from here on (this frame's rest and the next frames'), until set again. With `narrow`, that one in its
/// place in the frames whose window is narrower than `narrow_below` (a phone's), picked as each frame starts from its
/// width (Ctx::narrow; style.mbt's `narrow` blocks). The app calls it as it starts and when the person picks light
/// or dark, not every frame.
pub fn Ctx::set_theme(self : Ctx, t : Theme, narrow? : Theme, narrow_below? : Double = 700.0) -> Unit {
  self.theme_wide = t
  self.theme_narrow = narrow
  self.narrow_below = narrow_below
  self.pick_theme()
}

///|
/// The theme set (Ctx::set_theme) for this frame's width.
fn Ctx::pick_theme(self : Ctx) -> Unit {
  self.theme = match self.theme_narrow {
    Some(n) if self.width < self.narrow_below => n
    _ => self.theme_wide
  }
  self.narrow = self.theme_narrow is Some(_) && self.width < self.narrow_below
}

///|
/// Whether this frame is drawn in the narrow theme (Ctx::set_theme's `narrow`).
pub fn Ctx::narrow(self : Ctx) -> Bool {
  self.narrow
}

///|
/// What a spacing token comes to.
pub fn Ctx::space(self : Ctx, s : Space) -> Double {
  ignore(self)
  s.px()
}

///|
/// What a colour token comes to in the theme in force.
pub fn Ctx::color(self : Ctx, c : Color) -> Int64 {
  self.theme.color(c)
}

///|
/// A size of words in the theme in force: (size, line).
pub fn Ctx::text_size(self : Ctx, s : TextSize) -> (Double, Double) {
  self.theme.text_size(s)
}

///|
/// What a colour token comes to in this theme.
pub fn Theme::color(self : Theme, c : Color) -> Int64 {
  match c {
    Clear => 0L
    Bg => self.bg
    Surface => self.surface
    Raised => self.raised
    Card => self.card
    Fg => self.fg
    Muted => self.muted
    Subtle => self.subtle
    Faint => self.faint
    Line => self.line
    Border => self.border
    Accent => self.accent
    AccentText => self.accent_text
    AccentBg => self.accent_bg
    OnAccent => self.on_accent
    Primary => self.primary
    OnPrimary => self.on_primary
    Positive => self.positive
    Danger => self.danger
    DangerBg => self.danger_bg
    OnDanger => self.on_danger
    Neutral => self.neutral
    Hover => self.hover
    Selected => self.selected
    Focus => self.focus
    Scrim => self.scrim
    Link => self.link
    ShadowC => self.shadow
    Warn => self.warn
    Tint => alpha(self.fg, 0.06)
    TintStrong => alpha(self.fg, 0.08)
    Floating => over(self.bg, alpha(self.raised, 0.72))
    Veil => 0x0000009EL
    VeilDeep => 0x000000EBL
    OnVeil => 0xFFFFFFFFL
    Lifted => self.lifted
    Wash => self.wash
    Theater => 0x000000FFL
    A(c, o) => alpha(self.color(c), o.value())
    Over(u, t) => over(self.color(u), self.color(t))
    Exact(v) => v
  }
}

///|
/// A size of words in this theme: (size, line).
pub fn Theme::text_size(self : Theme, s : TextSize) -> (Double, Double) {
  match s {
    Xs3 => self.text.xs3
    Xs2 => self.text.xs2
    Xs => self.text.xs
    Sm => self.text.sm
    Base => self.text.base
    Lg => self.text.lg
    Xl => self.text.xl
    Xl2 => self.text.xl2
    Xl3 => self.text.xl3
    Xl4 => self.text.xl4
    Exact(size, line) => (exact_ok(size, "TextSize"), exact_ok(line, "TextSize"))
  }
}

///|
/// A line's height in this theme; None for `Font`, the font's own (no height to say: not a 0 to be taken for one).
pub fn Theme::leading(self : Theme, l : Leading) -> Double? {
  match l {
    Font => None
    L3 => Some(self.leading.l3)
    L4 => Some(self.leading.l4)
    L4_75 => Some(self.leading.l4_75)
    L5 => Some(self.leading.l5)
    L6 => Some(self.leading.l6)
    L7 => Some(self.leading.l7)
    L8 => Some(self.leading.l8)
    L9 => Some(self.leading.l9)
    L10 => Some(self.leading.l10)
    Exact(v) => Some(exact_ok(v, "Leading"))
  }
}

///|
/// A corner in this theme (`Inner` and `Around` are worked out once laid out: 0 here).
pub fn Theme::corner(self : Theme, r : Radius) -> Double {
  match r {
    Sharp | Inner | Around => 0.0
    Sm => self.radii.sm
    Base => self.radii.base
    Md => self.radii.md
    Lg => self.radii.lg
    Xl => self.radii.xl
    Xl1_5 => self.radii.xl1_5
    Xl2 => self.radii.xl2
    Xl3 => self.radii.xl3
    Xl4 => self.radii.xl4
    Full => 1.0e6
    Exact(v) => exact_ok(v, "Radius")
  }
}

///|
/// `body` built under theme `t` (a dark panel in a light page, a part restyled), the theme as it was after it.
pub fn Ctx::with_theme(self : Ctx, t : Theme, body : () -> Unit) -> Unit {
  let saved = self.theme
  self.theme = t
  body()
  self.theme = saved
}

///|
/// Which way words and rows run (Radix's DirectionProvider, CSS's `dir`).
pub(all) enum Direction {
  Ltr
  Rtl
} derive(Eq, Show, Debug)

///|
/// The direction in force where the view is building.
pub fn Ctx::direction(self : Ctx) -> Direction {
  self.direction
}

///|
/// Whether rows run right to left where the view is building: a row's first child is at its right, its start
/// padding the right one, and the arrows that move along a row go the other way (focus.mbt).
pub fn Ctx::rtl(self : Ctx) -> Bool {
  self.direction == Rtl
}

///|
/// The direction from here on, until set again (the app's language's).
pub fn Ctx::set_direction(self : Ctx, d : Direction) -> Unit {
  self.direction = d
}

///|
/// `body` built in direction `d` (a part in another language), the direction as it was after it.
pub fn Ctx::with_direction(self : Ctx, d : Direction, body : () -> Unit) -> Unit {
  let saved = self.direction
  self.direction = d
  body()
  self.direction = saved
}

///|
/// `c` at `a` of its alpha (0 … 1).
pub fn alpha(c : Int64, a : Double) -> Int64 {
  let k = ((c & 0xFFL).to_double() * dclamp(a, 0.0, 1.0)).round().to_int64()
  (c & 0xFFFFFF00L) | k
}

///|
/// `top` laid over `under` (both RRGGBBAA; `under` taken as opaque): the colour it shows as.
pub fn over(under : Int64, top : Int64) -> Int64 {
  let a = (top & 0xFFL).to_double() / 255.0
  let ch = fn(sh : Int) -> Int64 {
    let u = ((under >> sh) & 0xFFL).to_double()
    let t = ((top >> sh) & 0xFFL).to_double()
    (u + (t - u) * a).round().to_int64() << sh
  }
  ch(24) | ch(16) | ch(8) | 0xFFL
}
