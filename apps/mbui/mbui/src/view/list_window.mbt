// A column that scrolls (View::scrolls) holding blocks by their keys, each made only while it shows. Where it is
// scrolled to is an anchor: the first block at the top of what shows that holds it, and how far down that block's top
// the top of what shows is. As the column is laid out, in that one layout (its fill, run by View::scrolls as flex
// gives it its room), the scroll's move since is carried to the anchor, what meets where it shows is made and measured
// at the column's width (one never measured counted `est` till then), and the scroll is put back from the anchor: what
// comes, goes or is measured anew over what shows moves none of it, and nothing laid out is told afterwards to make
// things by. Moved by the hand, the wheel or a fling, the anchor is the first block seen before that still shows: one
// come in over it measured otherwise than it was counted grows up from it, what was seen staying where the move put it.
// Scrolled so that a block comes to show, the column is marked laid out again; so that one made no more shows, it is
// put by at once, nothing laid out: what is made is what shows. What shows is worked out going out from the blocks
// whose place is sure (the anchor; what was seen and still shows), up and down, one never measured as far as it goes
// that way till it is measured: a block made and still in sight is never let go for one come in over it (worked out
// from the top down by where the blocks were counted, one never measured come in at the top was all that showed till it
// was measured, every block under it let go and made again, the anchor with them: what was read jumped as far as the
// block was taller than counted, and a list opened at its foot made and let go its blocks several times over), nor for
// one come at its foot: what showed as the column began to be laid out stays made while what shows is measured, and
// what shows no more is let go once, as the last of that measuring finds what shows (a key appended at its foot, never
// measured, was all that showed for a pass: every block in sight let go and made again, its words drawn anew, for one
// row come).

///|
/// A block of a list's column as it is counted now (View::scrolls_window's `laid`, a Column's): its top in the column
/// and its height.
priv struct Laid {
  top : Double
  h : Double
}

///|
/// A page's list's blocks as they are counted (View::scrolls_window's `laid`): their keys, each one's height as it is
/// laid out (on its host's pixels where it sets a page's list's rows on them) and whether it was laid out, and the sums
/// of those heights two by two up a tree. Each sum is its two parts' as they are now, added anew whenever one of them
/// changes, none ever added to or taken from: where a block's top is (the sum of all over it, taken down the tree in
/// one order of adding) is a function of the heights as they are now and of how many there are, whatever order they
/// were measured in; on a host's pixels put on the grid's own number for the pixel it comes to, as flex puts each row's
/// top (layout_flex's rows_grid). A height told changes its leaf and the sums over it, as many as the tree is deep;
/// a top is that many additions: what is counted of 1,500 keys as one is measured no more than of 30, but for a few.
priv struct Column[K] {
  mut keys : Array[K]
  hs : Array[Double]
  knowns : Array[Bool]
  /// the tree, `cap` leaves (the heights, then 0) from `cap` on, each sum over them at half its index, the whole at 1
  mut sums : Array[Double]
  /// each top as it was last read and the count of changes it was read at (`told`): read again only once a height is
  /// told or all of it filled again since, never added up anew for each reading of it
  tops : Array[Double]
  tops_at : Array[Int]
  mut told : Int
  mut cap : Int
  mut grid : Double
  /// the leaves put since it was filled again (Column::refill) that the sums over them are to be added anew for, from
  /// and up to (Column::summed)
  mut from : Int
  mut upto : Int
}

///|
fn[K] Column::new() -> Column[K] {
  {
    keys: [],
    hs: [],
    knowns: [],
    sums: [0.0, 0.0],
    tops: [],
    tops_at: [],
    told: 0,
    cap: 1,
    grid: 0.0,
    from: 0,
    upto: 0,
  }
}

///|
fn[K] Column::length(self : Column[K]) -> Int {
  self.keys.length()
}

///|
/// Filled again for `keys` on the grid of `g` pixels a point, kept as it is up to the first place whose key is not the
/// key it held there (`whole`: from the first): that place, from which each block's height is to be put
/// (Column::put), the sums over them then added anew (Column::summed). Its shape is a function of how many blocks it
/// holds alone (a block at place i in the same leaf whatever came before), so what is kept is what a filling of all of
/// it would have come to: a key appended puts one leaf and adds the sums over it, as a height told does; a key put in
/// before the first, all of it. Whether the heights of those kept changed is told by Column::set, as ever. What it keeps
/// is written where it is, grown or cut to as many: nothing made again for each key.
fn[K : Eq] Column::refill(self : Column[K], keys : Array[K], g : Double, whole? : Bool = false) -> Int {
  let n = keys.length()
  let was = self.keys.length()
  let mut cap = 1
  while cap < n {
    cap = cap * 2
  }
  // (the first place whose key is another: compared key by key, never by the arrays' being one)
  let mut p = 0
  let same_shape = g == self.grid && cap == self.cap && self.sums.length() == 2 * cap
  if same_shape && !whole {
    let m = if n < was { n } else { was }
    while p < m && keys[p] == self.keys[p] {
      p = p + 1
    }
  }
  self.keys = keys
  self.grid = g
  // (every top kept read again: none of them read at this count)
  self.told = self.told + 1
  if self.hs.length() > n {
    self.hs.truncate(n)
    self.knowns.truncate(n)
  }
  while self.hs.length() < n {
    self.hs.push(0.0)
    self.knowns.push(false)
  }
  while self.tops.length() < n {
    self.tops.push(0.0)
    self.tops_at.push(-1)
  }
  self.cap = cap
  if same_shape {
    // (the leaves it held past as many as it holds now: none)
    for i in n..<(if was < cap { was } else { cap }) {
      self.sums[cap + i] = 0.0
    }
  } else {
    self.sums = Array::make(2 * cap, 0.0)
  }
  self.from = p
  self.upto = if was > n && same_shape { (if was < cap { was } else { cap }) } else { n }
  p
}

///|
/// Block `i`'s height as laid out on the grid and whether it was laid out, as it is filled again (Column::refill).
fn[K] Column::put(self : Column[K], i : Int, h : Double, known : Bool) -> Unit {
  self.hs[i] = h
  self.knowns[i] = known
  self.sums[self.cap + i] = h
}

///|
/// The sums over the leaves put since it was filled again (Column::put) added anew, each its two parts' as they are
/// now, from the leaves up: those over the leaves from where it was kept, no others.
fn[K] Column::summed(self : Column[K]) -> Unit {
  guard self.from < self.upto else { return }
  let sums = self.sums
  let mut lo = (self.cap + self.from) / 2
  let mut hi = (self.cap + self.upto - 1) / 2
  while lo >= 1 {
    for q in lo..=hi {
      sums[q] = sums[2 * q] + sums[2 * q + 1]
    }
    lo = lo / 2
    hi = hi / 2
  }
  self.from = 0
  self.upto = 0
}

///|
/// Block `i`'s height told: `h` as laid out on the grid, whether it was laid out; the sums over it added anew.
fn[K] Column::set(self : Column[K], i : Int, h : Double, known : Bool) -> Unit {
  self.told = self.told + 1
  self.hs[i] = h
  self.knowns[i] = known
  let mut p = self.cap + i
  self.sums[p] = h
  p = p / 2
  while p >= 1 {
    self.sums[p] = self.sums[2 * p] + self.sums[2 * p + 1]
    p = p / 2
  }
}

///|
/// Where block `i`'s top is: the sums of all over it, taken from the root down to it (the one order of adding for it),
/// on the grid's own number for its pixel where there is one.
fn[K] Column::top(self : Column[K], i : Int) -> Double {
  if self.tops_at[i] == self.told {
    return self.tops[i]
  }
  let mut acc = 0.0
  let mut node = 1
  let mut lo = 0
  let mut hi = self.cap
  while node < self.cap {
    let mid = (lo + hi) / 2
    if i < mid {
      node = 2 * node
      hi = mid
    } else {
      acc = acc + self.sums[2 * node]
      node = 2 * node + 1
      lo = mid
    }
  }
  let g = self.grid
  let t = if g > 0.0 { (acc * g + 0.5).floor() / g } else { acc }
  self.tops[i] = t
  self.tops_at[i] = self.told
  t
}

///|
/// Block `i`'s key, height as laid out, and whether it was laid out.
fn[K] Column::key(self : Column[K], i : Int) -> K {
  self.keys[i]
}

///|
fn[K] Column::h(self : Column[K], i : Int) -> Double {
  self.hs[i]
}

///|
fn[K] Column::known(self : Column[K], i : Int) -> Bool {
  self.knowns[i]
}

///|
/// Block `i` as it is counted now.
#alias("_[_]")
fn[K] Column::at(self : Column[K], i : Int) -> Laid {
  { top: self.top(i), h: self.hs[i] }
}

///|
/// The last block as it is counted now; none where there is none.
fn[K] Column::last(self : Column[K]) -> Laid? {
  if self.keys.length() == 0 {
    None
  } else {
    Some(self[self.keys.length() - 1])
  }
}

///|
/// The first block whose foot is past `y`, as they go down (each foot no higher than the next one's); as many as there
/// are where none is. Its foot is where the next one's top is (the last one's, where all of them end), so it is found
/// going down the sums once, as Column::top goes down them for one top: at each sum, the top of the first block of its
/// right half (all over it, added in the same order, on the grid's number for its pixel) past `y` or not.
fn[K] Column::first_past(self : Column[K], y : Double) -> Int {
  let n = self.keys.length()
  let g = self.grid
  let on_grid = fn(t : Double) { if g > 0.0 { (t * g + 0.5).floor() / g } else { t } }
  if n == 0 || on_grid(self.sums[1]) <= y {
    return n
  }
  let mut acc = 0.0
  let mut node = 1
  let mut lo = 0
  let mut hi = self.cap
  while node < self.cap {
    let mid = (lo + hi) / 2
    let right = acc + self.sums[2 * node]
    if on_grid(right) > y {
      node = 2 * node
      hi = mid
    } else {
      acc = right
      node = 2 * node + 1
      lo = mid
    }
  }
  if lo < n { lo } else { n }
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
/// is laid out, till the column is moved otherwise (the hand, the wheel). `near_foot`: (screens,
/// wanting, ask): `ask` done as it is scrolled to within so many of its heights of its foot while `wanting()` holds, as
/// that comes to be, and again as its keys change while it is (a page more asked of what has more): how far its foot is
/// is its own, nothing laid out read by what asks. `near_top`: the same of its top (the page before asked of what has
/// more before it), how far that is by its anchor and its blocks' tops as its keys are now; at its foot however far
/// that comes to be (`follows`), only once all it holds shows (room left over it to fill): its newest is what is read
/// there, the page before wanted as the reader heads up. `reused`: of a block
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
  near_foot? : (Double, () -> Bool, () -> Unit),
  near_top? : (Double, () -> Bool, () -> Unit),
  reused? : (K) -> Int?,
  make_reused? : (View, () -> K) -> Unit,
) -> View {
  guard self.live() is Some(_) else { return self }
  // (what asks it to show a block or its foot: the page's, else its own, which End asks its foot of at once,
  // scroll_keys.mbt)
  let place = Some(place.unwrap_or(ListPlace::new()))
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
  // (the keys they were worked out for and where each is among them; what they come to, counted (Column): made again as
  // the keys change, else only those whose height changed since told it)
  let laid_keys : Ref[Array[K]] = Ref([])
  let laid_at : Map[K, Int] = Map([])
  // (each key's number, given as it is first asked (words picked in its row: View::row_place), kept while the list
  // lives: what its row is known by, whichever node it is made in (Tree's rows_named); a key come back the same row)
  let row_numbers : Map[K, Int] = Map([])
  let row_numbered = Ref(0)
  let number_of = fn(k : K) {
    match row_numbers.get(k) {
      Some(n) => n
      None => {
        row_numbered.val = row_numbered.val + 1
        row_numbers[k] = row_numbered.val
        row_numbered.val
      }
    }
  }
  let height_of = fn(k : K) {
    match heights.get(k) {
      Some(h) => (h, true)
      None => (est, false)
    }
  }
  let column : Column[K] = Column::new()
  // (the anchor taken again where the column is scrolled to now, by its blocks as they are counted before its keys
  // change: anchor_again, below)
  let anchor_again : Ref[(Column[K]) -> Unit] = Ref(fn(_) {  })
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
    if physical_equal(ks, laid_keys.val) && g == laid_grid.val && column.length() == ks.length() {
      for k in heights_changed {
        match laid_at.get(k) {
          Some(i) => {
            let (h, known) = height_of(k)
            column.set(i, rows_slot_on(h, g), known)
          }
          None => ()
        }
      }
    } else {
      // (where what shows is held from, taken first by the blocks as they were counted till now: what comes in is put
      // in round it)
      (anchor_again.val)(column)
      laid_keys.val = ks
      // (kept as it was up to the first key that is another: from there its keys found and their heights put again; the
      // heights told of those kept told as ever)
      let was = column.keys
      let p = column.refill(ks, g)
      for i in p..<was.length() {
        if laid_at.get(was[i]) == Some(i) {
          laid_at.remove(was[i])
        }
      }
      for i in p..<ks.length() {
        let k = ks[i]
        laid_at[k] = i
        let (h, known) = height_of(k)
        column.put(i, rows_slot_on(h, g), known)
      }
      column.summed()
      for k in heights_changed {
        match laid_at.get(k) {
          Some(i) if i < p => {
            let (h, known) = height_of(k)
            column.set(i, rows_slot_on(h, g), known)
          }
          _ => ()
        }
      }
    }
    laid_grid.val = g
    heights_changed.clear()
    column
  }, same=fn(_, _) { false })
  // (the first of them whose foot is past `y`, as they go down: each foot no higher than the next one's)
  let first_past = fn(all : Column[K], y : Double) { all.first_past(y) }
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
  // (the others that showed as the anchor was last put and hold what shows, each with how far down its top the top of
  // what showed was: the anchor's stand-ins, in order, once it is no more among the keys (the row a filter leaves out;
  // an item become another), what shows held by the next of them where it was)
  let anchor_else : Array[(K, Double)] = []
  // (how many blocks it had, and its last, as it was said held where it is at its foot (Scroll::holds_here): blocks
  // come or gone since, with it still at its foot, and it follows its foot again)
  let held_with : Ref[(Int, K?)] = Ref((0, None))
  s.held_said = fn() {
    let ks = @signals.untracked(keys)
    held_with.val = (ks.length(), ks.last())
  }
  // (where the scroll was as the anchor was last put: what it moved by since, carried to the anchor)
  let anchor_x : Ref[Double?] = Ref(None)
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
  // (the anchor among the blocks as they are counted now, or the first of its stand-ins that is: where it is among them
  // and how far down its top the top of what shows was; none put yet, or none of them left, none)
  let held_at = fn(all : Column[K]) -> (Int, Double)? {
    guard anchor.val is Some((k, off)) else { return None }
    if laid_at.get(k) is Some(i) && i < all.length() {
      return Some((i, off))
    }
    for o in anchor_else {
      if laid_at.get(o.0) is Some(i) && i < all.length() {
        return Some((i, o.1))
      }
    }
    None
  }
  // (where the top of what shows is by where the blocks are counted now: the anchor's, moved as the scroll was since it
  // was put; none yet, where the scroll is. What came in or went over what shows since has moved the blocks' tops, not
  // yet the scroll (its fill puts it): by the scroll alone, what shows would be read off other blocks.)
  let top_now = fn(all : Column[K], x : Double) {
    match (held_at(all), anchor_x.val) {
      (Some((i, off)), Some(was)) => all.top(i) + off + (x - was)
      _ => x
    }
  }
  // (where the top of what shows is with the column at its foot, showing `vh` of it: by its blocks as they are counted
  // now and its foot's room, followed)
  let foot_top = fn(all : Column[K], vh : Double) {
    let blocks_h = match all.last() {
      Some(b) => b.top + b.h
      None => 0.0
    }
    dmax(0.0, blocks_h + foot_room() + s.tuck_room.get() - vh)
  }
  // (following its foot, scrolled back to it by the hand or the wheel, at rest there: at its foot again, kept there
  // however far that comes to be as what it holds grows, till it is moved off it; told as that comes to be so, not each
  // time the column is scrolled. By its own blocks and its anchor, as its near_foot is: by how far the scroll could
  // go as last laid out, a column moved in its fill for what came in or grew over what shows (Scroll::grew_above)
  // further than that was read at its foot before that layout said how far it goes now, and taken there: what was
  // read 100 off its foot gone as a block 150 taller than counted came in at its top.)
  let at_most = @signals.computed(fn(_) {
    guard s.seen.get() is Some((_, vh)) else { return false }
    let all = laid.get()
    top_now(all, at()) >= foot_top(all, vh) - 0.5 && s.rest_now() is None && s.glides_till() is None
  }, same=fn(a, b) { a == b })
  self.reacts(fn() { at_most.get() }, fn(foot) {
    if foot && @signals.untracked(follows) && !s.at_foot() {
      // (back at its foot, having left it: followed again, whatever held it where it was, Scroll::holds_here)
      s.held = false
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
  match near_top {
    Some((screens, wanting, ask)) => {
      // (how far its top is by its anchor as its keys are now, those over it not laid out yet as tall as `est`: not
      // by the scroll, which a page come in over what shows has not moved yet, so that it is not asked again for that
      // page before it is laid out)
      // (at its foot however far that comes to be: only where nothing is over what shows, by its blocks (the scroll
      // says nothing of how far down its foot is before it is laid out there, and the room it is first laid out in may
      // be taller than the one it gets: a panel whose head is measured a frame later))
      let near = @signals.computed(fn(_) {
        guard s.seen.get() is Some((_, vh)) && vh > 0.0 else { return false }
        let all = laid.get()
        let x = at()
        if s.at_foot() {
          foot_top(all, vh) <= 0.0
        } else {
          top_now(all, x) < screens * vh
        }
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
  let holding = fn(all : Column[K], i : Int) {
    let mut j = i
    while j < all.length() && !holds(all.key(j)) {
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
    // (known by its key as the row it is made for, read as its key is: taken for another key, that one's row from then;
    // where a word in it is placed, View::row_place stops at it)
    self.tree.nodes[v.at].each_row = true
    let named = (
      self.id(),
      fn() { number_of(key()) },
      fn() { laid_at.get(@signals.untracked(key)).unwrap_or(-1) },
    )
    self.tree.rows_named[v.at] = named
    let v_at = v.at
    v.owns(fn() {
      if self.tree.rows_named.get(v_at) is Some(r) && physical_equal(r.2, named.2) {
        self.tree.rows_named.remove(v_at)
      }
    })
    |> ignore
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
      s.to_foot = fn(_) {
        p.to_end(glide=false)
        true
      }
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
              Some(i) if i < all.length() => Some(all.top(i) + off)
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
    guard now != shown_now else { return }
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
  // (those that show as they were measured, or as they were counted and came out so: what was seen as it is, which
  // holds where the column is as it is moved, before one come in over it measured otherwise)
  let seen_rows : Map[K, Bool] = Map([])
  // (the anchor put where the top of what shows is `top`, `vh` of it showing, the scroll at `x` then, by the blocks as
  // they are counted now: the first that holds what shows, how far down its top the top of what shows is; what is
  // measured anew over it from now on moving none of what shows. One never measured holds nothing sure, the top of what
  // shows somewhere in a height it is only counted: the first measured that shows under it holds it instead, from over
  // its top. Held by one counted 48 and measured 218 in the next fill, what showed under it went down the 170 more with
  // it, and that fill, going out from it alone, let go of every block in sight to make them again. Those that show its
  // stand-ins.)
  let anchor_put = fn(all : Column[K], top : Double, vh : Double, x : Double) {
    anchor.val = if all.length() > 0 {
      let first = holding(all, first_past(all, top).min(all.length() - 1))
      let mut j = first
      while j < all.length() && all.top(j) < top + vh && !(all.known(j) && holds(all.key(j))) {
        j = j + 1
      }
      let j = if j < all.length() && all.top(j) < top + vh { j } else { first }
      Some((all.key(j), top - all.top(j)))
    } else {
      None
    }
    anchor_x.val = Some(x)
    anchor_else.clear()
    for k in shown_now {
      if holds(k) && laid_at.get(k) is Some(i) && i < all.length() {
        anchor_else.push((k, top - all.top(i)))
      }
    }
  }
  // Moved by the hand, the wheel, a fling or Scroll::put since its fill last put the anchor, with nothing laid out
  // since (scrolled so that only blocks counted as they are come to show, its fill does not run: what shows is shown
  // by the scroll alone, past_made below), the anchor is still the one put then, perhaps far out of sight (its foot's
  // last, the column scrolled up off its foot), the move carried as how far the scroll went since (top_now). A key come
  // in between it and what shows was counted over it, and what was read moved by as much (one put in under the top of
  // what shows, over the foot it was opened at: the column 40 further down, what was read 40 up, 2026-11-12). So as its
  // keys change, the anchor is put first where the column is now, by its blocks as they were counted till then: what
  // comes in is put in round what is read.
  anchor_again.val = fn(all) {
    guard !s.at_foot() && anchor_x.val is Some(was) && held_at(all) is Some(_) else { return }
    let x = @signals.untracked(at)
    guard (x - was).abs() > 0.000001 else { return }
    let vh = match s.seen.untracked() {
      Some((_, vh)) => vh
      None => 0.0
    }
    anchor_put(all, top_now(all, x), vh, x)
  }
  // (what is made, the stretch it covers, as `shown_now` says)
  let made_now = fn(all : Column[K]) {
    match (shown_now.get(0), shown_now.last()) {
      (Some(a), Some(b)) =>
        match (laid_at.get(a), laid_at.get(b)) {
          (Some(i), Some(j)) =>
            made.set(
              (
                if i == 0 { @double.neg_infinity } else { all.top(i) },
                all.top(i) + all.h(i),
                all.top(j),
                if j == all.length() - 1 { @double.infinity } else { all.top(j) + all.h(j) },
              ),
            )
          _ => ()
        }
      _ => made.set((@double.neg_infinity, @double.infinity, @double.neg_infinity, @double.infinity))
    }
  }
  // (which show where the column shows from `top`, `vh` tall, by where they are counted: going out from those whose
  // place is sure, `lo` to `hi` (what was seen and still shows, or the one the column is held by), up and down
  // while one meets where it shows. One never measured is as far as it goes that way till it is measured: where those
  // past it start is known only then; what is sure stays made whatever comes in over it or under it. `up_first`: the
  // first of them is sure by its top (those over it sure too, measured or not); else by its foot. None sure (`lo`
  // past `hi`): from the first that meets it down, as far as the first never measured.)
  let window = fn(all : Column[K], top : Double, vh : Double, lo : Int, hi : Int, up_first : Bool) -> Array[K] {
    let now = []
    // (showing none of it, a page under another: none made, the one it is held by neither, what it reads let go)
    if vh <= 0.0 {
      return now
    }
    if lo > hi {
      let mut i = first_past(all, top)
      while i < all.length() && all.top(i) < top + vh {
        now.push(all.key(i))
        if !all.known(i) {
          break
        }
        i = i + 1
      }
      return now
    }
    let mut a = lo
    if all.known(lo) || up_first {
      let mut i = lo - 1
      while i >= 0 && all.top(i) + all.h(i) > top {
        a = i
        if !all.known(i) {
          break
        }
        i = i - 1
      }
    }
    let mut b = hi
    if all.known(hi) {
      let mut i = hi + 1
      while i < all.length() && all.top(i) < top + vh {
        b = i
        if !all.known(i) {
          break
        }
        i = i + 1
      }
    }
    for i in a..=b {
      now.push(all.key(i))
    }
    // (past one never measured, come in among those that show: those made under it that meet where it shows as they
    // are counted kept made, not let go to be made again once it is measured; where they are is worked out then, and
    // they go only if it puts them out of sight)
    if !all.known(b) {
      let mut i = b + 1
      while i < all.length() && all.top(i) < top + vh {
        if showing.contains(all.key(i)) {
          now.push(all.key(i))
        }
        i = i + 1
      }
    }
    now
  }
  // Scrolled so that one more meets where it shows, or the first or the last made no more does, or the blocks counted
  // otherwise (come, gone, moved or measured anew), what meets it is shown at once by where the blocks are counted, the
  // rest put by: nothing laid out but the slot of each that comes, alone
  // (the slot as tall as it is counted, shown or not). Where that comes out another height than it is counted, the
  // column is laid out (Tree::alone_asks), and its fill measures it there. What is made is what shows, no more. Told
  // only as it comes to be past what is made or back, not each time the column is scrolled: a computed's same value
  // telling nothing. Past it as soon as one more meets where it shows by any of it, as the window finds what meets it
  // (`window`: a top over where it shows ends, a foot under where it starts): one meeting it by half a point or less,
  // left for the scroll to go half a point further, showed the list's ground there for a frame.
  let past_made = @signals.computed(fn(_) {
    match s.seen.get() {
      Some((_, vh)) => {
        let x = at()
        let (lo, first_end, last_top, hi) = made.get()
        x < lo || x + vh > hi || x >= first_end || x + vh <= last_top
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
    let all = laid.untracked()
    let x = top_now(all, @signals.untracked(at))
    // (what was seen and still meets where it shows is sure where it is: kept, what comes in going out from it)
    let mut lo = all.length()
    let mut hi = -1
    for k in shown_now {
      guard seen_rows.contains(k) && laid_at.get(k) is Some(i) && i < all.length() else { continue }
      if all.top(i) + all.h(i) > x && all.top(i) < x + vh {
        lo = lo.min(i)
        hi = hi.max(i)
      }
    }
    let now = window(all, x, vh, lo, hi, true)
    show_only(now)
    made_now(all)
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
    // (held where it is at its foot (Scroll::holds_here): not following it, the anchor it had holding what shows; blocks
    // come or gone since, nothing having opened: followed again)
    if s.held && s.at_foot() {
      let ks = @signals.untracked(keys)
      if held_with.val != (ks.length(), ks.last()) {
        s.held = false
      }
    }
    let mut held = s.held && s.at_foot()
    let mut follows_foot = @signals.untracked(follows) && s.at_foot() && !held
    // (the anchor as the scroll moved it since; none yet, where the scroll is)
    let start = {
      let all = laid.untracked()
      let fresh = fn() {
        let i = first_past(all, x)
        if i < all.length() {
          (i, x - all.top(i))
        } else {
          (all.length() - 1, 0.0)
        }
      }
      match (held_at(all), anchor_x.val) {
        // (held at its foot: where it was put, the scroll saying nothing of a move)
        (Some((i, off)), Some(_)) if held => (i, off)
        (Some((i, off)), Some(was)) => (i, off + (x - was))
        _ => fresh()
      }
    }
    let mut ai = start.0
    let mut aoff = start.1
    // (moved by the hand, the wheel or a fling since: the anchor taken again where it is now, by what is counted now,
    // before what comes to show is measured; not moved, the one it had, whatever came or went over it)
    match anchor_x.val {
      Some(was) if !held && (x - was).abs() > 0.000001 => {
        // (moved by the hand: held where it was no more)
        s.held = false
        let all = laid.untracked()
        if all.length() > 0 {
          let i = ai.min(all.length() - 1).max(0)
          let at_now = all.top(i) + aoff
          let j = holding(all, first_past(all, at_now).min(all.length() - 1))
          // (what was seen and still shows holding it, before one come to show: what comes in over it measured
          // otherwise than it was counted moves what was seen none, the column moved with it instead)
          let vh = match shows() {
            Some(vh) => vh
            None => 0.0
          }
          let mut seen = j
          while seen < all.length() &&
                all.top(seen) < at_now + vh &&
                !(seen_rows.contains(all.key(seen)) && holds(all.key(seen))) {
            seen = seen + 1
          }
          let j = if seen < all.length() && all.top(seen) < at_now + vh { seen } else { j }
          ai = j
          aoff = at_now - all.top(j)
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
    // (asked to show a block or its foot: held where it was no more)
    if asked {
      s.held = false
      held = false
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
    // (what showed as this layout began, kept made while it still measures: a pass that finds what shows otherwise for
    // one never measured (the appended one at its foot, as tall as `est` till it is measured, all that shows by itself)
    // lets none of it go, to make it again a pass later; what shows no more let go once, after the last pass)
    let showed = shown_now.copy()
    let mut found : Array[K] = []
    while again {
      again = false
      let all = laid.untracked()
      vh = shows().unwrap_or(0.0)
      if all.length() == 0 {
        found = []
        show_only([])
        top = 0.0
        break
      }
      // (a block brought to the middle: by its height as it is counted now, measured or not, again as it is measured)
      ai = ai.min(all.length() - 1).max(0)
      if centring {
        aoff = all.h(ai) / 2.0 - vh / 2.0
      }
      let most = dmax(0.0, whole_now() - vh)
      top = if follows_foot || to_end { most } else { dclamp(all.top(ai) + aoff, 0.0, most) }
      match from {
        Some((i, margin)) if follows_foot && i < all.length() && all.top(i) - margin < most => {
          top = dmax(0.0, all.top(i) - margin)
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
      // (what meets where it shows, made, going out from the one it is held by, or from its last at its foot: one
      // never measured as it is measured, those past it only once it is, where they start known then; none that was
      // made and still shows let go for one come in over it)
      let foot = follows_foot || to_end
      let si = if foot {
        // (at its foot, from the last measured that meets where it shows: those come under it, never measured, made
        // as it goes down to them, what showed over them kept made. Gone out from its last alone, one come at its foot
        // and not measured yet showed alone, every block in sight let go and made again once it was measured: a job's
        // output following its end made every line it showed again for each line more, 2026-11-11)
        let mut i = all.length() - 1
        let mut from = all.length() - 1
        while i >= 0 && all.top(i) + all.h(i) > top {
          if all.known(i) {
            from = i
            break
          }
          i = i - 1
        }
        from
      } else if all.top(ai) + all.h(ai) > top && all.top(ai) < top + vh {
        ai
      } else {
        first_past(all, top).min(all.length() - 1)
      }
      let now = window(all, top, vh, si, si, !foot && !centring)
      found = now
      // (most often what showed is what shows: nothing to add, nothing told)
      if now == showed {
        show_only(now)
      } else {
        let kept = now.copy()
        for k in showed {
          if laid_at.contains(k) && !kept.contains(k) {
            kept.push(k)
          }
        }
        show_only(kept)
      }
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
    // (what the last pass found, alone: what showed before and shows no more let go now, in this layout)
    show_only(found)
    let live = blocks.filter(fn(b) { b.0.alive() })
    blocks.clear()
    blocks.append(live)
    let all = laid.untracked()
    // (the anchor from now, where the scroll is put: anchor_put)
    anchor_put(all, top, vh, top)
    // (what is made, the stretch it covers)
    made_now(all)
    // (the scroll put where the anchor says: moved by as much, a fling under way with it; at its foot where it follows
    // it there, as it is)
    if held {
      // (held where it is at its foot: put there once what it holds has grown under it, its foot further down now;
      // till then at its foot as it was)
      if top < dmax(0.0, whole_now() - vh) - 0.5 {
        s.put(top)
      }
    } else if !follows_foot && (top - x).abs() > 0.000001 {
      if s.as_list && !asked {
        s.grew_above(top - x)
      } else {
        s.put(top)
      }
    }
    // (back at its foot at rest, where it follows its foot: kept there from now as what it holds grows)
    if !follows_foot &&
      !held &&
      @signals.untracked(follows) &&
      vh > 0.0 &&
      top >= dmax(0.0, whole_now() - vh) - 0.5 &&
      s.rest_now() is None &&
      s.glides_till() is None {
      s.held = false
      s.to_foot()
    }
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
      // (its key's row: where a word in it is placed, View::row_place stops at it)
      self.tree.nodes[slot_at].each_row = true
      let named = (self.id(), fn() { number_of(k) }, fn() { laid_at.get(k).unwrap_or(-1) })
      self.tree.rows_named[slot_at] = named
      slot.owns(fn() {
        if self.tree.rows_named.get(slot_at) is Some(r) && physical_equal(r.2, named.2) {
          self.tree.rows_named.remove(slot_at)
        }
      })
      |> ignore
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
                    // (a block given another key: what that makes or lets go in it so at once, key_taken.mbt)
                    key_taking_set(slot.tree, v.id())
                    key.set(k)
                    wake()
                    mine.val = Some((v, key))
                  }
                  // (in another's slot, out of sight there: moved into this one, made this one's)
                  Some((v, key, wake, was_in)) if v.alive() => {
                    was_in.park(v) |> ignore
                    slot.take_in(v)
                    showing[k] = true
                    // (a block given another key: what that makes or lets go in it so at once, key_taken.mbt)
                    key_taking_set(slot.tree, v.id())
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
