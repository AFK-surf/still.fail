// A column that scrolls (View::scrolls) holding blocks by their keys, each made only while it shows:
// which show is worked out from where the
// column is scrolled to, how tall it shows and each block's height (as laid out while it showed, kept by its key as wide
// as the column was then; one never laid out counted as `est`), so a block that does not show is not made and nothing of
// it measured. As what is over what shows changes height (a block laid out again taller than it was counted, one come
// or gone over it), the column is moved with it: what shows stays where it is.

///|
/// A page's list (`s`: Scroll::list, what it holds above moved with it as it grows: Scroll::grew_above) scrolling up and
/// down in it (View::scrolls, `slop` and `bar` as there) holding the
/// blocks `keys` names, in their order, one under another from its top, nothing else: each made by `make` in a node of
/// its own as it comes to show (its room, from the column's top to its foot, met by any of it), let go as it no more
/// does, as tall in the column meanwhile as it was last laid out (`est` where it never was). How tall each that does
/// not show was is forgotten as the column is laid out at another width or all words are measured anew (what shows is
/// laid out again as it is, its height told anew). `bar_clear`: the bar's ends kept clear (View::scrolls'). `foot_room`:
/// room kept under the last block, as it is now (none of the blocks: it is never made or let go as the column scrolls,
/// so it is laid out as it changes wherever the column is). `holds`: whether a block holds what shows where it is as
/// what is over it changes (none that does not: the first after it that does; a head that stands over what comes in
/// under it, which goes on down with what shows). `follows`: while it says so, a column at its foot (made there, or
/// scrolled back to it) is kept there as what it holds grows, till it is moved off it (a chat's newest end). `centres`:
/// the block to bring to the middle of where the column shows as this comes to name it (its cause: what asks it, an
/// entry gone to), its middle there as tall as it is counted then; held there as what is over it is laid out, till the
/// column is moved otherwise (the hand, the wheel). `first_told`: told the first block that shows as that changes, the
/// column moved first for what came or changed over it (how near its top the reader has got). `reused`: of a block
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
  centres? : () -> K? = fn() { None },
  first_told? : (K) -> Unit = fn(_) {  },
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
  let tell = fn() { told.set(@signals.untracked(fn() { told.get() }) + 1) }
  // (the same, each block's own, by its key, while it is made: what its height reads, not all of them read again as
  // one is told, n for each told)
  let tall : Map[K, @signals.Signal[Double?]] = Map([])
  // (those that show now: laid out again as they are, each told anew where it comes out otherwise; the rest forgotten)
  let showing : Map[K, Bool] = Map([])
  self.reacts(fn() { (self.laid_size_told().map(fn(z) { z.0 }), self.words_redone()) }, fn(_) {
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
  // (each block's top in the column and its height, in order: as tall as it was laid out, else est; and how many times
  // they were worked out, what is read for whether they changed: not all of them compared each time the column is
  // scrolled)
  let laid_n = Ref(0)
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
  let laid_out : Array[(K, Double, Double, Bool)] = []
  let laid_grid = Ref(-1.0)
  let laid = @signals.computed(fn(_) {
    told.get() |> ignore
    laid_n.val = laid_n.val + 1
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
      b.1 + b.2
    } else {
      0.0
    }
    for i in from..<ks.length() {
      let (h, known) = laid_h[i]
      let h = rows_slot_on(h, g)
      let b = (ks[i], top, h, known)
      if i < laid_out.length() {
        laid_out[i] = b
      } else {
        laid_out.push(b)
      }
      top = top + h
    }
    laid_out
  }, same=fn(_, _) { false })
  // (the first of them whose foot is past `y`, as they go down: each foot no higher than the next one's)
  let first_past = fn(all : Array[(K, Double, Double, Bool)], y : Double) {
    let mut lo = 0
    let mut hi = all.length()
    while lo < hi {
      let mid = (lo + hi) / 2
      if all[mid].1 + all[mid].2 > y {
        hi = mid
      } else {
        lo = mid + 1
      }
    }
    lo
  }
  // (where it is scrolled to, as what it holds is drawn now)
  let at = fn() { s.drawn(self.tree) }
  // (those that show: their room met by the column's, as tall as it shows, from the first down to one not laid out yet;
  // none before it is first laid out)
  // (made at its foot where it follows it: Scroll::to_foot, there however far that comes to be)
  if @signals.untracked(follows) {
    s.to_foot()
  }
  // (the same as they were, the same: what reads them not told as the column scrolls within the same blocks)
  let window = @signals.computed(fn(_) {
    guard self.laid_size_told() is Some((_, vh)) else { return [] }
    // (to be put at its foot, how far that is not told yet: none, nothing made at its top it never shows)
    if s.at_foot() && (s.room)() is None {
      return []
    }
    let x = at()
    let out = []
    let all = laid.get()
    for i in first_past(all, x)..<all.length() {
      let b = all[i]
      if b.1 >= x + vh {
        break
      }
      if b.1 + b.2 > x {
        out.push(b.0)
        // (one never laid out shows as it is laid out, those under it only once it is: where they start is known then,
        // nothing made that turns out to be past the foot, as an old view's list lays a row and then the next)
        if !b.3 {
          break
        }
      }
    }
    out
  }, same=fn(a, b) { a == b })
  // (what shows held where it is as what is over it changes height: the first block that showed, its top as it was
  // then and where it was among them, the column moved by as far as that moved; as it is scrolled, the first that shows
  // then)
  let anchor : Ref[(K, Double, Int)?] = Ref(None)
  // (a block brought to the middle (`centres`) holding what shows instead, till the column is moved otherwise than by
  // what it does itself: where it put it last, as many times as its blocks were worked out then)
  let held : Ref[K?] = Ref(None)
  let put_x = Ref(0.0)
  let put_n = Ref(-1)
  let first_was : Ref[K?] = Ref(None)
  // (the first that shows from `i` on that holds what shows: none of them, the first that shows)
  let holding = fn(all : Array[(K, Double, Double, Bool)], i : Int) {
    let mut j = i
    while j < all.length() && !holds(all[j].0) {
      j = j + 1
    }
    if j < all.length() {
      j
    } else {
      i
    }
  }
  // (the first that shows where it is scrolled to now: what holds what shows told anew only as that changes, not each
  // time the column is scrolled within it; while a block brought to the middle holds it, where it is scrolled to)
  let first_shown = @signals.computed(fn(_) { first_past(laid.get(), at()) }, same=fn(a, b) { a == b })
  self.reacts(fn() {
    laid.get() |> ignore
    (laid_n.val, first_shown.get(), if held.val is Some(_) { at() } else { 0.0 })
  }, fn(now) {
    let (n, _, _) = now
    let x = @signals.untracked(at)
    // (moved since by the hand or the wheel, nothing over it laid out: the block brought holds it no more)
    if held.val is Some(_) && n == put_n.val && (x - dclamp(put_x.val, 0.0, s.most())).abs() > 0.5 {
      held.val = None
    }
    let all = @signals.untracked(fn() { laid.get() })
    let mut d = 0.0
    match anchor.val {
      Some((k, was, i)) => {
        // (where it was among them, else looked for: none come or gone over it, it is where it was)
        let at = if i < all.length() && all[i].0 == k {
          Some(i)
        } else {
          all.search_by(fn(b) { b.0 == k })
        }
        match at {
          Some(i) => d = all[i].1 - was
          None => ()
        }
      }
      None => ()
    }
    if d != 0.0 {
      s.grew_above(d)
    }
    put_x.val = x + d
    put_n.val = n
    // (the first that shows where it is now: none told before it is laid out, where it is put then not known)
    let f = first_past(all, x + d)
    if (s.room)() is Some(_) && f < all.length() && first_was.val != Some(all[f].0) {
      first_was.val = Some(all[f].0)
      first_told(all[f].0)
    }
    let i = match held.val {
      Some(k) =>
        match anchor.val {
          Some((a, _, i)) if a == k && i < all.length() && all[i].0 == k => i
          _ => all.search_by(fn(b) { b.0 == k }).unwrap_or(all.length())
        }
      None => {
        let i = first_past(all, x + d)
        if i < all.length() {
          holding(all, i)
        } else {
          i
        }
      }
    }
    anchor.val = if i < all.length() { Some((all[i].0, all[i].1, i)) } else { None }
  })
  // (the block `centres` names brought to the middle of where it shows, once each time it names one: as soon as it is
  // among them and the column is laid out; held there then)
  let centred : Ref[K?] = Ref(None)
  self.reacts(fn() { (centres(), keys(), self.laid_size_told().map(fn(z) { z.1 })) }, fn(now) {
    let (want, _, vh) = now
    guard want is Some(k) else {
      centred.val = None
      return
    }
    guard vh is Some(vh) && centred.val != Some(k) else { return }
    let all = @signals.untracked(fn() { laid.get() })
    guard all.search_by(fn(b) { b.0 == k }) is Some(i) else { return }
    centred.val = Some(k)
    let to = all[i].1 + all[i].2 / 2.0 - vh / 2.0
    held.val = Some(k)
    anchor.val = Some((k, all[i].1, i))
    put_x.val = to
    put_n.val = laid_n.val
    s.put(to)
  })
  // (following its foot, scrolled back to it by the hand or the wheel, at rest there: at its foot again, kept there
  // however far that comes to be as what it holds changes, till it is moved off it. At its foot as its blocks are now,
  // not only as it was last laid out: moved down for what came in over what shows (Scroll::grew_above), it is as far
  // from its foot as before, though that is not laid out yet)
  // (whether it is at its foot as it is scrolled, at rest: told as that changes, not each time the column is scrolled)
  let at_most = @signals.computed(fn(_) { at() >= s.reach() - 0.5 && s.rest_now() is None }, same=fn(a, b) { a == b })
  self.reacts(fn() { at_most.get() }, fn(foot) {
    let x = @signals.untracked(at)
    guard foot && @signals.untracked(follows) && !s.at_foot() && x >= s.most() - 0.5 && s.glides_till() is None else {
      return
    }
    let all = @signals.untracked(fn() { laid.get() })
    let foot = match all.last() {
      Some(b) => b.1 + b.2
      None => 0.0
    }
    let vh = match @signals.untracked(fn() { self.laid_size_told() }) {
      Some((_, vh)) => vh
      None => 0.0
    }
    if x >= foot + @signals.untracked(foot_room) - vh - 0.5 {
      s.to_foot()
    }
  })
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
  let was : Ref[Array[K]] = Ref([])
  self.reacts(fn() { window.get() }, fn(now) {
    let on : Map[K, Bool] = Map([])
    for k in now {
      on[k] = true
    }
    @signals.start_batch()
    for k in was.val {
      if !on.contains(k) {
        if shown.get(k) is Some(c) {
          c.set(false)
        }
      }
    }
    for k in now {
      if shown.get(k) is Some(c) {
        c.set(true)
      }
    }
    @signals.end_batch()
    was.val = now
  })
  // (a block's own as it is made in what shows it (`v`), `key` its key as it is now: as tall as what it holds,
  // whatever its slot is counted as till that is told; how tall it is told as it is laid out, kept by its key, told
  // again as it is another's)
  let block = fn(v : View, key : () -> K, made : (View) -> Unit) {
    v.shrink(Is(0.0)) |> ignore
    let k = @signals.untracked(key)
    showing[k] = true
    v.owns(fn() { showing.remove(@signals.untracked(key)) }) |> ignore
    v.reacts(fn() { (key(), v.laid_size_told()) }, fn(now) {
      match now {
        (k, Some((_, h))) if heights.get(k) != Some(h) => {
          heights[k] = h
          heights_changed.push(k)
          if tall.get(k) is Some(c) {
            c.set(Some(h))
          }
          tell()
        }
        _ => ()
      }
    })
    made(v)
  }
  let out = self.scrolls(s, slop?=slop, bar?=bar, bar_clear~, fn(held) {
    held.padding(By(fn() { (0.0, 0.0, 0.0, foot_room()) })) |> ignore
    held.each(keys, fn(k) { k }, fn(slot, item) {
      let k = @signals.untracked(fn() { item.get() })
      let cell = @signals.signal(@signals.untracked(fn() { window.get().contains(k) }), same=fn(a, b) { a == b })
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
      // (as tall as it is counted, as wide as the column: what comes to show in it laid out from it alone)
      .lays_out_alone()
      |> ignore
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
                    match all.search_by(fn(b) { @signals.untracked(fn() { b.1.get() }) == k }) {
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
          slot.show(shows, fn(v) { block(v, fn() { k }, fn(v) { make(v, k) }) })
      }
    })
  })
  // (those put by let go with the list: held by nothing, let go by nothing else)
  self.owns(spare_let_go) |> ignore
  out
}

///|
/// How many blocks of one kind a list keeps put by (View::scrolls_window's `reused`): as many as come to show at once
/// as it is scrolled, the rest let go.
let spare_most : Int = 4
