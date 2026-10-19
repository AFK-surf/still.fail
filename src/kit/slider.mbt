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
  { value: now, response: r.changed_to(told(c, now != value)) }
}

///|
/// A slider's look by its sizes (still.fail's): a hairline track `track_h` high in `track` (16% of the words' colour),
/// filled up to the thumb in `fill` (the theme's accent); a round thumb `thumb_d` across in the fill with a ring of
/// `ring` (the page's ground) round it, a size up while held.
pub fn slider_look_of(
  track_h? : Double = 2.0,
  thumb_d? : Double = 22.0,
  track? : Int64,
  fill? : Int64,
  ring? : Int64,
) -> (@ui.Ctx, SliderState) -> Unit {
  fn(c, s) {
    let t = c.theme()
    let (_, _, w, _) = s.rect
    let travel = if w > thumb_d { w - thumb_d } else { 0.0 }
    let k = if c.rtl() { 1.0 - s.t } else { s.t }
    let ink = fill.unwrap_or(t.accent)
    let d = if s.pressed { thumb_d + 4.0 } else { thumb_d }
    c.box(w=Fill(1.0), h=Px(thumb_d + 6.0), justify=JCenter, opacity=if s.disabled { 0.45 } else { 1.0 }, fn() {
      c.box(
        w=Fill(1.0),
        h=Px(track_h),
        padx=thumb_d / 2.0,
        dir=Row,
        justify=if c.rtl() { JEnd } else { JStart },
        fn() {
          c.box(w=Px(travel * s.t), h=Fill(1.0), bg=ink, fn() {  }) |> ignore
          c.box(w=Fill(1.0), h=Fill(1.0), bg=track.unwrap_or(@ui.alpha(t.fg, 0.16)), fn() {  }) |> ignore
        },
      )
      |> ignore
      c.layer(fn() {
        c.box(h=Fill(1.0), justify=JCenter, fn() {
          c.box(w=Px(thumb_d), h=Px(thumb_d), tx=travel * k, align=ACenter, justify=JCenter, fn() {
            c.box(w=Px(d), h=Px(d), radius=d / 2.0, bg=ink, border=3.0, border_color=ring.unwrap_or(t.bg), fn() {  })
            |> ignore
            focus_ring(c, s.focus_shown, (0.0, 0.0, thumb_d, thumb_d), thumb_d / 2.0)
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }
}

///|
/// The default look: a 2 high hairline, a 22 thumb in the accent ringed in the page's ground.
pub let slider_look : (@ui.Ctx, SliderState) -> Unit = slider_look_of()
