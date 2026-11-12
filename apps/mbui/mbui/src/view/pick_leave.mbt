// A pick said to leave over a time (View::pick's `leave`): what it showed and what it shows now, one in the other's
// place, never both seen. The place is one node, made once, its size making its way down its column or along its row
// (View::comes) from as big as it was to as big as what it shows now; what it showed stays where it was over it, taking
// no room, fading out over `leave`; what it shows now is seen only once that is gone and the place holds it whole,
// fading in over as long. A way to a smaller place waits for what is fading out to be gone (it cuts nothing seen); one
// to a bigger sets out at once, what comes in waiting for it to be there. Down a column as along a row (the
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
/// What a pick leaving over a time shows of one key: its fader (what `make` makes in), and the moment it is first seen
/// from (-inf: seen from the start, made with what holds it).
priv struct LeaveShown {
  fader : View
  seen_from : @signals.Signal[Double]
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
  // (a fader for key `k` in `p`, seen from `from`: how opaque it is drawn its fade in from then, and out as it leaves)
  let fader = fn(p : View, k : K, from : Double) -> LeaveShown {
    let seen_from = @signals.signal(from, same=fn(a, b) { a == b })
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
      make(f, k)
    }, loc~)
    { fader: f, seen_from }
  }
  let stop = tree.structured(which, fn(k) {
    guard slot.alive() else { return }
    match had.val {
      Some((was, _)) if was == k => ()
      Some((_, old)) => {
        tree.work.structure = tree.work.structure + 1
        guard place.val is Some(p) && p.live() is Some(_) else { return }
        let at = tree.cause_now()
        // (what showed: not seen yet, let go at once (nothing seen goes); else over the place where it was, taking no
        // room, fading out over `leave` from as opaque as it is)
        if old.seen_from.untracked() > at {
          p.leave(old.fader, 0.0)
        } else {
          let st = tree.nodes[old.fader.at].flex.style
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
        // (its place's way from as big as it is now to what it holds now: down its column, or along its row)
        let from = tree.along_now(p.at, at)
        let way = !at_once && tree.makes_way(p.at) && slot.comes(p, from, 1.0)
        if way {
          @signals.after_flush(fn() {
            guard p.live() is Some(m) && m.coming && now.fader.alive() else { return }
            let st = m.flex.style
            guard st.come_at == at else { return }
            tree.measured_now()
            let goal = st.come_goal
            guard goal == goal && st.come_ends == st.come_ends else { return }
            if goal < from && st.come_v == 0.0 && waits > at && st.come_group is None {
              // (to a smaller place: set out once what fades out over it is gone, cutting nothing seen)
              let d = waits - at
              st.come_at = st.come_at + d
              st.come_ends = st.come_ends + d
              (m.come_off)()
              m.come_off = p.at_moment(st.come_ends, fn() { come_done(tree, p, m) })
              tree.layout_marked_at(p.at)
            } else if goal > from {
              // (to a bigger: what comes seen once the place holds it whole)
              now.seen_from.set(dmax(waits, st.come_ends))
            }
          })
        }
      }
      None => {
        tree.work.structure = tree.work.structure + 1
        let made = Ref(None)
        let p = slot.box(fn(p) { made.val = Some(fader(p, k, -1.0 / 0.0)) }, loc~)
        place.val = Some(p)
        match made.val {
          Some(s) => had.val = Some((k, s))
          None => ()
        }
      }
    }
  })
  slot.owns(stop) |> ignore
}
