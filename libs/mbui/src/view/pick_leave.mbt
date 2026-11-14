// A pick said to leave over a time (View::pick's `leave`): what it showed and what it shows now, one in the other's
// place, never both seen. The place is one node, made once, its size making its way down its column or along its row
// (View::comes) from as big as it was to as big as what it shows now; what it showed stays where and as big as it was
// over it, taking no room, fading out over `leave`, the place at least as big across as that was laid till it is gone
// (it moves and cuts nothing of it); what it shows now is seen only once that is gone and the place holds it whole,
// fading in over as long. A way to a smaller place waits for what is fading out to be gone (it cuts nothing seen), of
// no way said with it in its column: it sets out then, in the one way of what still goes there; one to a bigger sets
// out at once, what comes in waiting for it to be there. A side that makes nothing: the place closing to nothing, its
// gap with it, and laid out nowhere at rest, as a show's that is not there. Down a column as along a row (the
// coordinator of the migration, 2026-11-11: a video's capsule, its length and how far it has come one in the other's
// place, the old view's video_capsule).

///|
/// How much of a fade `x` (0 … 1 of its time) is done: eased out, fast at first, as the old view's tween's Out.
fn leave_eased(x : Double) -> Double {
  if x <= 0.0 {
    0.0
  } else if x >= 1.0 {
    1.0
  } else {
    1.0 - (1.0 - x) * (1.0 - x)
  }
}

///|
/// What a pick leaving over a time shows of one key: its fader (what `make` makes in), the moment it is first seen
/// from (-inf: seen from the start, made with what holds it), and whether `make` made nothing in it (Tree::structural).
priv struct LeaveShown {
  fader : View
  seen_from : @signals.Signal[Double]
  none : Bool
}

///|
/// View::pick with `leave` > 0 (its slot `slot`): its place made once, what each key shows made in a fader in it,
/// what went fading out over it as what comes waits to be seen (the file's head).
fn[K : Eq] View::pick_leaving(
  slot : View,
  which : () -> K,
  make : (View, K) -> Unit,
  at_once : Bool,
  leave : Double,
  loc : SourceLoc,
) -> Unit {
  let tree = slot.tree
  let place : Ref[View?] = Ref(None)
  let had : Ref[(K, LeaveShown)?] = Ref(None)
  // (when what is fading out over the place is all gone: what comes is seen no sooner)
  let gone_by = Ref(-1.0 / 0.0)
  // (how many times it changed, and faded what it showed: what a moment asked for by one change, or by one fade, finds
  // no newer one took over; and how big across the place is held while what fades is there)
  let changes = Ref(0)
  let fades = Ref(0)
  let held_across = Ref(0.0)
  // (a fader for key `k` in `p`, seen from `from`: how opaque it is drawn its fade in from then, and out as it leaves)
  let fader = fn(p : View, k : K, from : Double) -> LeaveShown {
    let seen_from = @signals.signal(from, same=fn(a, b) { a == b })
    let said = Ref(tree.said_count)
    let f = p.box(fn(f) {
      f.alpha(
        By(fn() {
          let s = seen_from.get()
          let shown = if s == -1.0 / 0.0 {
            1.0
          } else {
            let t = f.drawn_while(fn(now) { now < s + leave })
            leave_eased((t - s) / leave)
          }
          shown * (1.0 - leave_eased(f.going()))
        }),
      )
      |> ignore
      said.val = tree.said_count
      make(f, k)
    }, loc~)
    // (one that made nothing: nothing to its place, which holding nothing else is nothing to a box that takes no room
    // holding nothing, as a pick's case that made nothing is)
    { fader: f, seen_from, none: tree.structural(f, said.val) }
  }
  let stop = tree.structured(which, fn(k) {
    guard slot.alive() else { return }
    match had.val {
      Some((was, _)) if was == k => ()
      Some((_, old)) => {
        tree.work.structure = tree.work.structure + 1
        guard place.val is Some(p) && p.live() is Some(_) else { return }
        let at = tree.cause_now()
        changes.val = changes.val + 1
        let change = changes.val
        // (laid out again where it rested holding nothing: its way from nothing)
        if p.live() is Some(n) && n.flex.style.display == @flex.Display::DisplayNone {
          n.flex.style.display = @flex.Display::Flex
          tree.layout_marked_at(p.at)
        }
        // (what showed: not seen yet, let go at once (nothing seen goes); else over the place where it was, taking no
        // room, fading out over `leave` from as opaque as it is)
        if old.seen_from.untracked() > at {
          p.leave(old.fader, 0.0)
        } else {
          // (the place at least as big across as what fades was laid (its width down a column, its height along a row),
          // till it is gone: what it shows now smaller across, or nothing, neither moves it nor cuts it)
          let row = tree.along_row_at(p.at)
          let laid = tree.nodes[old.fader.at].flex
          let across = if row { laid.height } else { laid.width }
          if across == across && across > 0.0 {
            let held = if gone_by.val > at { dmax(held_across.val, across) } else { across }
            held_across.val = held
            fades.val = fades.val + 1
            let fade = fades.val
            let ps = tree.nodes[p.at].flex.style
            if row {
              ps.set_min_height(Pt(held))
            } else {
              ps.set_min_width(Pt(held))
            }
            tree.layout_marked_at(p.at)
            p.at_moment(at + leave, fn() {
              guard fades.val == fade && p.live() is Some(m) else { return }
              if row {
                m.flex.style.set_min_height(Auto)
              } else {
                m.flex.style.set_min_width(Auto)
              }
              held_across.val = 0.0
              tree.layout_marked_at(p.at)
            })
            |> ignore
          }
          // (and as big as it was laid, out of the flow: not shrunk to what it holds, a ground stretched across its place
          // or words centred in it drawn where and as big as they were till it is gone)
          let st = tree.nodes[old.fader.at].flex.style
          if laid.width == laid.width && laid.height == laid.height {
            st.set_width(Pt(laid.width))
            st.set_height(Pt(laid.height))
          }
          st.position = @flex.PositionType::Absolute
          st.set_inset_left(Pt(0.0))
          st.set_inset_top(Pt(0.0))
          tree.layout_marked_at(old.fader.at)
          p.leave(old.fader, leave)
          gone_by.val = dmax(gone_by.val, at + leave)
        }
        let waits = dmax(gone_by.val, at)
        let now = fader(p, k, waits)
        had.val = Some((k, now))
        // (holding nothing once what fades is gone and its way is over (at `ends`): laid out nowhere, no gap of its own
        // left in its column, as a show's that is not there; not where a newer change took over, or still on a way)
        let rests_nowhere = fn(ends : Double) {
          guard now.none else { return }
          p.at_moment(ends, fn() {
            guard changes.val == change && p.live() is Some(n) && !n.coming else { return }
            n.flex.style.display = @flex.Display::DisplayNone
            tree.layout_marked_at(p.at)
          })
          |> ignore
        }
        // (its place's way from as big as it is now to what it holds now: down its column, or along its row)
        let from = tree.along_now(p.at, at)
        // (to one that made nothing: closing to nothing and staying there, its padding and gap with it, as a pick's)
        let to = if now.none { 0.0 } else { 1.0 }
        let way = !at_once && tree.makes_way(p.at) && slot.comes(p, from, to, stays=now.none)
        // (it may wait for what fades: of no way said with it in its column, noted till the change is made
        // (Tree::come_group_settle))
        if way && waits > at {
          tree.pick_waits[p.at] = waits
        }
        // (at rest by then, its way none or already over: from then)
        rests_nowhere(waits)
        if way {
          @signals.after_flush(fn() {
            tree.pick_waits.remove(p.at)
            guard p.live() is Some(m) && m.coming && now.fader.alive() else { return }
            let st = m.flex.style
            guard st.come_at == at else { return }
            tree.measured_now()
            let goal = st.come_goal
            guard goal == goal && st.come_ends == st.come_ends else { return }
            if goal < from && st.come_v == 0.0 && waits > at && st.come_group is None {
              // (to a smaller place: set out once what fades out over it is gone, cutting nothing seen, as big as it was
              // till then)
              let d = waits - at
              st.come_at = st.come_at + d
              st.come_ends = st.come_ends + d
              (m.come_off)()
              m.come_off = p.at_moment(st.come_ends, fn() { come_done(tree, p, m) })
              tree.layout_marked_at(p.at)
              // (and said anew then, as a way said at that moment: in the one way of what still goes down its column
              // then, alone the same way as this)
              let held_at = st.come_at
              p.at_moment(waits, fn() {
                guard changes.val == change &&
                  p.live() is Some(n) &&
                  n.coming &&
                  n.flex.style.come_at == held_at else {
                  return
                }
                slot.comes(p, tree.along_now(p.at, waits), to, stays=now.none) |> ignore
                // (its end, its group's where it is in one: known once the change is made)
                @signals.after_flush(fn() {
                  if p.live() is Some(n) && n.coming {
                    rests_nowhere(dmax(n.flex.style.come_ends, waits))
                  }
                })
              })
              |> ignore
            } else if goal > from {
              // (to a bigger: what comes seen once the place holds it whole)
              now.seen_from.set(dmax(waits, st.come_ends))
            }
            rests_nowhere(dmax(st.come_ends, waits))
          })
        }
      }
      None => {
        tree.work.structure = tree.work.structure + 1
        let made = Ref(None)
        let p = slot.box(fn(p) { made.val = Some(fader(p, k, -1.0 / 0.0)) }, loc~)
        place.val = Some(p)
        // (made with nothing in it: laid out nowhere, as a show's that is not there)
        if made.val is Some(s) && s.none && p.live() is Some(n) {
          n.flex.style.display = @flex.Display::DisplayNone
        }
        match made.val {
          Some(s) => had.val = Some((k, s))
          None => ()
        }
      }
    }
  })
  slot.owns(stop) |> ignore
}
