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
  /// what is drawn to be seen with nothing in it, at its faintest: a line (a panel's edge, a separator), a gauge's
  /// empty cell, a placeholder's block, a sheet's grip. The ink at an opacity, so that it stands as far off whatever
  /// it lies on (the page, a card, a menu): at least contrast_mark_least (contrast.mbt), an opaque grey being that on
  /// the page alone (a menu's columns' lines not seen in the dark, a station's empty cells on its card, 2026-10-26)
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
  /// a quiet ground under what is in it (a pill's, a bubble's, a picture's before it comes): the ink at an opacity, a
  /// step off whatever it lies on as `line` is (fainter: what is in it carries it)
  neutral : Int64
  /// what is chosen in a list
  selected : Int64
  /// links
  link : Int64
  /// someone else at the controls (Color's Warn)
  warn : Int64
  /// words said in warn's colour (Color's WarnInk): its amber dark enough to read on the theme's grounds (4.5:1, WCAG's
  /// AA), as accent_text is the accent's; `warn` itself is a mark's, a dot's, a bar's
  warn_ink : Int64
  /// what is lifted out of a tinted track (Color's Lifted), drawn over the track: in the light opaque white, a shadow
  /// lifting it; in the dark, where a shadow does not show, the ink at an opacity, a step lighter than the track on
  /// whatever ground the track lies on (an opaque grey is lighter than a track on the page, darker than one on a card)
  lifted : Int64
  /// a quiet wash under what comes onto it (Color's Wash)
  wash : Int64
  /// a sidebar's ground beside the page (Color's Sidebar)
  sidebar : Int64
  /// a list's ground, a step off the page (Color's ListGround)
  list : Int64
  /// the sizes of words with their lines' heights (style.mbt's TextSize), the lines' heights said on their own
  /// (Leading), and the corners (Radius)
  text : TextScale
  leading : LeadingScale
  radii : RadiusScale
  /// the corners nested things keep to, outermost first (still.fail's ladder: each a step in from the one before,
  /// what lies in a container's corner as far in as makes it the next): a rounded container with something in its
  /// corner, and a smooth one there, each round by one of them; a capsule or a circle round by its shape. None said:
  /// any (Tester::corner_faults)
  corner_ladder : Array[Double]
  /// how round what lies in a container's corner may be, and how far from its edges, to be concentric with it
  /// (CornerFit); None: any, as concentric asks
  corner_fit : CornerFit?
  /// how far apart two things that light up under the hand stand at least (the spacing rules, gaps.mbt: the web's
  /// sidebar rows 2); 0: not held
  lit_apart : Double
  /// how far in from the sides of the box with a ground round it a row that lights up under the hand stands, where it
  /// runs across it (the spacing rules, gaps.mbt rule 7: still.fail's 6, a menu's rows in its panel, a list's in its
  /// card); 0: not held
  lit_reach : Double
  /// the height of a line of words that say none, a size of words (1.4: CSS's `line-height: 1.4`, still.fail's
  /// apps'); 0: the host's own (its system's, about 1.42)
  text_line : Double
  /// the app's own words with their digits all one width (@hostapi.style_tabular: a number keeps its width as it
  /// changes, CSS's `font-variant-numeric: tabular-nums` on a page's root) where they say nothing of it; what people
  /// wrote (`words`), a face shown in itself and a book's pages keep the font's own figures. false: the font's own
  /// everywhere, the system's way (San Francisco's figures are proportional, Roboto's and Segoe UI's tabular)
  tabular : Bool
}

///|
/// The sizes of words, each with its line's height (size, line): the roles' (TextSize Caption … Display), then the
/// scale's.
pub(all) struct TextScale {
  caption : (Double, Double)
  meta : (Double, Double)
  ui : (Double, Double)
  body : (Double, Double)
  title : (Double, Double)
  heading : (Double, Double)
  display : (Double, Double)
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
  xl5 : (Double, Double)
  xl6 : (Double, Double)
  xl7 : (Double, Double)
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
    xl5: (48.0, 48.0),
    xl6: (60.0, 60.0),
    xl7: (72.0, 72.0),
    // the roles on Tailwind's: xs, xs, sm, base, xl, 3xl, 4xl
    caption: (12.0, 16.0),
    meta: (12.0, 16.0),
    ui: (14.0, 20.0),
    body: (16.0, 24.0),
    title: (20.0, 28.0),
    heading: (30.0, 36.0),
    display: (36.0, 40.0),
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
    muted: 0x565B62FFL,
    subtle: 0x565B62FFL,
    faint: 0xF1F1F2FFL,
    border: 0xC1C4C9FFL,
    line: 0x322D2424L,
    accent: 0xDC5929FFL,
    on_accent: 0xFFFFFFFFL,
    primary: 0x24272BFFL,
    on_primary: 0xFFFFFFFFL,
    positive: 0x006A3FFFL,
    danger: 0x9A2830FFL,
    on_danger: 0xFFFFFFFFL,
    hover: 0x26211711L,
    field_hover: 0x9A9EA3FFL,
    focus: 0x646970FFL,
    scrim: 0x13161B33L,
    shadow: 0x13161B1AL,
    thumb: 0xFFFFFFFFL,
    radius: 12.0,
    radius_lg: 20.0,
    // (a field 36 high, 24 in, in its corners: 24 + 18 as a circle reads it, smooth.mbt round_like_out)
    radius_dialog: round_like_out(42.0),
    font: 13.0,
    font_sm: 12.0,
    font_title: 16.0,
    font_heading: 22.0,
    control_h: 36.0,
    focus_w: 2.0,
    focus_gap: 2.0,
    raised: 0xE4E4E8FFL,
    card: 0xF6F6F7FFL,
    accent_text: 0x982E01FFL,
    accent_bg: 0x982E012EL,
    danger_bg: 0x9A28302EL,
    neutral: 0x24272B13L,
    selected: 0xEBE7E1FFL,
    link: 0x0047AEFFL,
    warn: 0xD9962BFFL,
    warn_ink: 0x6E4802FFL,
    lifted: 0xFFFFFFFFL,
    // #322D24 at 6.5%
    wash: 0x322D2411L,
    sidebar: 0xF6F5F1FFL,
    // oklch(98.5% .002 85)
    list: 0xFBFAF9FFL,
    text: TextScale::tailwind(),
    leading: LeadingScale::tailwind(),
    text_line: 0.0,
    radii: RadiusScale::tailwind(),
    corner_ladder: [],
    corner_fit: None,
    lit_apart: 0.0,
    lit_reach: 0.0,
    tabular: false,
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
    muted: 0xA8AAAEFFL,
    subtle: 0xA8AAAEFFL,
    faint: 0x313237FFL,
    border: 0x3D3F44FFL,
    line: 0xE9E9EA19L,
    accent: 0xE97342FFL,
    warn_ink: 0xE6B55DFFL,
    primary: 0xECEDEDFFL,
    on_primary: 0x1F2023FFL,
    positive: 0x68C894FFL,
    danger: 0xFF9A97FFL,
    on_danger: 0x1F2023FFL,
    hover: 0xFFFFFF0DL,
    field_hover: 0x5D6066FFL,
    focus: 0x8A8D93FFL,
    scrim: 0x00000080L,
    shadow: 0x00000073L,
    raised: 0x2A2C31FFL,
    card: 0x28292CFFL,
    accent_text: 0xFF9E71FFL,
    accent_bg: 0xFF9E7129L,
    danger_bg: 0xFF9A9729L,
    neutral: 0xE9E9EA0EL,
    selected: 0x323338FFL,
    sidebar: 0x19191BFFL,
    list: 0x1C1D20FFL,
    link: 0x8EB8FEFFL,
    // the ink at 12% over the track (the ink at 6%): 1.39 to 1 off it on the darkest ground and the lightest; the
    // opaque 3A3B40 was 1.05 to 1 off a track on a raised ground, and the canvas the wide segmented had 1.02 off one
    // on the page (2026-10-27: "dark mode 下单选滑块几乎分辨不清")
    lifted: 0xE9E9EA1FL,
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
    muted: 0x535559FFL,
    subtle: 0x535559FFL,
    faint: 0xEFECE6FFL,
    line: 0x322D2424L,
    accent: 0xCC5A34FFL,
    positive: 0x2F8F5BFFL,
    danger: 0x991302FFL,
    hover: 0x24272B0FL,
    font: 15.0,
    font_sm: 13.0,
    control_h: 38.0,
    raised: 0xFFFFFFFFL,
    card: 0xFFFFFFFFL,
    accent_text: 0x8F2B01FFL,
    accent_bg: 0x8F2B012EL,
    danger_bg: 0x9913022EL,
    neutral: 0x322D2413L,
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
    muted: 0xB8BBC1FFL,
    subtle: 0xB8BBC1FFL,
    faint: 0x313237FFL,
    line: 0xECECED1FL,
    accent: 0xE8734FFFL,
    positive: 0x5CC08AFFL,
    danger: 0xFE9D8CFFL,
    warn_ink: 0xEEAA44FFL,
    hover: 0xECECED14L,
    font: 15.0,
    font_sm: 13.0,
    control_h: 38.0,
    raised: 0x2A2C31FFL,
    card: 0x26272BFFL,
    accent_text: 0xF6A383FFL,
    accent_bg: 0xF6A38329L,
    danger_bg: 0xFE9D8C29L,
    neutral: 0xECECED1BL,
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
    warn_ink: 0x983F00FFL,
    lifted: 0xFFFFFFFFL,
    // #322D24 at 6.5%
    wash: 0x322D2411L,
    sidebar: 0xF2F2F7FFL,
    list: 0xFFFFFFFFL,
    text: TextScale::tailwind(),
    leading: LeadingScale::tailwind(),
    text_line: 0.0,
    radii: RadiusScale::tailwind(),
    corner_ladder: [],
    corner_fit: None,
    lit_apart: 0.0,
    lit_reach: 0.0,
    tabular: false,
  }
}

///|
/// iOS's dark colours.
pub fn Theme::ios_dark() -> Theme {
  {
    ..Theme::ios_light(),
    dark: true,
    warn_ink: 0xFF9F0AFFL,
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
    WarnInk => self.warn_ink
    Tint => alpha(self.fg, 0.06)
    TintStrong => self.line
    Floating => over(self.bg, alpha(self.raised, 0.72))
    Veil => 0x0000009EL
    VeilDeep => 0x000000EBL
    OnVeil => 0xFFFFFFFFL
    Lifted => self.lifted
    Wash => self.wash
    Sidebar => self.sidebar
    ListGround => self.list
    FieldHover => self.field_hover
    Theater => 0x000000FFL
    A(c, o) => alpha(self.color(c), o.value())
    Over(u, t) => over(self.color(u), self.color(t))
    Exact(v) => v
    Data(v) => v
  }
}

///|
/// A size of words in this theme: (size, line).
pub fn Theme::text_size(self : Theme, s : TextSize) -> (Double, Double) {
  match s {
    Caption => self.text.caption
    Meta => self.text.meta
    Ui => self.text.ui
    Body => self.text.body
    Title => self.text.title
    Heading => self.text.heading
    Display => self.text.display
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
    Xl5 => self.text.xl5
    Xl6 => self.text.xl6
    Xl7 => self.text.xl7
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
/// A corner in this theme (`Inner` and `Around` are worked out once laid out: 0 here; `InnerOr` its own here, the
/// container's once laid out where it lies in a corner of one; `Corners` the roundest of its four, each its own as a box
/// is drawn: Radius::each).
pub fn Theme::corner(self : Theme, r : Radius) -> Double {
  match r {
    Sharp | Inner | Around => 0.0
    InnerOr(own) => self.corner(own)
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
    // (each its own: the roundest here, each in Ctx::box's corners)
    Corners(a, b, c, d) =>
      dmax(
        dmax(exact_ok(a, "Radius"), exact_ok(b, "Radius")),
        dmax(exact_ok(c, "Radius"), exact_ok(d, "Radius")),
      )
    // (where it comes from, now: corner_of.mbt)
    Linked(c) => c.radius(corner_roots())
    LinkedEach(a, b, c, d) => {
      let at = corner_roots()
      dmax(dmax(a.radius(at), b.radius(at)), dmax(c.radius(at), d.radius(at)))
    }
  }
}

///|
/// The corners of `r` each its own (top left, top right, bottom right, bottom left), where they are not one: `Corners`,
/// alone or as what `InnerOr` keeps.
pub fn Radius::each(self : Radius) -> FixedArray[Double]? {
  match self {
    Corners(a, b, c, d) => Some(FixedArray::from_array([a, b, c, d]))
    LinkedEach(a, b, c, d) => {
      let at = corner_roots()
      Some(FixedArray::from_array([a.radius(at), b.radius(at), c.radius(at), d.radius(at)]))
    }
    InnerOr(own) => own.each()
    _ => None
  }
}

///|
/// Where the corners of `r` come from, each (top left, then round it), where they are linked: `Linked`, `LinkedEach`,
/// or what `InnerOr` keeps; None where they are not.
pub fn Radius::links(self : Radius) -> FixedArray[CornerOf]? {
  match self {
    Linked(c) => Some(FixedArray::make(4, c))
    LinkedEach(a, b, c, d) => Some(FixedArray::from_array([a, b, c, d]))
    InnerOr(own) => own.links()
    _ => None
  }
}

///|
/// `body` built under theme `t` (a dark panel in a light page, a part restyled), the theme as it was after it.
pub fn Ctx::with_theme(self : Ctx, t : Theme, body : () -> Unit) -> Unit {
  let saved = self.theme
  self.theme = t
  if t.corner_ladder.length() > 0 {
    self.corner_ladder = t.corner_ladder
  }
  if t.corner_fit is Some(_) {
    self.corner_fit = t.corner_fit
  }
  if t.lit_apart > 0.0 {
    self.lit_apart = t.lit_apart
  }
  if t.lit_reach > 0.0 {
    self.lit_reach = t.lit_reach
  }
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
/// `top` laid over `under` (both RRGGBBAA): the colour it shows as; over a tint (a ground pointed at laid over a
/// translucent one: style.mbt Patch::lit_by), the two as one tint, as much of what is under them showing through.
pub fn over(under : Int64, top : Int64) -> Int64 {
  let a = (top & 0xFFL).to_double() / 255.0
  let ua = (under & 0xFFL).to_double() / 255.0
  if ua < 1.0 {
    let oa = a + ua * (1.0 - a)
    if oa <= 0.0 {
      return 0L
    }
    let mix = fn(sh : Int) -> Int64 {
      let u = ((under >> sh) & 0xFFL).to_double()
      let t = ((top >> sh) & 0xFFL).to_double()
      ((t * a + u * ua * (1.0 - a)) / oa).round().to_int64() << sh
    }
    return mix(24) | mix(16) | mix(8) | (oa * 255.0).round().to_int64()
  }
  let ch = fn(sh : Int) -> Int64 {
    let u = ((under >> sh) & 0xFFL).to_double()
    let t = ((top >> sh) & 0xFFL).to_double()
    (u + (t - u) * a).round().to_int64() << sh
  }
  ch(24) | ch(16) | ch(8) | 0xFFL
}
