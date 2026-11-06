// A slider as nodes of the window's tree (parts.mbt's slider). Its track, thumb and focus ring are kept nodes; a
// pointer's events change the thumb at their own moments, without waiting for a frame.

///|
/// A setting between `min()` and `max()`, its value and colours followed as they change. `preview` is told as the
/// pointer goes down and moves, and if its last place changes as it is let go; `commit` is told its final value on
/// release. A key or a screen reader's step previews and commits in that event. `cancel` lets go of a preview when the
/// system calls off a hold or this node leaves. For a continuous value (`step() <= 0`), a key moves 1% of the range.
/// The returned node fills its parent's width and is 28 points high, as the old slider's look.
pub fn slider_node(
  parent : @view.View,
  value : () -> Double,
  min : () -> Double,
  max : () -> Double,
  preview : (Double) -> Unit,
  commit : (Double) -> Unit,
  step? : () -> Double = fn() { 0.0 },
  label? : () -> String = fn() { "" },
  ink? : () -> Int64 = fn() { theme().p.text },
  accent? : () -> Int64 = fn() { theme().p.accent },
  ground? : () -> Int64 = fn() { theme().p.canvas },
  disabled? : () -> Bool = fn() { false },
  cancel? : () -> Unit = fn() {  },
) -> @view.View {
  let draft : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
  let held = @signals.signal(false, same=fn(a, b) { a == b })
  let bounds = fn() { (min(), dmax(min(), max())) }
  let snapped = fn(x : Double) {
    let (lo, hi) = bounds()
    @kit.snap(x, lo, hi, step())
  }
  let now = fn() { snapped(draft.get().unwrap_or(value())) }
  let fraction = fn() {
    let (lo, hi) = bounds()
    if hi > lo { dmax(0.0, dmin(1.0, (now() - lo) / (hi - lo))) } else { 0.0 }
  }
  let across = fn() { if @ui.current().rtl() { 1.0 - fraction() } else { fraction() } }
  parent.box(fn(v) {
    let change = fn(to : Double) {
      preview(to)
      if v.alive() {
        commit(to)
      }
    }
    let step_by = fn(direction : Double) {
      let (lo, hi) = @signals.untracked(bounds)
      let s = @signals.untracked(step)
      let delta = if s > 0.0 { s } else { (hi - lo) / 100.0 }
      let was = @signals.untracked(now)
      let to = @signals.untracked(fn() { snapped(was + direction * delta) })
      if to != was { change(to) }
    }
    let by_key = fn(k : @view.Key) {
      if !v.focused() || disabled() || k.mods != 0 {
        return false
      }
      let (lo, hi) = @signals.untracked(bounds)
      let step_size = @signals.untracked(step)
      let delta = if step_size > 0.0 { step_size } else { (hi - lo) / 100.0 }
      let was = @signals.untracked(now)
      let rtl = @ui.current().rtl()
      let to = if k.code == @ui.key_code_up || k.code == (if rtl { @ui.key_code_left } else { @ui.key_code_right }) {
        Some(snapped(was + delta))
      } else if k.code == @ui.key_code_down || k.code == (if rtl { @ui.key_code_right } else { @ui.key_code_left }) {
        Some(snapped(was - delta))
      } else if k.code == @ui.key_code_page_up {
        Some(snapped(was + 10.0 * delta))
      } else if k.code == @ui.key_code_page_down {
        Some(snapped(was - 10.0 * delta))
      } else if k.code == @ui.key_code_home {
        Some(lo)
      } else if k.code == @ui.key_code_end {
        Some(hi)
      } else {
        None
      }
      match to {
        Some(x) => {
          if x != was { change(x) }
          true
        }
        None => false
      }
    }
    v
    .width_share(Is(1.0))
    .height(Is(Some(28.0)))
    .min_width(Is(Some(0.0)))
    .presses(By(fn() { !disabled() }))
    .focusable(By(fn() { !disabled() }), keys=0)
    .alpha(By(fn() { if disabled() { 0.45 } else { 1.0 } }))
    .claims(fn(dx, dy) { dx.abs() > @ui.touch_slop() && dx.abs() > dy.abs() }, at_down=true)
    .says(By(fn() {
      let (lo, hi) = bounds()
      let x = now()
      let s = step()
      let shown = if s >= 1.0 && s.floor() == s { x.to_int().to_string() } else { x.to_string() }
      Some(@view.said(Slider, label=label(), value=shown, range=(lo, x, hi), actions=if disabled() { [] } else { [Increment, Decrement] }))
    }))
    .on_key(by_key)
    .on_action(fn(action) {
      match action {
        Increment => step_by(1.0)
        Decrement => step_by(-1.0)
        _ => ()
      }
    })
    .on_drag(fn(d) {
      if d.kind == Off {
        if held.get() {
          held.set(false)
          draft.set(None)
          cancel()
        }
        return
      }
      if disabled() { return }
      let (lo, hi) = @signals.untracked(bounds)
      let to = if d.w > 22.0 {
        let f = dmax(0.0, dmin(1.0, (d.x - 11.0) / (d.w - 22.0)))
        let f = if @ui.current().rtl() { 1.0 - f } else { f }
        @signals.untracked(fn() { snapped(lo + f * (hi - lo)) })
      } else {
        @signals.untracked(now)
      }
      match d.kind {
        Down => {
          // A finger may be taken over by a scrolling ancestor until this slider wins across; a mouse drags directly.
          v.yield_drag(@ui.pointing() is Finger)
          // A finger using a nearby control leaves an editor's keyboard alone, as an old view's focus_on_press does.
          if @ui.pointing() is Mouse || @ui.focused_field_in() is None {
            v.ask_focus() |> ignore
          }
          if !v.alive() || disabled() { return }
          held.set(true)
          draft.set(Some(to))
          preview(to)
        }
        Moved => if held.get() {
          draft.set(Some(to))
          preview(to)
        }
        Up => if held.get() {
          let was = draft.get()
          draft.set(Some(to))
          if was != Some(to) { preview(to) }
          if v.alive() {
            held.set(false)
            draft.set(None)
            commit(to)
          }
        }
        Off => ()
      }
    })
    |> ignore
    v.owns(fn() { if held.get() { held.set(false); cancel() } }) |> ignore
    // (the 2-point track begins and ends at the thumb's centre)
    v.box(fn(at) {
      at.over(Is(true)).padding(Is((11.0, 0.0, 11.0, 0.0))).lies_along(Is(Middle)) |> ignore
      at.box(fn(track) {
        track.width_share(Is(1.0)).height(Is(Some(2.0))).ground(By(fn() { alpha(ink(), 0.16) })) |> ignore
        track.box(fn(fill) {
          fill.over(Is(true)).ground(By(accent)).ground_drawn(Painted(fn(laid) {
            let w = laid.size(track).unwrap_or((0.0, 0.0)).0
            let part = w * fraction()
            let x = if @ui.current().rtl() { w - part } else { 0.0 }
            (x, 0.0, part - w, 0.0)
          })) |> ignore
        }) |> ignore
      }) |> ignore
    }) |> ignore
    v.box(fn(at) {
      at.over(Is(true)).lines_up(Is(Some(Start))).lies_along(Is(Middle)) |> ignore
      at.box(fn(room) {
        room.width(Is(Some(22.0))).height(Is(Some(22.0))).offset(Painted(fn(laid) {
          let w = laid.size(v).unwrap_or((0.0, 0.0)).0
          (dmax(0.0, w - 22.0) * across(), 0.0)
        })) |> ignore
        room.box(fn(knob) {
          knob.width_share(Is(1.0)).height_share(Is(1.0)).radius(By(fn() { if held.get() { 13.0 } else { 11.0 } }))
          .ground_drawn(By(fn() { if held.get() { (-2.0, -2.0, 4.0, 4.0) } else { (0.0, 0.0, 0.0, 0.0) } }))
          .ground(By(accent)).edge(By(fn() { (3.0, ground()) })) |> ignore
        }) |> ignore
        room.show(fn() { v.focus_shown() }, fn(ring) {
          let out = fn() { @ui.tree_theme().focus_gap + @ui.tree_theme().focus_w }
          ring.over(Is(true)).margin(By(fn() { (-out(), -out(), -out(), -out()) }))
          .radius(By(fn() { 11.0 + out() })).edge(By(fn() { (@ui.tree_theme().focus_w, @ui.tree_theme().focus) })) |> ignore
        })
      }) |> ignore
    }) |> ignore
  })
}
