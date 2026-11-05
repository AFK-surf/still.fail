// The list catching up on what changed while away as nodes of the window's tree (sync_key's): its refresh mark turning
// by the clock, brought to rest once all is here, its arrows drawn back, the tick drawn, held, faded; each of its steps
// a way declared from the moment of its cause, nothing built anew as it goes.

///|
/// The list catching up (sync_key's) in node `parent`: `side` across, the refresh mark (`mark`, in the grey of what it
/// says nothing of) turning a turn each sync_turn_ms, slow at its ends, once `shown()` has held later_ms (a moment's
/// catching up shows nothing), faded in as a presence comes; once it stops, the mark goes on from where it is and as
/// fast as it turns to rest where it looks as upright (sync_rest), its arrows drawn back along their strokes, then the
/// tick drawn as a hand ticks; there sync_done_ms, then it fades (sync_out_ms). `text()` its tip (in `tips`) and what it
/// is read out as, the last said while it goes. Nothing of it laid out while it is not there (none of its row's gap).
pub fn sync_key_node(
  parent : @view.View,
  tips : TipLayer,
  side : Double,
  mark : Double,
  shown : () -> Bool,
  text : () -> String,
) -> Unit {
  // (shown long enough; seen so (only then the tick); where it rests once all is here; held with its tick)
  let long = @signals.signal(false, same=fn(a, b) { a == b })
  let seen = @signals.signal(false, same=fn(a, b) { a == b })
  let rest : @signals.Signal[SyncRest?] = @signals.signal(None)
  let held = @signals.signal(false, same=fn(a, b) { a == b })
  let said = @signals.signal(@signals.untracked(text), same=fn(a, b) { a == b })
  // (how far it is there (a presence's: faded in as it comes, out as it goes); on to rest; the arrows drawn back; the
  // tick drawn)
  let there = EdgeWay::new(0.0)
  let resting = EdgeWay::new(0.0)
  let back = EdgeWay::new(0.0)
  let drawn = EdgeWay::new(0.0)
  let o = parent
  let waits = Ref(fn() {  })
  let holds = Ref(fn() {  })
  let leaves = Ref(fn() {  })
  // shown: what it says kept; long enough once it has held later_ms (from the moment it began to)
  o.reacts(shown, fn(on) {
    (waits.val)()
    waits.val = fn() {  }
    if on {
      said.set(@signals.untracked(text))
      waits.val = o.at_moment(o.cause_at() + later_ms, fn() { long.set(true) })
    } else {
      long.set(false)
    }
  })
  o.reacts(text, fn(s) { if @signals.untracked(shown) { said.set(s) } })
  o.reacts(fn() { shown() && long.get() }, fn(on) { if on { seen.set(true) } })
  // done: brought to rest from where it is at that moment, the arrows back, the tick drawn, held, then let go
  o.reacts(fn() { seen.get() && !shown() }, fn(ticked) {
    (holds.val)()
    holds.val = fn() {  }
    if ticked {
      let at = o.cause_at()
      let r = sync_rest(at)
      let settle = r.ms * sync_rest_gone
      rest.set(Some(r))
      held.set(true)
      resting.go_by(o, 1.0, @motion.tween_to(duration=r.ms, ease=fn(s) { r.ease(s) }))
      back.go_by(o, 1.0, @motion.tween(sync_back_ms, ease=InOut, delay=settle))
      drawn.go_by(o, 1.0, @motion.tween(sync_tick_ms, ease=Out, delay=settle + sync_back_ms * 0.6))
      holds.val = o.at_moment(at + settle + sync_back_ms + sync_tick_ms + sync_done_ms, fn() { held.set(false) })
    } else {
      rest.set(None)
      held.set(false)
      resting.put(0.0)
      back.put(0.0)
      drawn.put(0.0)
    }
  })
  // there while it turns or holds its tick, faded in and out as a presence; all it was forgotten once gone
  o.reacts(fn() { (shown() && long.get()) || held.get() }, fn(on) {
    (leaves.val)()
    leaves.val = fn() {  }
    if on {
      there.go_by(o, 1.0, @motion.tween(@kit.presence_in_ms, ease=Out))
    } else {
      there.go_by(o, 0.0, @motion.tween(sync_out_ms, ease=Leave))
      leaves.val = o.at_moment(there.end(), fn() {
        seen.set(false)
        rest.set(None)
        resting.put(0.0)
        back.put(0.0)
        drawn.put(0.0)
      })
    }
  })
  o.show(fn() { (shown() && long.get()) || held.get() || there.target() > 0.0 || there.shown(o) > 0.0 }, fn(k) {
    k
    .width(Is(Some(side)))
    .height(Is(Some(side)))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .alpha(By(fn() { dmin(1.0, there.shown(k)) }))
    .says(By(fn() { Some(@view.said(Status, label=said.get())) }))
    |> ignore
    k.box(fn(m) {
      m.width(Is(Some(mark))).height(Is(Some(mark))) |> ignore
      // the refresh mark: turning by the clock, then on to rest, then drawn back along its strokes
      m.show(fn() { back.shown(m) < 1.0 }, fn(a) {
        a
        .over(Is(true))
        .width(Is(Some(mark)))
        .height(Is(Some(mark)))
        .shapes(By(fn() {
          let b = back.shown(a)
          if b > 0.0 {
            traced_shapes("refresh", fn(i, pts) { sync_drawn_back(i, pts, 1.0 - b) }, mark, 0x000000FFL)
          } else {
            match icon_numbers("refresh") {
              Some(d) => icon_shapes(d, mark / 24.0, 0x000000FFL)
              None => []
            }
          }
        }))
        .tint(By(fn() { theme().p.muted }))
        .turn(By(fn() {
          match rest.get() {
            None => sync_turned(a.cycle(sync_turn_ms))
            Some(r) => {
              let s = resting.shown(a)
              if back.shown(a) == 0.0 && s < 1.0 {
                r.from + (r.to - r.from) * s
              } else {
                0.0
              }
            }
          }
        }))
        |> ignore
      })
      // the tick, drawn as a hand ticks
      m.show(fn() { drawn.shown(m) > 0.0 }, fn(a) {
        a
        .over(Is(true))
        .width(Is(Some(mark)))
        .height(Is(Some(mark)))
        .shapes(By(fn() {
          let d = drawn.shown(a)
          if d < 1.0 {
            traced_shapes("check", fn(_, pts) { [stroke_from_start(pts, d)] }, mark, 0x000000FFL)
          } else {
            match icon_numbers("check") {
              Some(n) => icon_shapes(n, mark / 24.0, 0x000000FFL)
              None => []
            }
          }
        }))
        .tint(By(fn() { theme().p.muted }))
        |> ignore
      })
    })
    |> ignore
    ignore(tip_node(tips, k, fn() { said.get() }, within=true))
  })
}
