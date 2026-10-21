// Who a press is (Compose's way: no one's as it goes down; whoever's own way it moves past the slop first). What
// scrolls or is dragged under it, innermost first, waits: a list (up and down), a pager (across), a drag area (along
// its axis), a sideways box (its own way, while it can go that way). The first of them, from the innermost out, whose
// way the finger has gone past the slop, and further than across it, takes the press from there; the others let it
// go (a drag area pressed: no tap, not ended). Whoever holds whom does not matter: a row swiped across in a list, a
// card swiped across over the list in it. A press none takes is a tap. Taken at once, as it goes down: a drag area
// that only holds (Hold: a scrim, a sheet's body), a list moving on its own (caught), or the only one there.
// (What reaches the end of its way does not hand the rest on to what lies around it: no nested scroll yet.)

///|
/// What scrolls or is dragged under (x, y), the innermost first.
fn claim_chain(c : Ctx, x : Double, y : Double) -> Array[Int] {
  let ids = c.scroll_ids
  let rects = c.scroll_rects
  let out : Array[Int] = []
  let mut k = ids.length() - 1
  while k >= 0 {
    let r = k * 4
    if x >= rects[r] &&
      x < rects[r + 2] &&
      y >= rects[r + 1] &&
      y < rects[r + 3] &&
      !out.contains(ids[k]) &&
      claim_in_shape(c, ids[k], x, y) {
      out.push(ids[k])
    }
    k = k - 1
  }
  out
}

///|
/// Whether (x, y) is within drag area `id`'s box as drawn, its rounded corners too (as a tap on it: in_round_clip); what
/// else scrolls, by its rect.
fn claim_in_shape(c : Ctx, id : Int, x : Double, y : Double) -> Bool {
  if !drags.contains(id) {
    return true
  }
  let ids = c.hit_ids
  let rects = c.hit_rects
  let mut k = ids.length() - 1
  while k >= 0 {
    if ids[k] == id {
      let r = k * 4
      return x >= rects[r] &&
        x < rects[r + 2] &&
        y >= rects[r + 1] &&
        y < rects[r + 3] &&
        in_round_clip(c.hit_clips, k, x, y)
    }
    k = k - 1
  }
  true
}

///|
/// Whether `id` waits for its way to be moved along (a list, a pager, a drag area that moves, a sideways box): else it
/// takes the press as it goes down.
fn claim_waits(c : Ctx, id : Int) -> Bool {
  match drags.get(id) {
    Some(d) => !d.axis.same(Hold)
    None => c.lists.contains(id) || pagers.contains(id) || sideways.contains(id)
  }
}

///|
/// Whether `id` takes the press, the finger moved by (dx, dy) since it went down: its way past the slop, further than
/// across (a sideways box: and it can go that way).
fn claim_takes(c : Ctx, id : Int, dx : Double, dy : Double) -> Bool {
  let slop = touch_slop()
  let past = fn(along : Double, across : Double) { along.abs() > slop && along.abs() > across.abs() }
  match drags.get(id) {
    Some(d) =>
      match d.axis {
        Hold => false
        Vertical => past(dy, dx)
        Horizontal => past(dx, dy)
        Free => (dx * dx + dy * dy).sqrt() > slop
      }
    None =>
      match sideways.get(id) {
        Some(st) => {
          let (along, across) = if st.vertical { (dy, dx) } else { (dx, dy) }
          let can = if along < 0.0 { st.x < st.max } else { st.x > 0.0 }
          past(along, across) && can
        }
        None =>
          if pagers.contains(id) {
            past(dx, dy)
          } else if c.lists.contains(id) {
            past(dy, dx)
          } else {
            false
          }
      }
  }
}

///|
/// A press going down at (x, y): what lies under it waits (`press_chain`), the innermost as `drag_scroll`; taken at
/// once when the innermost does not wait, or it is the only one there.
fn claim_down(c : Ctx, x : Double, y : Double) -> Unit {
  let chain = claim_chain(c, x, y)
  c.press_chain = chain
  c.drag_scroll = if chain.length() > 0 { chain[0] } else { 0 }
  c.claimed = chain.length() <= 1 || !claim_waits(c, chain[0])
}

///|
/// The finger moved, the press no one's yet: the first, from the innermost out, whose way it has gone, takes it (the
/// others let go). True when it is taken now or was.
fn claim_move(c : Ctx, x : Double, y : Double) -> Bool {
  if c.claimed {
    return true
  }
  let dx = x - c.press_x
  let dy = y - c.press_y
  for id in c.press_chain {
    if claim_waits(c, id) && claim_takes(c, id, dx, dy) {
      c.drag_scroll = id
      c.claimed = true
      for other in c.press_chain {
        if other != id {
          drag_cancel(other)
        }
      }
      return true
    }
  }
  // no one's yet: the drag areas pressed follow the finger still (where it is, not yet moved), so the one that takes
  // it moves from where the finger was the move before, as it would alone
  for id in c.press_chain {
    match drags.get(id) {
      Some(d) if d.down => {
        d.x = x
        d.y = y
      }
      _ => ()
    }
  }
  false
}
