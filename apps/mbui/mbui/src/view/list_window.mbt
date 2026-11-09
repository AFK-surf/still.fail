// A column that scrolls (View::scrolls) holding blocks by their keys, each made only while it shows. Where it is
// scrolled to is an anchor: the first block at the top of what shows that holds it, and how far down that block's top
// the top of what shows is. As the column is laid out, in that one layout (its fill, run by View::scrolls as flex
// gives it its room), the scroll's move since is carried to the anchor, what meets where it shows is made and measured
// at the column's width (one never measured counted `est` till then), and the scroll is put back from the anchor: what
// comes, goes or is measured anew over what shows moves none of it, and nothing laid out is told afterwards to make
// things by. Moved by the hand, the wheel or a fling, the anchor is the first block seen before that still shows: one
// come in over it measured otherwise than it was counted grows up from it, what was seen staying where the move put it.
// Scrolled so that a block comes to show, the column is marked laid out again; so that one made no more shows, it is
// put by at once, nothing laid out: what is made is what shows.

///|
/// A block of a list's column as its tops are worked out (View::scrolls_window's `laid`): its key, its top in the
/// column, its height, and whether it was laid out (else as tall as said it would be). Written again in its place as
/// they are worked out again, none made each time.
priv struct Laid[K] {
  mut key : K
  mut top : Double
  mut h : Double
  mut known : Bool
}

///|
/// A page's list (`s`: Scroll::list, what it holds above moved with it as it grows: Scroll::grew_above) scrolling up and
/// down in it (View::scrolls, `slop` and `bar` as there) holding the
/// blocks `keys` names, in their order, one under another from its top, nothing else: each made by `make` in a node of
/// its own as it comes to show (its room, from the column's top to its foot, met by any of it), let go as it no more
/// does, as tall in the column meanwhile as it was last measured (`est` where it never was). What shows is made and
/// measured as the column is laid out, in that layout (its fill, below: made by what was measured, measured in turn,
/// none of it told after the layout). How tall each that does not show was is forgotten as the column is given another
/// width or all words are measured anew. `bar_clear`: the bar's ends kept clear (View::scrolls'). `foot_room`:
/// room kept under the last block, as it is now (none of the blocks: it is never made or let go as the column scrolls,
/// so it is laid out as it changes wherever the column is). `holds`: whether a block holds what shows where it is as
/// what is over it changes (none that does not: the first after it that does; a head that stands over what comes in
/// under it, which goes on down with what shows). `follows`: while it says so, a column at its foot (made there, or
/// scrolled back to it) is kept there as what it holds grows, till it is moved off it (a chat's newest end). `place`:
/// what asks it to show a block or its foot at a cause (ListPlace: a block brought to the middle or to its top, back
/// to its foot, its foot followed no further than a block), done as it is next laid out; held there as what is over it
/// is laid out, till the column is moved otherwise (the hand, the wheel). `first_told`: told the first block that shows as that changes, the
/// column moved first for what came or changed over it (how near its top the reader has got). `near_foot`: (screens,
/// wanting, ask): `ask` done as it is scrolled to within so many of its heights of its foot while `wanting()` holds, as
/// that comes to be, and again as its keys change while it is (a page more asked of what has more): how far its foot is
/// is its own, nothing laid out read by what asks. `reused`: of a block
/// whose key it gives a kind, what shows is made by `make_reused` with its key as it is now, and as it no more shows put
/// by, not let go: left in its slot out of sight, what it binds following nothing meanwhile (View::rests), so its going
/// draws nothing again; the next of its kind to come to show takes it (moved into that one's slot: View::park,
/// View::take_in), its key that one's then (what it binds read again for it, what changed set again): a list's rows of one make, as a RecyclerView's views, not made and let go each as
/// the list is scrolled.
pub fn[K : Hash + Eq] View::scrolls_window(
  self : View,
  s : Scroll,
  keys : () -> Array[K],
  make : (View, K) -> Unit,
  est? : Double = 80.0,
  slop? : Double,
  bar? : ScrollBar,
  bar_clear? : () -> (Double, Double) = fn() { (0.0, 0.0) },
  foot_room? : () -> Double = fn() { 0.0 },
  holds? : (K) -> Bool = fn(_) { true },
  follows? : () -> Bool = fn() { false },
  place? : ListPlace[K],
  first_told? : (K) -> Unit = fn(_) {  },
  near_foot? : (Double, () -> Bool, () -> Unit),
  reused? : (K) -> Int?,
  make_reused? : (View, () -> K) -> Unit,
) -> View {
  guard self.live() is Some(_) else { return self }
  // (its keys worked out once as what they read changes, not again as a block's height is told: what reads them, the
  // blocks' tops and the blocks made, reads these)
  let keyed = @signals.computed(fn(_) { keys() })
  let keys = fn() { keyed.get() }
  // (how tall each was laid out while it showed, by its key, told as each is laid out (`told` counting each change of
  // it); forgotten as the column is laid out at another width, or as all words are measured anew (the system's size of
  // words, how the theme shapes them: Tree::words_again))
  let heights : Map[K, Double] = Map([])
  // (those whose height changed or was forgotten since their tops were last worked out: those alone looked up again
  // then, not every key hashed each time one is told)
  let heights_changed : Array[K] = []
  let told : @signals.Signal[Int] = @signals.signal(0)
  let tell = fn() { told.set(told.untracked() + 1) }
  // (the same, each block's own, by its key, while it is made: what its height reads, not all of them read again as
  // one is told, n for each told)
  let tall : Map[K, @signals.Signal[Double?]] = Map([])
  // (those that show now: laid out again as they are, each told anew where it comes out otherwise; the rest forgotten)
  let showing : Map[K, Bool] = Map([])
  // (the blocks made, each with its key as it is now: what is measured as the column is laid out)
  let blocks : Array[(View, () -> K)] = []
  // (how wide what it holds is given to be, as it is laid out: View::scrolls' fill)
  let room_w : @signals.Signal[Double?] = @signals.signal(None, same=fn(a, b) { a == b })
  self.reacts(fn() { (room_w.get(), self.words_redone()) }, fn(_) {
    let gone = heights.keys().filter(fn(k) { !showing.contains(k) }).collect()
    if gone.length() > 0 {
      for k in gone {
        heights.remove(k)
        heights_changed.push(k)
        if tall.get(k) is Some(c) {
          c.set(None)
        }
      }
      tell()
    }
  })
  // (each block's top in the column and its height, in order: as tall as it was measured, else est)
  // (the keys they were worked out for, where each is among them, and its height and whether it was laid out: made
  // again as the keys change, else only those whose height changed since)
  let laid_keys : Ref[Array[K]] = Ref([])
  let laid_at : Map[K, Int] = Map([])
  let laid_h : Array[(Double, Bool)] = []
  let height_of = fn(k : K) {
    match heights.get(k) {
      Some(h) => (h, true)
      None => (est, false)
    }
  }
  // (what they come to, one array kept and written again from the first whose height changed down, those over it as
  // they were: told changed each time it is worked out, the same array)
  let laid_out : Array[Laid[K]] = []
  let laid_grid = Ref(-1.0)
  // (how many times they were worked out: what shows by them worked out again each time)
  let laid_rev = Ref(0)
  let laid = @signals.computed(fn(_) {
    laid_rev.val = laid_rev.val + 1
    told.get() |> ignore
    let ks = keys()
    // (as tall as each is laid out in the column: on its host's pixels where it sets a page's list's rows on them,
    // Tree::rows_slot)
    let g = self.tree.rows_grid_now()
    let mut from = 0
    if physical_equal(ks, laid_keys.val) && g == laid_grid.val && laid_out.length() == ks.length() {
      from = ks.length()
      for k in heights_changed {
        match laid_at.get(k) {
          Some(i) => {
            laid_h[i] = height_of(k)
            from = from.min(i)
          }
          None => ()
        }
      }
    } else {
      laid_keys.val = ks
      laid_at.clear()
      laid_h.clear()
      laid_out.clear()
      for i, k in ks {
        laid_at[k] = i
        laid_h.push(height_of(k))
      }
    }
    laid_grid.val = g
    heights_changed.clear()
    let mut top = if from > 0 {
      let b = laid_out[from - 1]
      b.top + b.h
    } else {
      0.0
    }
    for i in from..<ks.length() {
      let (h, known) = laid_h[i]
      let h = rows_slot_on(h, g)
      // (each written again in its place, none made but for one more than before)
      if i < laid_out.length() {
        let b = laid_out[i]
        b.key = ks[i]
        b.top = top
        b.h = h
        b.known = known
      } else {
        laid_out.push({ key: ks[i], top, h, known })
      }
      top = top + h
    }
    laid_out
  }, same=fn(_, _) { false })
  // (the first of them whose foot is past `y`, as they go down: each foot no higher than the next one's)
  let first_past = fn(all : Array[Laid[K]], y : Double) {
    let mut lo = 0
    let mut hi = all.length()
    while lo < hi {
      let mid = (lo + hi) / 2
      if all[mid].top + all[mid].h > y {
        hi = mid
      } else {
        lo = mid + 1
      }
    }
    lo
  }
  // (where it is scrolled to, as what it holds is drawn now)
  let at = fn() { s.drawn(self.tree) }
  // (made at its foot where it follows it: Scroll::to_foot, there however far that comes to be)
  if @signals.untracked(follows) {
    s.to_foot()
  }
  // Where it is scrolled to is kept as an anchor, the column's: the block at the top of what shows (the first that holds
  // what shows) and how far down its top that is. The hand, the wheel and a fling move the scroll by points, as ever;
  // as the column is laid out (its fill, below) that move is carried to the anchor, the blocks that show made and
  // measured from it, and where the scroll is put back from the anchor: what came, went or was measured anew over what
  // shows moves none of it. Nothing of this is told after the layout.
  let anchor : Ref[(K, Double)?] = Ref(None)
  // (where the scroll was as the anchor was last put: what it moved by since, carried to the anchor)
  let anchor_x : Ref[Double?] = Ref(None)
  let first_was : Ref[K?] = Ref(None)
  // (the column marked laid out again: not while it is laid out, its fill going on to what that changed itself)
  let laid_again = fn() {
    if self.tree.rooming != self.at {
      self.tree.layout_marked_at(self.at)
    }
  }
  // (what is made, as its fill left it: the top of the first, where it ends, the top of the last and where it ends; the
  // first's top none (-∞) where none is over it, the last's end none (∞) where none is under it)
  let made : @signals.Signal[(Double, Double, Double, Double)] = @signals.signal(
    (@double.neg_infinity, @double.infinity, @double.neg_infinity, @double.infinity),
    same=fn(a, b) { a == b },
  )
  // (following its foot, scrolled back to it by the hand or the wheel, at rest there: at its foot again, kept there
  // however far that comes to be as what it holds grows, till it is moved off it; told as that comes to be so, not each
  // time the column is scrolled)
  let at_most = @signals.computed(fn(_) {
    s.seen.get() is Some(_) && at() >= s.reach() - 0.5 && s.rest_now() is None && s.glides_till() is None
  }, same=fn(a, b) { a == b })
  self.reacts(fn() { at_most.get() }, fn(foot) {
    if foot && @signals.untracked(follows) && !s.at_foot() {
      s.to_foot()
    }
  })
  match near_foot {
    Some((screens, wanting, ask)) => {
      // (how far its foot is by its own blocks' tops as its keys are now, those not laid out yet as tall as `est`: not
      // the room last laid out, which a page more come in has not reached yet, so that it is not asked again for it
      // before it is laid out, nor at once again, page after page, by a source that answers as it is asked)
      let near = @signals.computed(fn(_) {
        guard s.seen.get() is Some((_, vh)) && vh > 0.0 else { return false }
        let foot = match laid.get().last() {
          Some(b) => b.top + b.h
          None => 0.0
        }
        foot + foot_room() + s.tuck_room.get() - vh - at() < screens * vh
      }, same=fn(a, b) { a == b })
      self.reacts(fn() { (near.get() && wanting(), keys().length()) }, fn(now) {
        if now.0 {
          ask()
        }
      })
    }
    None => ()
  }
  // (the first from `i` on that holds what shows: none of them, the `i`th)
  let holding = fn(all : Array[Laid[K]], i : Int) {
    let mut j = i
    while j < all.length() && !holds(all[j].key) {
      j = j + 1
    }
    if j < all.length() {
      j
    } else {
      i
    }
  }
  // (those of a kind another may take put by as they no more show (`reused`), each with what says its key now, what
  // wakes what it binds (View::rests) and the slot it is still in: so many at most of each, the rest let go; all let go
  // with the list)
  let spare : Map[Int, Array[(View, @signals.Signal[K], () -> Unit, View)]] = Map([])
  let spare_let_go = fn() {
    for _, all in spare {
      for b in all {
        b.0.let_go()
      }
      all.clear()
    }
  }
  // (whether each shows, by its key: told only to those that come to show or stop, not each block reading the window,
  // all of them run again each time the column is scrolled)
  let shown : Map[K, @signals.Signal[Bool]] = Map([])
  // (a block's own as it is made in what shows it (`v`), `key` its key as it is now: as tall as what it holds,
  // whatever its slot is counted as till that is told; how tall it is told as it is laid out, kept by its key, told
  // again as it is another's)
  let block = fn(v : View, key : () -> K, made : (View) -> Unit) {
    v.shrink(Is(0.0)) |> ignore
    let k = @signals.untracked(key)
    showing[k] = true
    v.owns(fn() { showing.remove(@signals.untracked(key)) }) |> ignore
    // (measured as it is laid out, in that layout: the column's fill, below)
    blocks.push((v, key))
    made(v)
  }
  // (how tall what it holds comes to: its blocks as they are counted, on its host's pixels, and its foot's room)
  let whole_now = fn() {
    @signals.untracked(fn() {
      let all = laid.get()
      let blocks_h = match all.last() {
        Some(b) => b.top + b.h
        None => 0.0
      }
      blocks_h + foot_room() + s.tuck_room.get()
    })
  }
  // (what is asked of it at a cause: done as the column is laid out again, or at once where it glides there)
  match place {
    Some(p) => {
      p.laid_again = laid_again
      p.glide = fn(ask) {
        let all = laid.untracked()
        let vh = match s.seen.untracked() {
          Some((_, vh)) => vh
          None => 0.0
        }
        let most = dmax(0.0, whole_now() - vh)
        let to = match ask {
          Bring(k, off) =>
            match laid_at.get(k) {
              Some(i) if i < all.length() => Some(all[i].top + off)
              _ => None
            }
          ToEnd => Some(most)
          Centre(_) => None
        }
        match to {
          // (far from there, more than two of its heights: there at once, as an old view's list's glide far)
          Some(to) if (to - @signals.untracked(at)).abs() <= glide_most * vh => {
            s.glide_to(self, self.cause_at(), dclamp(to, 0.0, most))
            true
          }
          _ => false
        }
      }
      self.owns(fn() {
        p.laid_again = fn() {  }
        p.glide = fn(_) { false }
      })
      |> ignore
    }
    None => ()
  }
  // (which show, as the fill last left them)
  let shown_now : Array[K] = []
  // (told only to those that come or go, each found among the others by looking: what shows is a screen of them, and
  // those that stay were told as they came, or made so: `shown`'s cell made by `shown_now`)
  let show_only = fn(now : Array[K]) {
    for k in shown_now {
      if !now.contains(k) && shown.get(k) is Some(c) {
        c.set(false)
      }
    }
    for k in now {
      if !shown_now.contains(k) && shown.get(k) is Some(c) {
        c.set(true)
      }
    }
    shown_now.clear()
    shown_now.append(now)
  }
  // (the first that shows from `y` down told as that changes)
  let first_now = fn(all : Array[Laid[K]], y : Double) {
    let f = first_past(all, y)
    if f < all.length() && first_was.val != Some(all[f].key) {
      first_was.val = Some(all[f].key)
      first_told(all[f].key)
    }
  }
  // (those that show as they were measured, or as they were counted and came out so: what was seen as it is, which
  // holds where the column is as it is moved, before one come in over it measured otherwise)
  let seen_rows : Map[K, Bool] = Map([])
  // (what is made, the stretch it covers, as `shown_now` says)
  let made_now = fn(all : Array[Laid[K]]) {
    match (shown_now.get(0), shown_now.last()) {
      (Some(a), Some(b)) =>
        match (laid_at.get(a), laid_at.get(b)) {
          (Some(i), Some(j)) =>
            made.set(
              (
                if i == 0 { @double.neg_infinity } else { all[i].top },
                all[i].top + all[i].h,
                all[j].top,
                if j == all.length() - 1 { @double.infinity } else { all[j].top + all[j].h },
              ),
            )
          _ => ()
        }
      _ => made.set((@double.neg_infinity, @double.infinity, @double.neg_infinity, @double.infinity))
    }
  }
  // Scrolled so that one more meets where it shows, or the first or the last made no more does, or the blocks counted
  // otherwise (come, gone, moved or measured anew), what meets it is shown at once by where the blocks are counted, the
  // rest put by: nothing laid out but the slot of each that comes, alone
  // (the slot as tall as it is counted, shown or not). Where that comes out another height than it is counted, the
  // column is laid out (Tree::alone_asks), and its fill measures it there. What is made is what shows, no more. Told
  // only as it comes to be past what is made or back, not each time the column is scrolled: a computed's same value
  // telling nothing.
  let past_made = @signals.computed(fn(_) {
    match s.seen.get() {
      Some((_, vh)) => {
        let x = at()
        let (lo, first_end, last_top, hi) = made.get()
        x < lo - 0.5 || x + vh > hi + 0.5 || x >= first_end || x + vh <= last_top
      }
      None => false
    }
  }, same=fn(a, b) { a == b })
  self.reacts(fn() {
    let out = past_made.get()
    laid.get() |> ignore
    (out, laid_rev.val)
  }, fn(now) {
    let (out, _) = now
    // (as the column is laid out: its fill shows what shows, by what it measures; never laid out yet, nothing shows)
    guard self.tree.rooming != self.at && s.seen.untracked() is Some((_, vh)) else { return }
    // (put at its foot: where that is the column's layout says, its fill making what shows there)
    if s.at_foot() {
      if out {
        laid_again()
      }
      return
    }
    let x = @signals.untracked(at)
    let all = laid.untracked()
    let now = []
    let mut i = first_past(all, x)
    while i < all.length() && all[i].top < x + vh {
      now.push(all[i].key)
      // (one never measured shows as it is laid out, those under it only once it is: where they start is known then)
      if !all[i].known {
        break
      }
      i = i + 1
    }
    show_only(now)
    made_now(all)
    first_now(all, x)
    // (those come in not seen yet: seen as they are laid out, Tree::alone_asks)
    let still = seen_rows.keys().filter(fn(k) { !now.contains(k) }).collect()
    for k in still {
      seen_rows.remove(k)
    }
  })
  // Its fill, as the column is laid out (View::scrolls' fill), in that layout: given how wide it is and how tall it
  // shows, the scroll's move since carried to the anchor (or the block `centres` names brought to the middle, or its
  // foot where it follows it there), what meets where it shows made (each by its key, in its slot) and measured at that
  // width, its height counted, the anchor kept where it was as what is over it comes out otherwise, again till what
  // shows is all measured and none of it comes out otherwise; then the scroll put where the anchor says.
  let last_h : Ref[(Double?, Double)?] = Ref(None)
  s.fill = fn(w, h, performing) {
    // (how tall it shows as last told, where this fill is told none: one again in the same layout)
    let h = match h {
      Some(_) => {
        last_h.val = h
        h
      }
      None => last_h.val
    }
    match w {
      Some(w) =>
        if performing {
          room_w.set(Some(w))
        }
      None => ()
    }
    let shows = fn() {
      match h {
        Some((Some(exact), _)) => Some(exact)
        Some((None, most)) => Some(dmin(whole_now(), most))
        None => None
      }
    }
    // (blocks made and measured as it is laid out, at the width it is laid out at: not for a room it is only measured
    // in first, which would count them at another)
    guard performing && room_w.untracked() is Some(w) else {
      self.tree.room_bindings_run()
      return
    }
    let x = @signals.untracked(at)
    let mut follows_foot = @signals.untracked(follows) && s.at_foot()
    // (the anchor as the scroll moved it since; none yet, where the scroll is)
    let start = {
      let all = laid.untracked()
      let fresh = fn() {
        let i = first_past(all, x)
        if i < all.length() {
          (i, x - all[i].top)
        } else {
          (all.length() - 1, 0.0)
        }
      }
      match (anchor.val, anchor_x.val) {
        (Some((k, off)), Some(was)) =>
          match laid_at.get(k) {
            Some(i) if i < all.length() => (i, off + (x - was))
            _ => fresh()
          }
        _ => fresh()
      }
    }
    let mut ai = start.0
    let mut aoff = start.1
    // (moved by the hand, the wheel or a fling since: the anchor taken again where it is now, by what is counted now,
    // before what comes to show is measured; not moved, the one it had, whatever came or went over it)
    match anchor_x.val {
      Some(was) if (x - was).abs() > 0.000001 => {
        let all = laid.untracked()
        if all.length() > 0 {
          let i = ai.min(all.length() - 1).max(0)
          let at_now = all[i].top + aoff
          let j = holding(all, first_past(all, at_now).min(all.length() - 1))
          // (what was seen and still shows holding it, before one come to show: what comes in over it measured
          // otherwise than it was counted moves what was seen none, the column moved with it instead)
          let vh = match shows() {
            Some(vh) => vh
            None => 0.0
          }
          let mut seen = j
          while seen < all.length() &&
                all[seen].top < at_now + vh &&
                !(seen_rows.contains(all[seen].key) && holds(all[seen].key)) {
            seen = seen + 1
          }
          let j = if seen < all.length() && all[seen].top < at_now + vh { seen } else { j }
          ai = j
          aoff = at_now - all[j].top
        }
      }
      _ => ()
    }
    // (a block asked to be brought to the middle or its top (ListPlace), once, as soon as it is among its keys: its
    // middle there as tall as it is counted; off its foot then)
    let mut centring = false
    let mut to_end = false
    // (asked: put there, what it was on by itself stopped; else moved by as much as the anchor says)
    let mut asked = false
    match place {
      Some(p) =>
        match p.asked {
          Some(ToEnd) => {
            p.asked = None
            to_end = true
            asked = true
          }
          Some(ask) => {
            let (k, off) = match ask {
              Bring(k, off) => (k, Some(off))
              Centre(k) => (k, None)
              ToEnd => panic()
            }
            match laid_at.get(k) {
              Some(i) => {
                p.asked = None
                asked = true
                ai = i
                follows_foot = false
                match off {
                  Some(off) => aoff = off
                  None => centring = true
                }
              }
              None => ()
            }
          }
          None => ()
        }
      None => ()
    }
    // (its foot followed no further than a block's top `margin` under where it shows from: held there, off its foot,
    // once it would go further, and followed no further after)
    let from = match place {
      Some(p) => p.from.bind(fn(f) { laid_at.get(f.0).map(fn(i) { (i, f.1) }) })
      None => None
    }
    let mut top = 0.0
    let mut vh = 0.0
    let mut again = true
    let measured : Map[K, Bool] = Map([])
    while again {
      again = false
      let all = laid.untracked()
      vh = shows().unwrap_or(0.0)
      if all.length() == 0 {
        show_only([])
        top = 0.0
        break
      }
      // (a block brought to the middle: by its height as it is counted now, measured or not, again as it is measured)
      ai = ai.min(all.length() - 1).max(0)
      if centring {
        aoff = all[ai].h / 2.0 - vh / 2.0
      }
      let most = dmax(0.0, whole_now() - vh)
      top = if follows_foot || to_end { most } else { dclamp(all[ai].top + aoff, 0.0, most) }
      match from {
        Some((i, margin)) if follows_foot && i < all.length() && all[i].top - margin < most => {
          top = dmax(0.0, all[i].top - margin)
          follows_foot = false
          // (held by it from now, as it is measured anew in this fill too)
          ai = i
          aoff = -margin
          asked = true
          match place {
            Some(p) => p.from = None
            None => ()
          }
        }
        _ => ()
      }
      // (what meets where it shows, made: one never measured as it is measured, those under it only once it is, where
      // they start known then, none made that comes out past where it shows)
      let now = []
      let mut i = first_past(all, top)
      while i < all.length() && all[i].top < top + vh {
        now.push(all[i].key)
        if !all[i].known {
          break
        }
        i = i + 1
      }
      show_only(now)
      self.tree.room_bindings_run()
      // (each that shows measured, once in this fill, its height counted where it came out otherwise)
      for b in blocks.filter(fn(b) { b.0.alive() }) {
        let (v, key) = b
        let k = @signals.untracked(key)
        guard showing.contains(k) && !measured.contains(k) else { continue }
        measured[k] = true
        let bh = self.tree.height_in(v.at, self.at, w)
        if heights.get(k) != Some(bh) {
          heights[k] = bh
          heights_changed.push(k)
          if tall.get(k) is Some(c) {
            c.set(Some(bh))
          }
          again = true
        }
      }
      if again {
        tell()
        self.tree.room_bindings_run()
      }
    }
    let live = blocks.filter(fn(b) { b.0.alive() })
    blocks.clear()
    blocks.append(live)
    let all = laid.untracked()
    // (the anchor from now: the first that holds what shows, how far down its top the top of what shows is; what is
    // measured anew over it from now on moving none of what shows)
    anchor.val = if all.length() > 0 {
      let j = holding(all, first_past(all, top).min(all.length() - 1))
      Some((all[j].key, top - all[j].top))
    } else {
      None
    }
    anchor_x.val = Some(top)
    // (what is made, the stretch it covers)
    made_now(all)
    // (the scroll put where the anchor says: moved by as much, a fling under way with it; at its foot where it follows
    // it there, as it is)
    if !follows_foot && (top - x).abs() > 0.000001 {
      if s.as_list && !asked {
        s.grew_above(top - x)
      } else {
        s.put(top)
      }
    }
    // (back at its foot at rest, where it follows its foot: kept there from now as what it holds grows)
    if !follows_foot &&
      @signals.untracked(follows) &&
      vh > 0.0 &&
      top >= dmax(0.0, whole_now() - vh) - 0.5 &&
      s.rest_now() is None &&
      s.glides_till() is None {
      s.to_foot()
    }
    first_now(all, top)
    seen_rows.clear()
    for k in shown_now {
      seen_rows[k] = true
    }
    self.tree.room_bindings_run()
  }
  s.whole = Some(whole_now)
  let out = self.scrolls(s, slop?=slop, bar?=bar, bar_clear~, fn(held) {
    held.padding(By(fn() { (0.0, 0.0, 0.0, foot_room() + s.tuck_room.get()) })) |> ignore
    held.each(keys, fn(k) { k }, fn(slot, item) {
      let k = item.untracked()
      let cell = @signals.signal(shown_now.contains(k), same=fn(a, b) { a == b })
      shown[k] = cell
      slot.owns(fn() { if shown.get(k) is Some(c) && physical_equal(c, cell) { shown.remove(k) } }) |> ignore
      let shows = fn() { cell.get() }
      let my_tall = @signals.signal(heights.get(k), same=fn(a, b) { a == b })
      tall[k] = my_tall
      slot.owns(fn() { if tall.get(k) is Some(c) && physical_equal(c, my_tall) { tall.remove(k) } }) |> ignore
      // (as tall as it is counted, showing or not: as what it holds was told laid out, est before; never as tall as
      // what it holds is while that is still to be laid out, the column's end gone up and back in one frame)
      slot
      .height(By(fn() {
        Some(self.tree.rows_slot(my_tall.get().unwrap_or(est)))
      }))
      .shrink(Is(0.0))
      // (as tall as it is counted, as wide as the column: what changes in what shows laid out from it alone; where that
      // comes out another height than it is counted, or what shows in it was never measured (one taken from another's
      // slot), the column laid out again, which measures it: Tree::alone_asks)
      .lays_out_alone()
      |> ignore
      let slot_at = slot.at
      self.tree.alone_asks[slot_at] = fn() {
        // (the block that shows its key)
        guard showing.contains(k) else { return false }
        match blocks.iter().find_first(fn(b) { b.0.alive() && @signals.untracked(b.1) == k }) {
          Some((v, _)) =>
            match room_w.untracked() {
              // (measured as the column's fill measures it, against how tall it is counted: as it was measured, else
              // `est`; the same, its slot as it is, nothing laid out again)
              Some(w) => {
                let h = self.tree.height_in(v.at, self.at, w)
                if h != heights.get(k).unwrap_or(est) {
                  true
                } else {
                  // (as tall as it was counted, never measured: measured now, what shows under it worked out by that)
                  if heights.get(k) is None {
                    heights[k] = h
                    heights_changed.push(k)
                    tell()
                  }
                  seen_rows[k] = true
                  false
                }
              }
              None => true
            }
          None => false
        }
      }
      slot.owns(fn() { self.tree.alone_asks.remove(slot_at) }) |> ignore
      // (one of a kind another may take: made, or taken from those of its kind put by, as it comes to show; put by as
      // it no more does, for the next of its kind to show)
      match (reused, make_reused) {
        (Some(kind_of), Some(make_by)) if kind_of(k) is Some(kind) => {
          let mine : Ref[(View, @signals.Signal[K])?] = Ref(None)
          let stop = slot.tree.structured(shows, fn(on) {
            guard slot.alive() else { return }
            match (on, mine.val) {
              (true, None) => {
                slot.tree.work.structure = slot.tree.work.structure + 1
                // (its own if it was put by (gone and come again at once, the window told twice): where it was, as it
                // was; else the last put by)
                let taken = match spare.get(kind) {
                  Some(all) if all.length() > 0 =>
                    match all.search_by(fn(b) { b.1.untracked() == k }) {
                      Some(i) => Some(all.remove(i))
                      None => all.pop()
                    }
                  _ => None
                }
                match taken {
                  // (still in this slot, out of sight: as it was, what it binds read again)
                  Some((v, key, wake, was_in)) if v.alive() && physical_equal(was_in, slot) => {
                    showing[k] = true
                    key.set(k)
                    wake()
                    mine.val = Some((v, key))
                  }
                  // (in another's slot, out of sight there: moved into this one, made this one's)
                  Some((v, key, wake, was_in)) if v.alive() => {
                    was_in.park(v) |> ignore
                    slot.take_in(v)
                    showing[k] = true
                    key.set(k)
                    wake()
                    mine.val = Some((v, key))
                  }
                  _ => {
                    let key = @signals.signal(k, same=fn(a, b) { a == b })
                    let v = slot.box(fn(v) { block(v, fn() { key.get() }, fn(v) { make_by(v, fn() { key.get() }) }) })
                    mine.val = Some((v, key))
                  }
                }
              }
              (false, Some((v, key))) => {
                slot.tree.work.structure = slot.tree.work.structure + 1
                mine.val = None
                showing.remove(k)
                let all = match spare.get(kind) {
                  Some(all) => all
                  None => {
                    let all = []
                    spare[kind] = all
                    all
                  }
                }
                // (left where it is, in its slot out of sight, what it binds at rest: nothing drawn changes as it goes,
                // so it is drawn again for nothing; moved only as the next to show takes it)
                if all.length() < spare_most && v.alive() {
                  all.push((v, key, v.rests(), slot))
                } else {
                  slot.drop(v)
                }
              }
              _ => ()
            }
          })
          // (its slot let go: what shows in it let go with it, as what it holds)
          slot.owns(fn() {
            stop()
            if mine.val is Some(_) {
              showing.remove(k)
              mine.val = None
            }
            // (what was put by in it let go with it)
            match spare.get(kind) {
              Some(all) =>
                match all.search_by(fn(b) { physical_equal(b.3, slot) }) {
                  Some(i) => all.remove(i) |> ignore
                  None => ()
                }
              None => ()
            }
          })
          |> ignore
        }
        _ =>
          // (a block made or let go as it comes to show or leaves it as the list scrolls: there at once, no way of its
          // own; what it holds makes its way in it as anywhere)
          slot.show(shows, fn(v) { block(v, fn() { k }, fn(v) { make(v, k) }) }, at_once=true)
      }
    }, at_once=true)
  })
  // (those put by let go with the list: held by nothing, let go by nothing else)
  self.owns(spare_let_go) |> ignore
  out
}

///|
/// How many blocks of one kind a list keeps put by (View::scrolls_window's `reused`): as many as come to show at once
/// as it is scrolled, the rest let go.
let spare_most : Int = 4

///|
/// Further than this many of its heights from where it is asked to go, a page's list goes there at once, not gliding
/// (an old view's list's list_glide_rows).
let glide_most : Double = 2.0

///|
/// What a page's list is asked to show at a cause (ListPlace), done as its column is next laid out: a block brought to
/// its top (`off` under it) or to the middle.
priv enum ListAsk[K] {
  Bring(K, Double)
  Centre(K)
  ToEnd
}

///|
/// What asks a page's list (View::scrolls_window's `place`) to show a block or its foot, as a press or what comes in
/// asks it (a cause, in its handler): each asked once, done as the column is next laid out (in that layout, by its
/// anchor: what is over it measured anew moves none of it), or gliding there from where it is, at that moment. One
/// asked before the block is among its keys waits for it; a later one in its place.
pub struct ListPlace[K] {
  priv mut asked : ListAsk[K]?
  /// its foot followed no further than this block's top so far under where it shows from (ListPlace::follow_from)
  priv mut from : (K, Double)?
  priv mut laid_again : () -> Unit
  priv mut glide : (ListAsk[K]) -> Bool
}

///|
/// One for a page's list, asking nothing yet.
pub fn[K] ListPlace::new() -> ListPlace[K] {
  { asked: None, from: None, laid_again: fn() {  }, glide: fn(_) { false } }
}

///|
/// Block `key` brought to the top of where the list shows (`offset` above it: its top that far over the list's, under
/// it where less than 0), as far as the list goes (Ctx::list_scroll_to's): gliding there where `glide` and it is near.
pub fn[K] ListPlace::bring(self : ListPlace[K], key : K, offset? : Double = 0.0, glide? : Bool = false) -> Unit {
  self.from = None
  if glide && (self.glide)(Bring(key, offset)) {
    self.asked = None
    return
  }
  self.asked = Some(Bring(key, offset))
  (self.laid_again)()
}

///|
/// Block `key` brought to the middle of where the list shows, its middle there as tall as it is counted then (an entry
/// gone to).
pub fn[K] ListPlace::centre(self : ListPlace[K], key : K) -> Unit {
  self.from = None
  self.asked = Some(Centre(key))
  (self.laid_again)()
}

///|
/// Back to the list's foot (Ctx::list_to_end's): gliding there where `glide` and it is near (else at once), followed
/// there from then where its list follows its foot.
pub fn[K] ListPlace::to_end(self : ListPlace[K], glide? : Bool = true) -> Unit {
  self.from = None
  self.asked = None
  if glide && (self.glide)(ToEnd) {
    return
  }
  self.asked = Some(ToEnd)
  (self.laid_again)()
}

///|
/// Its foot, where its list follows it, followed no further than block `key`'s top `margin` under the top of where it
/// shows (Ctx::list_follow_from's: a message come while it is at its foot read from its start); held there, off its
/// foot, once it would go further. None: followed all the way again.
pub fn[K] ListPlace::follow_from(self : ListPlace[K], key : K?, margin? : Double = 0.0) -> Unit {
  self.from = key.map(fn(k) { (k, margin) })
  (self.laid_again)()
}
