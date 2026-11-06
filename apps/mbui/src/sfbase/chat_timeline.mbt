// A retained chat owns its replies' declared phases. Input changes and owned
// deadlines advance them; drawing a frame only samples the ways they declared.

///|
pub fn chat_timeline(
  owner : @view.View,
  rk : String,
  rd : Reading,
  read : () -> ChatView?,
  shown : () -> Bool,
) -> () -> Unit {
  let em = emits_of(rk)
  let stop : Ref[() -> Unit] = Ref(fn() { })
  let due = Ref(@double.infinity)
  let lingering : Map[String, (Int, Double)] = {}
  let advancing = Ref(false)
  let pending = Ref(false)
  let again = Ref(false)
  owner.owns(fn() {
    (stop.val)()
    pending.val = false
  }) |> ignore
  fn advance(deadline : Bool) {
    if !owner.alive() { return }
    if advancing.val { again.val = true; return }
    if !deadline {
      if pending.val { return }
      pending.val = true
      owner.tree.after_change(fn() {
        pending.val = false
        advance(true)
      })
      return
    }
    // A declared deadline commits its phase in that very callback, before the timeline takes the next deadline.
    // Only a data/landing notification waits for its current publication or layout to finish.
    guard read() is Some(cv) else { return }
    let c = @ui.current()
    let showing = shown()
    advancing.val = true
    defer {
      advancing.val = false
      if again.val { again.val = false; advance(false) }
    }
    let now = owner.cause_at()
    if showing {
      let placed = Ref(false)
      let place = fn(k) {
        if !placed.val {
          placed.val = true
          // Only the first endpoint asks for placement. The preceding phase's row changes are published first.
          // Re-read each registration after it: layout may have mounted, replaced or released the row.
          owner.tree.laid_as_now()
        }
        emit_place_now(owner, k)
      }
      // The remaining endpoint reads use that placement without changing the clock or running another layout.
      emit_step(c, rk, em, cv.agents.map(fn(a) { a.key }), turns_of(rk), rd.landing.get(),
        place~, one_phase=true, at=now)
    }
    let keeps = emit_keeps(em)
    let gone : Array[String] = []
    let mut next = @double.infinity
    for k, l in rd.linger {
      if rd.running.contains(k) {
        gone.push(k)
      } else if keeps.contains(k) {
        lingering.remove(k) |> ignore
      } else {
        let until = match lingering.get(k) {
          Some((id, until)) if id == l.id => until
          _ => {
            let ended = emit_ended(em, k)
            let until = dmax(now, ended) + linger_ms
            lingering[k] = (l.id, until)
            until
          }
        }
        if until <= now { gone.push(k) } else { next = dmin(next, until) }
      }
    }
    for k in gone {
      rd.linger.remove(k)
      lingering.remove(k) |> ignore
    }
    if !gone.is_empty() {
      rd.linger_said.set(@signals.untracked(fn() { rd.linger_said.get() }) + 1)
    }
    if showing {
      match em.current {
        Some(t) => {
          let at = dmax(t.clock.end(), em.held_until)
          // An unknown sent row's landing is supplied by its geometry input,
          // not by polling an expired phase with another frame.
          if at > now { next = dmin(next, at) }
        }
        None => ()
      }
      for _, way in em.out_at {
        if way.end() > now { next = dmin(next, way.end()) }
      }
    }
    if next != due.val {
      (stop.val)()
      due.val = next
      if next < @double.infinity {
        stop.val = owner.at_moment(next, fn() {
          due.val = @double.infinity
          advance(true)
        })
      }
    }
  }
  fn() { advance(false) }
}
