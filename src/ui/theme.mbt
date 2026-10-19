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
  }
}

///|
/// The theme in force where the view is building.
pub fn Ctx::theme(self : Ctx) -> Theme {
  self.theme
}

///|
/// The theme from here on (this frame's rest and the next frames'), until set again.
pub fn Ctx::set_theme(self : Ctx, t : Theme) -> Unit {
  self.theme = t
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
