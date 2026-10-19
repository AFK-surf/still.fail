// A slider (Radix's Slider): a number between `min` and `max` in steps of `step`, the value the view's. Its thumb is
// dragged (a press on the track jumps it there first); with the focus the arrows move it a step (Right and Up more,
// Left and Down less; mirrored right to left), Page Up and Down ten steps, Home and End to the ends; Increment and
// Decrement asked of it do a step. It reports what it became.

///|
/// What a slider's look is given: where the thumb is (0 at min … 1 at max), pointed at, held (being dragged), focus
/// shown, disabled, where it was last frame.
pub(all) struct SliderState {
  t : Double
  hovered : Bool
  pressed : Bool
  focus_shown : Bool
  disabled : Bool
  rect : (Double, Double, Double, Double)
}

///|
/// `v` held between `min` and `max`, on the nearest step from `min`.
pub fn snap(v : Double, min : Double, max : Double, step : Double) -> Double {
  let x = if v < min { min } else if v > max { max } else { v }
  if step <= 0.0 {
    return x
  }
  let n = ((x - min) / step).round()
  let y = min + n * step
  if y > max {
    max
  } else {
    y
  }
}

///|
/// A slider (see the file's head) at `value` (its id `key`'s), named `label` for the semantics tree, `w` wide. What
/// it became, and what happened.
pub fn slider(
  c : @ui.Ctx,
  key : String,
  value : Double,
  min? : Double = 0.0,
  max? : Double = 100.0,
  step? : Double = 1.0,
  w? : Double = 240.0,
  label? : String = "",
  disabled? : Bool = false,
  look? : (@ui.Ctx, SliderState) -> Unit = slider_look,
) -> @ui.Changed[Double] {
  let id = c.id(key)
  let r = c.interact(id, disabled~, keys=0, focus_on_press=true)
  let span = if max > min { max - min } else { 1.0 }
  let mut now = snap(value, min, max, step)
  if !disabled {
    // the pointer: where it is along the track (last frame's), the value there
    match c.drag_of(id) {
      Some(d) if d.down => {
        let (x, _, rw, _) = r.rect
        if rw > 0.0 {
          let along = (d.x - x) / rw
          let k = if c.rtl() { 1.0 - along } else { along }
          now = snap(min + k * span, min, max, step)
        }
      }
      _ => ()
    }
    // the keys, while it has the focus
    if r.focused {
      let (more, less) = if c.rtl() {
        (@ui.key_code_left, @ui.key_code_right)
      } else {
        (@ui.key_code_right, @ui.key_code_left)
      }
      if c.take_key(more) || c.take_key(@ui.key_code_up) {
        now = snap(now + step, min, max, step)
      }
      if c.take_key(less) || c.take_key(@ui.key_code_down) {
        now = snap(now - step, min, max, step)
      }
      if c.take_key(@ui.key_code_page_up) {
        now = snap(now + step * 10.0, min, max, step)
      }
      if c.take_key(@ui.key_code_page_down) {
        now = snap(now - step * 10.0, min, max, step)
      }
      if c.take_key(@ui.key_code_home) {
        now = min
      }
      if c.take_key(@ui.key_code_end) {
        now = max
      }
    }
    if c.action_asked(id, Increment) {
      now = snap(now + step, min, max, step)
    }
    if c.action_asked(id, Decrement) {
      now = snap(now - step, min, max, step)
    }
  }
  let held = match c.drag_of(id) {
    Some(d) => d.down && !disabled
    None => false
  }
  let st = {
    t: (now - min) / span,
    hovered: r.hovered,
    pressed: held,
    focus_shown: r.focus_shown,
    disabled,
    // as wide as it is made (known before it is first laid out, and while disabled, when nothing tracks it)
    rect: (r.rect.0, r.rect.1, w, r.rect.3),
  }
  let i = c.drag_area(if disabled { 0 } else { id }, axis=Horizontal, w=Px(w), fn() { look(c, st) })
  let shown = if step >= 1.0 && step.floor() == step {
    now.to_int().to_string()
  } else {
    now.to_string()
  }
  c.semantics(i, Slider, id~, label~, value=shown, range=(min, max, now), disabled~, actions=pick(disabled, [], [
    Increment, Decrement,
  ]))
  { value: now, response: r.changed_to(now != value) }
}

///|
/// A slider's look by its sizes: a track `track_h` high in `track` (the theme's faint), filled up to the thumb in
/// `fill` (its accent), a round thumb `thumb_d` across in `thumb` (its thumb) with a shadow.
pub fn slider_look_of(
  track_h? : Double = 4.0,
  thumb_d? : Double = 24.0,
  track? : Int64,
  fill? : Int64,
  thumb? : Int64,
) -> (@ui.Ctx, SliderState) -> Unit {
  fn(c, s) {
    let t = c.theme()
    let (_, _, w, _) = s.rect
    let travel = if w > thumb_d { w - thumb_d } else { 0.0 }
    let k = if c.rtl() { 1.0 - s.t } else { s.t }
    c.box(
      w=Fill(1.0),
      h=Px(thumb_d),
      justify=JCenter,
      opacity=if s.disabled { disabled_alpha } else { 1.0 },
      fn() {
        c.box(
          w=Fill(1.0),
          h=Px(track_h),
          radius=track_h / 2.0,
          bg=track.unwrap_or(t.faint),
          dir=Row,
          justify=if c.rtl() { JEnd } else { JStart },
          fn() {
            c.box(
              w=Px(thumb_d / 2.0 + travel * s.t),
              h=Fill(1.0),
              radius=track_h / 2.0,
              bg=fill.unwrap_or(t.accent),
              fn() {  },
            )
            |> ignore
          },
        )
        |> ignore
        c.layer(fn() {
          c.box(
            w=Px(thumb_d),
            h=Px(thumb_d),
            radius=thumb_d / 2.0,
            bg=tinted(c, thumb.unwrap_or(t.thumb), s.hovered, s.pressed),
            shadow=4.0,
            shadow_color=0x00000040L,
            shadow_y=1.5,
            tx=travel * k,
            fn() {  },
          )
          |> ignore
        })
        |> ignore
        focus_ring(c, s.focus_shown, s.rect, thumb_d / 2.0)
      },
    )
    |> ignore
  }
}

///|
/// The default look: a 4 high track, filled with the accent, a 24 white thumb.
pub let slider_look : (@ui.Ctx, SliderState) -> Unit = slider_look_of()
