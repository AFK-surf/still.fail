// The list catching up on what changed while away, as a node of the window's tree (sync_key's).

///|
/// sync_key as a node in `parent`: the list catching up on what changed while away, `side` across, while `syncing()`
/// says what it is (its tip and what it is read out as; None once all is here). Only once it has gone on later_ms, from
/// the moment it began (a moment's catching up shows nothing): the refresh mark (`mark` across, in the grey of what
/// says nothing of it) turning evenly, a turn each sync_turn_ms, by the clock as each frame is drawn. Once
/// all is here, from that moment: the mark goes on from where it is and as fast as it turns, slowing to rest where it
/// looks as upright (sync_rest), its arrows drawn back along their strokes, then the tick drawn as a hand ticks; there
/// sync_done_ms, then it fades (sync_out_ms). Faded in over @kit.presence_in_ms as it comes; laid nowhere, nothing of it
/// made, once it has faded out.
#callsite(autofill(loc))
pub fn sync_key_node(
  parent : @view.View,
  tips : TipLayer,
  side : Double,
  mark : Double,
  syncing : () -> String?,
  loc~ : SourceLoc,
) -> Unit {
  parent.box(made_for=loc, fn(k) {
    // (what it said last while it went on: its words once all is here)
    let said = @signals.signal(@signals.untracked(syncing).unwrap_or(""))
    // (gone on later_ms: shown; shown once: its tick at its end)
    let waited = @signals.signal(false)
    let seen = @signals.signal(false)
    // (all here: where it rests from, from when; held till its tick has stood)
    let rest : @signals.Signal[(SyncRest, Double)?] = @signals.signal(None)
    let held = @signals.signal(false)
    let fade = EdgeWay::new(0.0)
    let resting = EdgeWay::new(0.0)
    let back = EdgeWay::new(0.0)
    let ticked = EdgeWay::new(0.0)
    let off_wait : Ref[() -> Unit] = Ref(fn() {  })
    let off_held : Ref[() -> Unit] = Ref(fn() {  })
    k.reacts(fn() { syncing() is Some(_) }, fn(on) {
      let at = k.cause_at()
      (off_wait.val)()
      off_wait.val = fn() {  }
      if on {
        (off_held.val)()
        off_held.val = fn() {  }
        held.set(false)
        rest.set(None)
        resting.put(0.0)
        back.put(0.0)
        ticked.put(0.0)
        // (a time nothing waits for, as a toast's on screen: what is idle is idle while it goes on)
        off_wait.val = k.at_moment(
          at + later_ms,
          fn() {
            waited.set(true)
            seen.set(true)
          },
          later=true,
        )
      } else {
        waited.set(false)
        if @signals.untracked(fn() { seen.get() }) {
          // (from where it turns now, as fast, to rest; the arrows drawn back as it nearly is, then the tick)
          let r = sync_rest(at)
          let settle = r.ms * sync_rest_gone
          rest.set(Some((r, at)))
          held.set(true)
          resting.go_by(k, 1.0, @motion.tween_to(duration=r.ms, ease=fn(s) { r.ease(s) }))
          back.go_by(k, 1.0, @motion.tween(sync_back_ms, ease=InOut, delay=settle))
          ticked.go_by(k, 1.0, @motion.tween(sync_tick_ms, ease=Out, delay=settle + sync_back_ms * 0.6))
          off_held.val = k.at_moment(at + settle + sync_back_ms + sync_tick_ms + sync_done_ms, fn() {
            held.set(false)
            seen.set(false)
          })
        }
      }
    })
    k.reacts(syncing, fn(s) {
      match s {
        Some(words) => said.set(words)
        None => ()
      }
    })
    let shown = fn() { waited.get() || held.get() }
    // (there while it shows or fades out: nothing of it made, nothing read of the clock for it, once it has faded)
    let there = @signals.signal(false)
    let off_there : Ref[() -> Unit] = Ref(fn() {  })
    k.reacts(shown, fn(on) {
      (off_there.val)()
      off_there.val = fn() {  }
      if on {
        there.set(true)
        fade.go(k, 1.0, @kit.presence_in_ms)
      } else if @signals.untracked(fn() { there.get() }) {
        // (fading out only from where it showed: nothing waited for where it never did)
        fade.go_by(k, 0.0, @motion.tween(sync_out_ms, ease=Leave))
        off_there.val = k.at_moment(k.cause_at() + sync_out_ms, fn() { there.set(false) })
      }
    })
    k.owns(fn() {
      (off_wait.val)()
      (off_held.val)()
      (off_there.val)()
      for w in [fade, resting, back, ticked] {
        (w.due)()
      }
    })
    |> ignore
    k
    .width(Is(Some(side)))
    .height(Is(Some(side)))
    .shrink(Is(0.0))
    .radius(Is(side / 2.0))
    .lines_up(Is(Some(Middle)))
    .lies_along(Is(Middle))
    .alpha(By(fn() { dmin(1.0, fade.shown(k)) }))
    .laid_nowhere(By(fn() { !there.get() }))
    .says(By(fn() { Some(@view.said(Status, label=said.get())) }))
    |> ignore
    k.show(at_once=true, fn() { there.get() }, fn(m) {
      m.width(Is(Some(mark))).height(Is(Some(mark))) |> ignore
      // (the mark turning, brought to rest, its arrows drawn back: in its middle, turned about it)
      m.box(fn(a) {
        a
        .over(Is(true))
        .width(Is(Some(mark)))
        .height(Is(Some(mark)))
        .shapes(By(fn() {
          let gone = back.shown(a)
          if gone >= 1.0 {
            []
          } else if gone > 0.0 {
            icon_shapes(icon_traced_data("refresh", fn(i, pts) { sync_drawn_back(i, pts, 1.0 - gone) }), mark / 24.0, 0x000000FFL)
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
            Some((r, _)) => {
              let s = resting.shown(a)
              if s < 1.0 {
                r.from + (r.to - r.from) * s
              } else {
                0.0
              }
            }
          }
        }))
        |> ignore
      })
      |> ignore
      // (the tick, drawn on as a hand ticks)
      m.box(fn(c) {
        c
        .over(Is(true))
        .width(Is(Some(mark)))
        .height(Is(Some(mark)))
        .shapes(By(fn() {
          let drawn = ticked.shown(c)
          if drawn <= 0.0 {
            []
          } else if drawn < 1.0 {
            icon_shapes(icon_traced_data("check", fn(_, pts) { [stroke_from_start(pts, drawn)] }), mark / 24.0, 0x000000FFL)
          } else {
            match icon_numbers("check") {
              Some(d) => icon_shapes(d, mark / 24.0, 0x000000FFL)
              None => []
            }
          }
        }))
        .tint(By(fn() { theme().p.muted }))
        |> ignore
      })
      |> ignore
    })
    ignore(tip_node(tips, k, fn() { said.get() }, side=Bottom))
  })
  |> ignore
}

