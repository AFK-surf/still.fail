// What the views built under it look like unless they say (SwiftUI's environment, Compose's CompositionLocal, egui's
// Style): the theme's colours, corners and sizes, and which way words and rows run. The app sets it once (it stays
// from frame to frame) or for a part of what it builds (Ctx::with_theme, Ctx::with_direction); the widgets read their
// defaults from it, and what a call says itself still wins. docs/components.md says how the components use it.

///|
/// The theme: colours RRGGBBAA, corners and sizes in logical pixels. Made from Theme::light or Theme::dark and changed
/// where the app differs (`{ ..Theme::light(), accent: 0x… }`).
pub(all) struct Theme {
  /// dark (what draws over it picks its own shades by it)
  dark : Bool
  /// the page's ground
  bg : Int64
  /// what lies over the page: panels, menus, dialogs, popovers, toasts
  surface : Int64
  /// words
  fg : Int64
  /// quieter words: a description, a placeholder, what is off
  muted : Int64
  /// the ground of quiet parts: a track, a switch that is off, a chip, a segmented control
  faint : Int64
  /// lines: a separator, a field's or a panel's edge
  border : Int64
  /// the one colour: what is on, chosen, filled; a button that is the thing to do
  accent : Int64
  /// words and marks over the accent
  on_accent : Int64
  /// what is on that is not a choice of colour: a switch's ground (iOS's green)
  positive : Int64
  /// what cannot be undone, what failed
  danger : Int64
  /// words and marks over `danger`
  on_danger : Int64
  /// laid over what is pointed at or pressed (a tint: its alpha says how much)
  hover : Int64
  /// the ring round what has the keyboard's focus
  focus : Int64
  /// the page under a modal (a dialog's)
  scrim : Int64
  /// what lies over the page casts
  shadow : Int64
  /// a switch's knob, a slider's thumb
  thumb : Int64
  /// the corner of controls (a button, a field, a checkbox's box is a third of it)
  radius : Double
  /// the corner of what lies over the page (a dialog, a menu, a popover)
  radius_lg : Double
  /// words' size, and the smaller one (a description, a tooltip, a badge)
  font : Double
  font_sm : Double
  /// a control's height (a button, a field, a select's trigger)
  control_h : Double
  /// the focus ring's width, and how far out of what it rings it lies
  focus_w : Double
  focus_gap : Double
}

///|
/// The light theme: the iOS colours mbui's widgets have always had.
pub fn Theme::light() -> Theme {
  {
    dark: false,
    bg: 0xFFFFFFFFL,
    surface: 0xFFFFFFFFL,
    fg: 0x1D1D1FFFL,
    muted: 0x8E8E93FFL,
    faint: 0xE3E3E8FFL,
    border: 0xD1D1D6FFL,
    accent: 0x0A84FFFFL,
    on_accent: 0xFFFFFFFFL,
    positive: 0x34C759FFL,
    danger: 0xFF3B30FFL,
    on_danger: 0xFFFFFFFFL,
    hover: 0x0000000FL,
    focus: 0x0A84FF99L,
    scrim: 0x00000059L,
    shadow: 0x0000002EL,
    thumb: 0xFFFFFFFFL,
    radius: 10.0,
    radius_lg: 14.0,
    font: 15.0,
    font_sm: 13.0,
    control_h: 36.0,
    focus_w: 2.0,
    focus_gap: 2.0,
  }
}

///|
/// The dark theme: iOS's dark colours.
pub fn Theme::dark() -> Theme {
  {
    ..Theme::light(),
    dark: true,
    bg: 0x000000FFL,
    surface: 0x1C1C1EFFL,
    fg: 0xF5F5F7FFL,
    muted: 0x8E8E93FFL,
    faint: 0x3A3A3CFFL,
    border: 0x38383AFFL,
    accent: 0x0A84FFFFL,
    positive: 0x30D158FFL,
    danger: 0xFF453AFFL,
    hover: 0xFFFFFF17L,
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
