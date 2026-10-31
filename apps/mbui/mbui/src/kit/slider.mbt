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
  w? : @ui.Size = Px(240.0),
  label? : String = "",
  disabled? : Bool = false,
  look? : (@ui.Ctx, SliderState) -> Unit = slider_look,
) -> @ui.Changed[Double] {
  let id = c.id(key)
  let r = c.interact(id, disabled~, keys=0, focus_on_press=true)
  let span = if max > min { max - min } else { 1.0 }
  let mut now = snap(value, min, max, step)
  if !disabled {
    // The pointer: where it is along the track (last frame's), the value there. A tap can go down and up between
    // frames, so take its recorded position at a tap or drag end as well as a pointer still down.
    match c.drag_of(id) {
      Some(d) => {
        let tapped = d.take_tap()
        let ended = d.take_end()
        if d.down || tapped || ended {
          let (x, _, rw, _) = r.rect()
          // the thumb's middle runs from half a thumb in to half a thumb from the end
          if rw > thumb_room {
            let along = dclamp((d.x - x - thumb_room / 2.0) / (rw - thumb_room), 0.0, 1.0)
            let k = if c.rtl() { 1.0 - along } else { along }
            now = snap(min + k * span, min, max, step)
          }
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
  }
  let i = c.drag_area(if disabled { 0 } else { id }, axis=Horizontal, w~, fn() { look(c, st) })
  let shown = if step >= 1.0 && step.floor() == step {
    now.to_int().to_string()
  } else {
    now.to_string()
  }
  c.semantics(i, Slider, id~, label~, value=shown, range=(min, now, max), disabled~, actions=pick(disabled, [], [
    Increment, Decrement,
  ]))
  { value: now, response: r.changed_to(now != value) }
}

///|
/// How much of a slider's width its thumb's middle does not run along (a thumb's: half at each end).
let thumb_room : Double = 22.0

///|
/// A slider's look by its sizes (still.fail's, Reader.css.ts slider): a hairline track `track_h` high on `track` (16%
/// of `ink`, the words' colour), the part up to the thumb in `fill` (the accent); a round thumb `thumb_d` across in the
/// fill with a ring of `ring` (the page's ground) round it, 4 more while held; 28 high.
pub fn slider_look_of(
  track_h? : Double = 2.0,
  thumb_d? : Double = 22.0,
  ink? : Int64,
  track? : Int64,
  fill? : Int64,
  ring? : Int64,
) -> (@ui.Ctx, SliderState) -> Unit {
  fn(c, s) {
    let t = c.theme()
    let f = dclamp(s.t, 0.0, 1.0)
    let accent = fill.unwrap_or(t.accent)
    let rest = track.unwrap_or(@ui.alpha(ink.unwrap_or(t.fg), 0.16))
    c.box(w=Fill(1.0), h=Px(thumb_d + 6.0), justify=JCenter, opacity=if s.disabled { 0.45 } else { 1.0 }, fn() {
      c.box(dir=Row, padx=thumb_d / 2.0, h=Px(track_h), fn() {
        if f > 0.0 {
          c.box(w=Fill(f), h=Px(track_h), bg=accent, fn() {  }) |> ignore
        }
        if f < 1.0 {
          c.box(w=Fill(1.0 - f), h=Px(track_h), bg=rest, fn() {  }) |> ignore
        }
      })
      |> ignore
      c.layer(fn() {
        c.box(dir=Row, h=Fill(1.0), align=ACenter, fn() {
          if f > 0.0 {
            c.box(w=Fill(f), fn() {  }) |> ignore
          }
          let k = if s.pressed { thumb_d + 4.0 } else { thumb_d }
          c.box(w=Px(thumb_d), h=Px(thumb_d), align=ACenter, justify=JCenter, fn() {
            c.box(w=Px(k), h=Px(k), bg=accent, radius=k / 2.0, border=3.0, border_color=ring.unwrap_or(t.bg), fn() {  })
            |> ignore
            focus_ring(c, s.focus_shown, thumb_d / 2.0)
          })
          |> ignore
          if f < 1.0 {
            c.box(w=Fill(1.0 - f), fn() {  }) |> ignore
          }
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
