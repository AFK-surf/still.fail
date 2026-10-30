// The window's own buttons where they are the app's to draw (@ui.window_keys_own: Windows' and Linux's, a window with
// no title bar of the system's, the app's top row its title bar), as still.fail's desktop app drew them in its page's
// top row (web WindowControls.tsx, WindowControls.css.ts): after a rule, minimize, maximize or back as it was, close,
// as the bars' keys are (icon_button: 32, round, their icons 16 quiet till pointed at, 2 apart), close red under the
// hand. Over all the app shows, as a title bar is: on the line of the top row under them, each layout's
// (window_keys_at). What a top row at the window's top right holds stands before them (window_end_in, window_clear_in,
// tape_bar_end). The maximize one is the host's too (@ui.window_snap: Windows' Snap Layouts open from it as the pointer
// rests there), lit as the host says the pointer stands on it, which the app does not see (@ui.window_snap_state).

///|
/// The band laid out Small over the page where the window's buttons are the app's (the app's status_top): the bar
/// keys' 32 with 6 over and under, a bar's line's.
pub let window_keys_band : Double = 44.0

///|
/// How far in from the window's side the last button stands alone, as a bar's last key does where it cannot follow the
/// window's corner (frame.mbt's bar_in).
pub let window_keys_in : Double = 12.0

///|
/// The rule before the buttons (WindowControls.css.ts separator): 1 by 16, 8 after what is before it, 6 before the
/// first, then the buttons' 2 apart.
let window_rule_before : Double = 8.0

///|
let window_rule_after : Double = 6.0

///|
let window_rule_h : Double = 16.0

///|
let window_rule_w : Double = 1.0

///|
let window_keys_gap : Double = 2.0

///|
// kept across runs: a value (no field of it changes)
let window_rule : @ui.Style = @ui.style(
  w=Fixed(window_rule_w),
  h=Fixed(window_rule_h),
  ml=room(window_rule_before),
  mr=room(window_rule_after),
  bg=Line,
)

///|
/// Across, from what is before the rule to the last button's side.
pub fn window_keys_w() -> Double {
  window_rule_before + window_rule_w + window_rule_after + window_keys_gap + 3.0 * bar_key_side +
  2.0 * window_keys_gap
}

///|
/// Where the buttons stand in a window `width` wide: their top from the window's top, the last one's side from the
/// window's. In a window's whole (Large) on its bars' line (bar_keys_top), the last at the window's corner as a bar's
/// last key stands there (following it where it can, else alone); on the tape (Medium) on its panels' line, concentric
/// with the top right corner of the panel at the window's edge as its bar's last key is (tape_line, line_end_in);
/// laid out Small, in the band over the page.
pub fn window_keys_at(width : Double) -> (Double, Double) {
  match layout(width) {
    Small => ((window_keys_band - bar_key_side) / 2.0, window_keys_in)
    Medium => (window_in + tape_line, window_keys_side_tape())
    Large => (bar_keys_top(), window_keys_side())
  }
}

///|
/// In a window's whole, how far in from the window's side the last button stands.
fn window_keys_side() -> Double {
  if window_corner_key().follows() {
    bar_keys_top()
  } else {
    window_keys_in
  }
}

///|
/// On the tape, how far in from the window's side the last button stands: as the last key of the bar of the panel at
/// the window's edge stands in its top right corner.
fn window_keys_side_tape() -> Double {
  window_in + line_end_in(tape_edge.radius(), window_keys_in - window_in)
}

///|
/// What a top row at the window's top right in a window's whole (laid out Large) leaves the buttons, from the
/// window's side to before their rule: none where they are not the app's (window_end_in, window_clear_in).
pub fn window_keys_room() -> Double {
  if @ui.window_keys_own() {
    window_keys_side() + window_keys_w()
  } else {
    0.0
  }
}

///|
/// What a top row at the window's top right leaves the buttons in a window `width` wide, from the window's side to
/// before their rule, as they stand in its layout (window_keys_at): none where they are not the app's.
pub fn window_keys_room_at(width : Double) -> Double {
  if @ui.window_keys_own() {
    window_keys_at(width).1 + window_keys_w()
  } else {
    0.0
  }
}

///|
/// The same on the tape (laid out Medium), from the window's side (tape_bar_end; the strip of a panel at the window's
/// right holding them: sfdesk's tape_shows_right).
pub fn window_keys_room_tape() -> Double {
  if @ui.window_keys_own() {
    window_keys_side_tape() + window_keys_w()
  } else {
    0.0
  }
}

///|
/// The window's buttons over all the app shows, where they are the app's to draw: pressed, what they do
/// (@ui.window_act); the maximize one's place told the host each frame (@ui.window_snap).
pub fn window_keys(c : @ui.Ctx) -> Unit {
  if !@ui.window_keys_own() {
    return
  }
  let p = theme().p
  let (top, side) = window_keys_at(c.width)
  let zoomed = @ui.window_zoomed()
  let snap = @ui.window_snap_state()
  // (its corner a bar's last key's at the window's corner, the others' the same: one corner for the row)
  let link = window_corner_key()
  c.box(style=@ui.style(row=true, w=Full, pt=room(top), pr=room(side), justify=JEnd, align=AStart), fn() {
    c.box(style=@ui.style(row=true, align=ACenter, gap=room(window_keys_gap)), fn() {
      c.box(style=window_rule, fn() {  }) |> ignore
      if icon_button(c, "minus", key="window/minimize", round=true, linked=link, label=t("desktop.menu.minimize")) {
        @ui.window_act(1)
      }
      // (pressed with the keys alone: the pointer's press on it is the host's)
      if icon_button(
          c,
          if zoomed { "copy" } else { "square" },
          key="window/zoom",
          round=true,
          linked=link,
          on=snap == 2,
          lit=snap == 1,
          label=t(if zoomed { "desktop.window.restore" } else { "desktop.window.maximize" }),
        ) {
        @ui.window_act(2)
      }
      if icon_button(
          c,
          "close",
          key="window/close",
          round=true,
          linked=link,
          ink=p.red,
          label=t("desktop.menu.close"),
        ) {
        @ui.window_act(3)
      }
    })
    |> ignore
  })
  |> ignore
  // (the maximize one second from the side: the close one and the gap between them past it)
  let x = c.width - side - bar_key_side - window_keys_gap - bar_key_side
  @ui.window_snap(x, top, bar_key_side, bar_key_side)
}
