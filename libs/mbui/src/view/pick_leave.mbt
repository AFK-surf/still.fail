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
//
// Under a page's list (in a block of View::scrolls_window whose insides join its way: Tree's list_inner) the same pick
// is one thing changing look as the list's rows are: its place's way sets out from the cause's frame in the list's one
// way (Tree::come_group_join), waiting for nothing, so what the list sets out at that moment takes what it gives back
// with what comes then; and what it showed and what it shows now are drawn as a key going and a key coming are, held by
// how far the place has gone from the one's size to the other's (row_held_at: as big as that about its start and top,
// none at half or less): never both seen, never cut, never fading over a place already closed (the coordinator of the
// migration, 2026-11-14; the user, 2026-11-09: 同一件事换样子是同一行换内容, 进和出是同一个动作的正放和倒放).

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
/// How far place `p` has gone on its way from the size it set out from to the one it goes to, 0 to 1, where it is
/// drawn (read by the clock, View::drawn_while): 1 off its way; 0 where how far it goes is not measured yet.
fn leave_held_progress(p : View) -> Double {
  guard p.live() is Some(m) && m.coming else { return 1.0 }
  let st = m.flex.style
  let ends = st.come_ends
  guard ends == ends else { return 0.0 }
  let t = p.drawn_while(fn(now) { now < ends })
  let at = if t == @double.infinity { ends } else { t }
  let from = st.come_from
  let goal = st.come_goal
  guard goal == goal else { return 0.0 }
  let x = if (goal - from).abs() < 0.5 {
    // (as big at both ends: by its time)
    if ends > st.come_at {
      (at - st.come_at) / (ends - st.come_at)
    } else {
      1.0
    }
  } else {
    // (as tall as it is laid out then, on the host's grid where it is put on it (flex's come_grid): what is drawn by it
    // as big as its room, never past it)
    let whole = st.come_whole
    if whole == whole {
      (@flex.come_tall_at(st, whole, at) - from) / (goal - from)
    } else {
      match @flex.come_state(st, at) {
        Some((h, _)) => (h - from) / (goal - from)
        None => 1.0
      }
    }
  }
  if x < 0.0 {
    0.0
  } else if x > 1.0 {
    1.0
  } else {
    x
  }
}

///|
/// Whether place `p` lies in a block of a page's list whose insides go its way (Tree's list_inner, joining): there a
/// pick leaving is held by its place's way (the file's head).
fn Tree::pick_held(self : Tree, p : View) -> Bool {
  let own = self.column_of(p.at)
  guard own >= 0 else { return false }
  let list = self.list_of(own)
  match self.list_inner.get(list) {
    Some((true, _)) => list != own
    _ => false
  }
}

///|
/// Node `v`, under a page's list (Tree::pick_held) and set on its way in or out of its place (`going`) by a show, drawn
/// as a key on its way is: as big as how far that way has gone, about its start and top, none at half or less, never
/// cut (the file's head). Its alpha and scale are this way's while it goes (at rest whole again).
fn held_on_way(v : View, going : Bool) -> Unit {
  guard v.live() is Some(n) && n.coming else { return }
  let tree = v.tree
  n.come_uncut = true
  n.look.clips = n.clips_said
  // (worked out again once the change's layout has measured where it goes)
  let told = @signals.signal(0, same=fn(a, b) { a == b })
  let share = fn() {
    told.get() |> ignore
    let p = leave_held_progress(v)
    if going {
      1.0 - p
    } else {
      p
    }
  }
  v.alpha(By(fn() { row_held_at(share()).0 })) |> ignore
  v.scale(By(fn() { row_held_at(share()).1 }), about=DrawnSide(0.0)) |> ignore
  @signals.after_flush(fn() {
    guard v.live() is Some(_) else { return }
    tree.measured_now()
    told.set(told.untracked() + 1)
  })
}

///|
/// What a pick leaving over a time shows of one key: its fader (what `make` makes in), the moment it is first seen
/// from (-inf: seen from the start, made with what holds it), and whether `make` made nothing in it (Tree::structural).
priv struct LeaveShown {
  fader : View
  seen_from : @signals.Signal[Double]
  none : Bool
  /// under a page's list: drawn by its place's way (0: as ever, by time; 1: the one shown now, coming; 2: the one that
  /// showed, going)
  held : @signals.Signal[Int]
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
  // (told as its place's way is said and as the change's layout has measured where it goes: what is drawn by that way
  // (leave_held_progress) worked out again then, its way not read by the clock till it is known)
  let way_told = @signals.signal(0, same=fn(a, b) { a == b })
  let held_progress = fn(p : View) {
    way_told.get() |> ignore
    leave_held_progress(p)
  }
  // (a fader for key `k` in `p`, seen from `from`: how opaque it is drawn its fade in from then, and out as it leaves)
  let fader = fn(p : View, k : K, from : Double) -> LeaveShown {
    let seen_from = @signals.signal(from, same=fn(a, b) { a == b })
    let held = @signals.signal(0, same=fn(a, b) { a == b })
    let said = Ref(tree.said_count)
    let f = p.box(fn(f) {
      // (under a page's list: as big as its place has gone toward it, or away from it, about its start and top)
      f.scale(
        By(fn() {
          match held.get() {
            1 => row_held_at(held_progress(p)).1
            2 => row_held_at(1.0 - held_progress(p)).1
            _ => 1.0
          }
        }),
        about=DrawnSide(0.0),
      )
      |> ignore
      f.alpha(
        By(fn() {
          match held.get() {
            1 => return row_held_at(held_progress(p)).0
            2 => return row_held_at(1.0 - held_progress(p)).0
            _ => ()
          }
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
    { fader: f, seen_from, none: tree.structural(f, said.val), held }
  }
  let stop = tree.structured(which, fn(k) {
    guard slot.alive() else { return }
    match had.val {
      Some((was, _)) if was == k => ()
      Some((_, old)) => {
        tree.work.structure = tree.work.structure + 1
        guard place.val is Some(p) && p.live() is Some(_) else { return }
        let at = tree.cause_now()
        // (under a page's list, its way not said at once: held by its place's way, waiting for nothing: the file's head)
        let in_list = !at_once && tree.pick_held(p)
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
          if in_list {
            // (drawn going as its place goes from its size, let go once that way is over at the longest)
            old.held.set(2)
            p.leave(old.fader, dmax(leave, @flex.move_most_ms))
          } else {
            p.leave(old.fader, leave)
            gone_by.val = dmax(gone_by.val, at + leave)
          }
        }
        let waits = if in_list { at } else { dmax(gone_by.val, at) }
        let now = fader(p, k, waits)
        if in_list {
          now.held.set(1)
        }
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
        if in_list {
          way_told.set(way_told.untracked() + 1)
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
            if in_list {
              way_told.set(way_told.untracked() + 1)
            }
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
            } else if goal > from && !in_list {
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
