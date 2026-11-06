// A column that scrolls (View::scrolls) holding blocks by their keys, each made only while it shows (retained.md's
// lists; as an old view's list builds only the rows in view, ui's Ctx::list): which show is worked out from where the
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
/// so it is laid out as it changes wherever the column is).
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
) -> View {
  guard self.live() is Some(_) else { return self }
  // (how tall each was laid out while it showed, by its key, told as each is laid out (`told` counting each change of
  // it); forgotten as the column is laid out at another width, or as all words are measured anew (the system's size of
  // words, how the theme shapes them: Tree::words_again))
  let heights : Map[K, Double] = Map([])
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
        if tall.get(k) is Some(c) {
          c.set(None)
        }
      }
      tell()
    }
  })
  // (each block's top in the column and its height, in order: as tall as it was laid out, else est)
  let laid = @signals.computed(fn(_) {
    told.get() |> ignore
    let out : Array[(K, Double, Double, Bool)] = []
    let mut top = 0.0
    for k in keys() {
      let (h, known) = match heights.get(k) {
        Some(h) => (h, true)
        None => (est, false)
      }
      // (as tall as it is laid out in the column: on its host's pixels where it sets a page's list's rows on them,
      // Tree::rows_slot)
      let h = self.tree.rows_slot(h)
      out.push((k, top, h, known))
      top = top + h
    }
    out
  })
  // (where it is scrolled to, as what it holds is drawn now)
  let at = fn() { s.drawn(self.tree) }
  // (those that show: their room met by the column's, as tall as it shows, from the first down to one not laid out yet;
  // none before it is first laid out)
  let window = @signals.computed(fn(_) {
    guard self.laid_size_told() is Some((_, vh)) else { return [] }
    let x = at()
    let out = []
    for b in laid.get() {
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
  })
  // (what shows held where it is as what is over it changes height: the first block that showed, its top as it was
  // then, the column moved by as far as that moved; as it is scrolled, the first that shows then)
  let anchor : Ref[(K, Double)?] = Ref(None)
  self.reacts(fn() { (laid.get(), at()) }, fn(now) {
    let (all, x) = now
    let mut d = 0.0
    match anchor.val {
      Some((k, was)) =>
        match all.search_by(fn(b) { b.0 == k }) {
          Some(i) => d = all[i].1 - was
          None => ()
        }
      None => ()
    }
    if d != 0.0 {
      s.grew_above(d)
    }
    anchor.val = match all.search_by(fn(b) { b.1 + b.2 > x + d }) {
      Some(i) => Some((all[i].0, all[i].1))
      None => None
    }
  })
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
  self.scrolls(s, slop?=slop, bar?=bar, bar_clear~, fn(held) {
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
      |> ignore
      slot.show(shows, fn(v) {
        // (as tall as what it holds, whatever its slot is counted as till that is told)
        v.shrink(Is(0.0)) |> ignore
        showing[k] = true
        v.owns(fn() { showing.remove(k) }) |> ignore
        // (how tall it is told as it is laid out, kept by its key)
        v.reacts(fn() { v.laid_size_told() }, fn(z) {
          match z {
            Some((_, h)) if heights.get(k) != Some(h) => {
              heights[k] = h
              if tall.get(k) is Some(c) {
                c.set(Some(h))
              }
              tell()
            }
            _ => ()
          }
        })
        make(v, k)
      })
    })
  })
}
