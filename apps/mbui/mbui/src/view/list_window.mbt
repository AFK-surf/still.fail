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
  /// how many times it was filled again (Column::refill): its keys as they were while this is the same
  mut refills : Int
  /// where its first block's top is: under the list's head, as tall as that is laid out (View::scrolls_window's
  /// `head`), each top and its foot that much further down, what is found by where it is (first_past) found so
  mut start : Double
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
    refills: 0,
    start: 0.0,
  }
}

///|
/// Its first block's top put at `h` (the head's height, as it is laid out): every top read anew.
fn[K] Column::start_at(self : Column[K], h : Double) -> Unit {
  if h != self.start {
    self.start = h
    self.told = self.told + 1
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
  self.refills = self.refills + 1
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
/// Whether keys `now` are other than `was`: as many no more, or one of them another, from `from` on (where
/// Column::refill found the first that is: those before it the same).
fn[K : Eq] keys_other(was : Array[K], now : Array[K], from : Int) -> Bool {
  if was.length() != now.length() {
    return true
  }
  for i in from..<now.length() {
    if now[i] != was[i] {
      return true
    }
  }
  false
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
  // (the sums over it, as Column::top_summed takes them: written here again, not called, a top being read so often)
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
  let t = self.start + (if g > 0.0 { (acc * g + 0.5).floor() / g } else { acc })
  self.tops[i] = t
  self.tops_at[i] = self.told
  t
}

///|
/// The sums of all over block `i`, taken from the root down to it (Column::top's, not yet on the grid).
fn[K] Column::top_summed(self : Column[K], i : Int) -> Double {
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
  self.start + acc
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
/// The first block whose foot is past `y`, as they go down (each foot no higher than the next one's); as many as there
/// are where none is. Its foot is where the next one's top is (the last one's, where all of them end), so it is found
/// going down the sums once, as Column::top goes down them for one top: at each sum, the top of the first block of its
/// right half (all over it, added in the same order, on the grid's number for its pixel) past `y` or not.
fn[K] Column::first_past(self : Column[K], y : Double) -> Int {
  let y = y - self.start
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
/// A page's list's blocks where they are at a moment while some of them make their way in or out (View::scrolls_window):
/// the column as it is counted (Column: how it all ends), each top less what the ways over it have still to open (more,
/// where one closes), each block on its way as tall as its way has it then, all on the grid as flex lays them there.
/// What reads where a block is (what shows, the anchor, its foot, a block brought to its top) reads it here, the one
/// reading of it; with none on its way, the column as it is counted, to the bit.
priv struct Places[K] {
  col : Column[K]
  /// from which block on each way moves the tops, and how much less than counted it has them there
  froms : Array[Int]
  lefts : Array[Double]
  /// the blocks on their way in, each as tall as its way has it then
  own_at : Array[Int]
  own_h : Array[Double]
}

///|
/// What a list's places hold where none is on its way: shared, never added to.
let places_none_at : Array[Int] = []

///|
let places_none_h : Array[Double] = []

///|
/// How many of a page's list's last keys a change of its keys looks back over for the last that stays (the floor's,
/// list_sent_up_test): more taken at its foot at once than that, nothing held.
let floor_tail : Int = 8

///|
/// The column as it is counted: where its blocks are with none on its way, or once all of them are there.
fn[K] Places::counted(col : Column[K]) -> Places[K] {
  { col, froms: places_none_at, lefts: places_none_h, own_at: places_none_at, own_h: places_none_h }
}

///|
fn[K] Places::length(self : Places[K]) -> Int {
  self.col.length()
}

///|
fn[K] Places::key(self : Places[K], i : Int) -> K {
  self.col.key(i)
}

///|
fn[K] Places::known(self : Places[K], i : Int) -> Bool {
  self.col.known(i)
}

///|
/// Block `i`'s height: as its way has it, where it is on its way in; else as it is counted.
fn[K] Places::h(self : Places[K], i : Int) -> Double {
  for j, at in self.own_at {
    if at == i {
      return self.own_h[j]
    }
  }
  self.col.h(i)
}

///|
/// How much less than counted the ways over block `i` (or at it, one closing over it) have its top.
fn[K] Places::left_over(self : Places[K], i : Int) -> Double {
  let mut l = 0.0
  for j, f in self.froms {
    if f <= i {
      l = l + self.lefts[j]
    }
  }
  l
}

///|
/// Where block `i`'s top is: as it is counted, less what the ways over it have still to open, on the grid's own number
/// for its pixel where there is one, as flex puts a row's top.
fn[K] Places::top(self : Places[K], i : Int) -> Double {
  if self.froms.is_empty() {
    return self.col.top(i)
  }
  let l = self.left_over(i)
  if l == 0.0 {
    return self.col.top(i)
  }
  let t = self.col.top_summed(i) - l
  let g = self.col.grid
  if g > 0.0 {
    (t * g + 0.5).floor() / g
  } else {
    t
  }
}

///|
/// Where its blocks end, what is on its way at its foot with them.
fn[K] Places::foot(self : Places[K]) -> Double {
  let n = self.col.length()
  if self.froms.is_empty() {
    return if n == 0 { self.col.start } else { self.col.top(n - 1) + self.col.h(n - 1) }
  }
  let t = self.col.start + self.col.sums[1] - self.left_over(n)
  let g = self.col.grid
  if g > 0.0 {
    (t * g + 0.5).floor() / g
  } else {
    t
  }
}

///|
/// The first block whose foot is past `y`, as they go down; as many as there are where none is (Column::first_past).
fn[K] Places::first_past(self : Places[K], y : Double) -> Int {
  if self.froms.is_empty() {
    return self.col.first_past(y)
  }
  let mut lo = 0
  let mut hi = self.col.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if self.top(mid) + self.h(mid) > y {
      hi = mid
    } else {
      lo = mid + 1
    }
  }
  lo
}

///|
/// A page's list (`s`: Scroll::list, what it holds above moved with it as it grows: Scroll::grew_above) scrolling up and
/// down in it (View::scrolls, `slop` and `bar` as there) holding the
/// blocks `keys` names, in their order, one under another from its top, nothing else: each made by `make` in a node of
/// its own as it comes to show (its room, from the column's top to its foot, met by any of it), let go as it no more
/// does, as tall in the column meanwhile as it was last measured (`est` where it never was). What shows is made and
/// measured as the column is laid out, in that layout (its fill, below: made by what was measured, measured in turn,
/// none of it told after the layout). How tall each that does not show was is forgotten as the column is given another
/// width or all words are measured anew. `bar_clear`: the bar's ends kept clear (View::scrolls'). `head`: a place the
/// list holds over its keys' blocks in what scrolls, the page building into it (a chat's bar's room): never the anchor
/// nor a stand-in for it (what is read is held by the keys' blocks alone), its height, as the fill measures it in the
/// layout, where its keys start (Column's `start`: what shows by where they are, a block brought, near_top, all count
/// from there); grown or shrunk where what shows starts in it or at its very top, that stays where it is, else what is
/// read stays. `foot`: a place pinned at the foot of what shows, drawn over what scrolls (what scrolls shows behind
/// it, what is pressed on it its own), as wide as the list, the page building into it; as tall as it is laid out, the
/// fill measuring it, the room kept under the last block (nothing of the blocks: never made or let go as the column
/// scrolls), laid out as it changes wherever the column is. `holds`: whether a block holds what shows where it is as
/// what is over it changes (none that does not: the first after it that does; a head that stands over what comes in
/// under it, which goes on down with what shows). `follows`: while it says so, a column at its foot (made there, or
/// scrolled back to it) is kept there as what it holds grows, till it is moved off it (a chat's newest end).
/// `from_end`: its blocks, where they come short of what shows, at its foot, the room left over them (an old view's
/// list's `from_end`: a short chat's few messages at the foot, over the composer), what comes after them pushing up what
/// is over it; laid out so by its column alone, at least as tall as what shows, its blocks at its end, in the same
/// layout whether they come short of it, just fill it or go past it. A switch of its own, not what `follows` says
/// (the coordinator of the migration, 2026-11-12): `follows` is read again at every moment and may stop (an agent's
/// history stops following once an entry is gone to), and a short list would then be laid out anew from its top; and
/// tied to it, the two lists that follow their foot already (a job's output, that history) would come to sit at it,
/// which nobody decided. `place`:
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
///
/// What comes or goes because its keys changed (data, not a scroll) makes its way in or closes it down its column as
/// what an each makes or lets go does (View::comes: the column's one way at that moment, ComeGroup, from the change's
/// moment), its block measured in the layout that change asks for before its way is planned, so its way's end is known
/// from its start: at its foot what is over it goes up with it (where it is scrolled is how far what it holds reaches,
/// as it is laid out); scrolled off its foot, what is read stays where it is and what is under it moves. So only where it
/// is seen: a key put in over what is read, or out of sight, or one gone that showed not, is there or gone at once, as
/// is all of its first making, all of it with motion reduced, and what comes to show as it is scrolled. `comes`: asked
/// of a key that comes as it first appears among them (once, then, untracked): whether it comes (a message said just
/// now), else it is simply there (one caught up); one change may hold both. `goes`: asked of a key that showed as it
/// goes (once, then, untracked; a key no longer among them, so not one its data has still): whether it closes its way,
/// else it is simply gone. A list that says neither (`fn(_) { false }` both) is as it was before any came along its
/// way. `at_once`: its keys there and gone at once whatever `comes` and `goes` say, and what its blocks hold going its
/// own way down each block, as a column's, joined to nothing of the list's (below): a list as it was before either
/// (the lists the app ships, till each is switched on with before and after shown: detlint's list-comes-off).
/// What a block holds that comes or goes down a column in it (a show, a pick, an each) makes its way in the list's one
/// way, the group of its held column (Tree::come_group_join): a row come or gone at that moment, another block's
/// inside, all of it one way. So too what changes in a box of a said height in a block, which moves nothing of the
/// list: known and taken. Its counts are how it all ends; where a
/// block is while a way goes is read through Places alone, at the moment it is read (as it is laid out, where flex has
/// each way then), and what shows is made from where it showed as the way set out to where it ends, those that show
/// no more at its end let go then.
pub fn[K : Hash + Eq] View::scrolls_window(
  self : View,
  s : Scroll,
  keys : () -> Array[K],
  make : (View, K) -> Unit,
  est? : Double = 80.0,
  slop? : Double,
  bar? : ScrollBar,
  bar_clear? : () -> (Double, Double) = fn() { (0.0, 0.0) },
  holds? : (K) -> Bool = fn(_) { true },
  follows? : () -> Bool = fn() { false },
  from_end? : Bool = false,
  comes? : (K) -> Bool = fn(_) { true },
  goes? : (K) -> Bool = fn(_) { true },
  leaves_room? : (K) -> Bool = fn(_) { false },
  at_once? : Bool = false,
  place? : ListPlace[K],
  near_foot? : (Double, () -> Bool, () -> Unit),
  near_top? : (Double, () -> Bool, () -> Unit),
  reused? : (K) -> Int?,
  make_reused? : (View, () -> K) -> Unit,
  head? : (View) -> Unit,
  foot? : (View) -> Unit,
) -> View {
  guard self.live() is Some(_) else { return self }
  // (its head and its foot, once made, and how tall the foot is as its fill last measured it: the room kept under its
  // last block)
  let head_v : Ref[View?] = Ref(None)
  // (how tall the head is laid out: what the page builds in it measured, on its host's pixels where it sets a page's
  // list's rows on them (rows_slot_on, as a block's slot is), the one reading of where its keys start: so every top,
  // the foot and first_past, each counting from it and on the grid by it, round alike, and the first row's top meets
  // the head's foot)
  let head_tall : @signals.Signal[Double] = @signals.signal(0.0, same=fn(a, b) { a == b })
  let foot_v : Ref[View?] = Ref(None)
  let foot_h : @signals.Signal[Double] = @signals.signal(0.0, same=fn(a, b) { a == b })
  let room_under = fn() { foot_h.get() }
  // (what asks it to show a block or its foot: the page's, else its own, which End asks its foot of at once,
  // scroll_keys.mbt)
  let place = Some(place.unwrap_or(ListPlace::new()))
  // (its keys worked out once as what they read changes, not again as a block's height is told: what reads them, the
  // blocks' tops and the blocks made, reads these)
  // (a key its page says goes leaving its room (`leaves_room`, asked once as it goes), the last among them as it goes
  // and the list at its foot: kept among the keys it lays out while what it showed fades out where it is, its slot as
  // tall as it is, its way in going on to its end (`fading`: the key, the moment it went); then let go at once, the
  // room under the last block taking its height in that change (foot_room). One that comes at its foot meanwhile ends
  // it at once, in its place from then, the key let go at once with its room left (`gone_quiet`: whether that room is
  // counted already), never both seen; the key back, its fade undone. `fade_go`, `fade_undo`: what sets its fade on
  // its block, or takes it off, once the change is told)
  // (what is sent takes it up only (list_sent_up_test): at its foot, a key come at its foot by a change, the stretch
  // from the top of the last key there before that stays to the column's end never shorter than it was at that change's
  // moment while that change's ways go, the room under the last block what keeps it so, never less than none; then the
  // room as it came to, going as it is scrolled off. What it counts as given back: the room there, the pinned foot's
  // shrink, a part closing in that key or under it, a key said to leave its room; what changes over that key's top is
  // not its (it moves that key as ever). Never a key its page lets go, not said to leave its room, gone at or under that
  // key (making its way, or at once: `goes` false, an `at_once` list): such a change is as ever, whole, not armed by it
  // and ending one armed (what is over it comes back with it, list_rows_come_test's, list_blocks_way_test's). Where no
  // key stays, nothing is held.
  // `floor`: that key and how long the stretch was then, armed; `laid_whole`, `laid_last`: how tall the column was as
  // its fill last left it and where its blocks were then; `laid_stretch`: the stretch held as that fill left it;
  // `floor_arm`: armed by the change that brings such a key, again from the column as it shows by a second while armed;
  // `floor_end`: ended, by such a change or by the hand taking it off its foot. A key said to leave its room going while
  // armed raises it to the stretch as it shows (its room counted). What is pressed and held holds the room itself
  // meanwhile, the floor armed under it as it was)
  let floor : Ref[(K, Double)?] = Ref(None)
  let laid_whole = Ref(0.0)
  let laid_last : Ref[Places[K]?] = Ref(None)
  let laid_stretch = Ref(0.0)
  let floor_arm : Ref[(K, Double) -> Unit] = Ref(fn(_, _) {  })
  let floor_end : Ref[() -> Unit] = Ref(fn() {  })
  let floor_raise = fn() {
    if floor.val is Some((k, e)) {
      floor.val = Some((k, dmax(e, laid_stretch.val)))
    }
  }
  let fading : Ref[(K, Double)?] = Ref(None)
  let fade_rev : @signals.Signal[Int] = @signals.signal(0)
  let fade_go : Ref[(K) -> Unit] = Ref(fn(_) {  })
  let fade_undo : Ref[(K) -> Unit] = Ref(fn(_) {  })
  let gone_quiet : Map[K, Bool] = Map([])
  let page_was : Ref[Array[K]] = Ref([])
  let keyed = @signals.computed(fn(_) {
    fade_rev.get() |> ignore
    let ks = keys()
    let was = page_was.val
    page_was.val = ks
    guard !physical_equal(ks, was) || fading.val is Some(_) else { return ks }
    // (one come at its foot: not among them before; asked only of one fading or gone leaving its room)
    let came_at_foot = fn() {
      ks.length() > 0 && !physical_equal(ks, was) && !was.contains(ks[ks.length() - 1])
    }
    match fading.val {
      Some((k, _)) if ks.contains(k) => {
        fading.val = None
        @signals.after_flush(fn() { (fade_undo.val)(k) })
      }
      Some((k, _)) if came_at_foot() => {
        fading.val = None
        gone_quiet[k] = false
      }
      _ => ()
    }
    // (the last gone, said to leave its room, at its foot, as laid out once: fading, or gone at once where one came in
    // its place)
    if fading.val is None && !at_once && was.length() > 0 && !physical_equal(ks, was) {
      let k = was[was.length() - 1]
      if @signals.untracked(fn() { s.seen.get() is Some(_) && s.at_foot() && leaves_room(k) }) && !ks.contains(k) {
        // (one come in its place, or motion reduced: gone at once, its room left)
        if came_at_foot() || @signals.untracked(self.tree.motion_reduced) {
          gone_quiet[k] = false
        } else {
          fading.val = Some((k, self.tree.cause_now()))
          @signals.after_flush(fn() { (fade_go.val)(k) })
        }
      }
    }
    match fading.val {
      Some((k, _)) => {
        let all = ks.copy()
        all.push(k)
        all
      }
      None => ks
    }
  })
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
  // (each that shows, where it is among them, and how far under the top of what shows its top is, by its blocks as they
  // are counted before its keys change: seen_before, below)
  let seen_before : Ref[(Column[K]) -> Array[(K, Int, Double)]] = Ref(fn(_) { [] })
  // (the keys come among them by the last change of its keys (not moved among them) that its page says come, and those
  // gone that showed then that it says go, each as far under the top of what showed as it was and the key it stood
  // over (none: at their foot): what of them comes or goes making its way, way_of below; told the fill, forgotten)
  // (each its own map, made anew where it held any: one let go of, not cleared, so what a first making of 1,500 grew
  // is not walked again at every fill)
  let came_by_data : Ref[Map[K, Bool]] = Ref(Map([]))
  let gone_from : Ref[Map[K, (Double, K?)]] = Ref(Map([]))
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
      // (where each that showed was as it was read till now, against the top of what showed, and where it was among
      // them: what of them goes closes its way only where it showed, under what was read)
      let showed_at = if at_once { [] } else { (seen_before.val)(column) }
      laid_keys.val = ks
      // (kept as it was up to the first key that is another: from there its keys found and their heights put again; the
      // heights told of those kept told as ever)
      let was = column.keys
      // (where the last keys there before were as its fill last left them (a few, from its end): what the floor holds from)
      let tail_tops : Array[(Int, Double)] = []
      match laid_last.val {
        Some(lp) if physical_equal(lp.col, column) && lp.length() == was.length() => {
          let mut j = was.length() - 1
          while j >= 0 && was.length() - j <= floor_tail {
            tail_tops.push((j, lp.top(j)))
            j = j - 1
          }
        }
        _ => ()
      }
      let p = column.refill(ks, g)
      // (its keys changed by data, one of them another or as many no more: what its bar's thumb shows changes with them,
      // in the frame that takes them; the same keys given again as another array are no change)
      if keys_other(was, ks, p) {
        s.keys_changed()
      }
      let laid_once = @signals.untracked(fn() { s.seen.get() is Some(_) })
      if came_by_data.val.length() > 0 {
        came_by_data.val = Map([])
      }
      for i in p..<ks.length() {
        let k = ks[i]
        // (come by this change: not among them before (one moved among them still is, at where it was); its page asked
        // once, now, whether it comes. Not before it was first laid out: what it is made with is there at once)
        if laid_once && !at_once && !laid_at.contains(k) && @signals.untracked(fn() { comes(k) }) {
          came_by_data.val[k] = true
        }
        laid_at[k] = i
        let (h, known) = height_of(k)
        column.put(i, rows_slot_on(h, g), known)
      }
      // (those that were from there on and are no more where they were: gone, unless put again elsewhere just now)
      for i in p..<was.length() {
        let k = was[i]
        if laid_at.get(k) == Some(i) && !(i < ks.length() && ks[i] == k) {
          laid_at.remove(k)
        }
      }
      column.summed()
      // (those that showed and are gone, each over the first after it still among them (none: at their foot), as far
      // under the top of what showed as it was)
      if gone_from.val.length() > 0 {
        gone_from.val = Map([])
      }
      for e in showed_at {
        let (k, j, off) = e
        guard !at_once &&
          !laid_at.contains(k) &&
          !gone_quiet.contains(k) &&
          @signals.untracked(fn() { goes(k) }) else {
          continue
        }
        let mut b = j + 1
        while b < was.length() && !laid_at.contains(was[b]) {
          b = b + 1
        }
        gone_from.val[k] = (off, if b < was.length() { Some(was[b]) } else { None })
      }
      // (one come at its foot by this change, seen, at its foot: the stretch from the last key there before that stays held
      // as long as it was; not where a key its page lets go, not said to leave its room, is gone at or under that one,
      // which ends one armed)
      if @signals.untracked(fn() { s.at_foot() }) {
        let mut j = was.length() - 1
        let mut let_go = false
        while j >= 0 && !laid_at.contains(was[j]) {
          if !@signals.untracked(fn() { leaves_room(was[j]) }) {
            let_go = true
          }
          j = j - 1
        }
        if let_go {
          (floor_end.val)()
        } else if j >= 0 && ks.length() > 0 && came_by_data.val.contains(ks[ks.length() - 1]) {
          match tail_tops.search_by(fn(t) { t.0 == j }) {
            Some(i) => (floor_arm.val)(was[j], laid_whole.val - tail_tops[i].1)
            None => ()
          }
        }
      }
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
  // (the rows made or let go by a change of its keys that make their way in or out (View::scrolls_window's way_of),
  // each with its key and, going, the key it stands over among them (none: at their foot), till the end its way
  // declares (ways_due, below); and what ends that wait)
  let ways : Array[(View, K, K?)] = []
  let ways_off : Ref[() -> Unit] = Ref(fn() {  })
  // Where its blocks are now (Places): as they are counted, less what the ways over each have still to open, at the
  // moment each way is laid out at as the column is laid out (its room's, the one flex lays it out at), else at the
  // logic's moment (an input, a change). With none on its way, the column as it is counted.
  // (the column as counted, made once: what is read where none is on its way, nothing made for each reading)
  let plain = Places::counted(column)
  let counted = fn(all : Column[K]) { if physical_equal(all, column) { plain } else { Places::counted(all) } }
  let places = fn(all : Column[K]) -> Places[K] {
    if ways.is_empty() {
      return counted(all)
    }
    // (those let go: no more; one past its end is where it ends, its way's own at any moment after it)
    let live = ways.filter(fn(w) { w.0.live() is Some(_) })
    if live.length() != ways.length() {
      ways.clear()
      ways.append(live)
      if ways.is_empty() {
        return counted(all)
      }
    }
    let n = all.length()
    let g = all.grid
    let laying = self.tree.rooming == self.at
    let t = self.tree.logic_said()
    let froms = []
    let lefts = []
    let own_at = []
    let own_h = []
    for w in ways {
      guard w.0.live() is Some(m) else { continue }
      let st = m.flex.style
      let at = if laying && st.come_now == st.come_now { st.come_now } else { t }
      if st.come_to >= 1.0 {
        // (coming: as tall as its way has it, those under it as much higher than counted as it has still to open)
        match laid_at.get(w.1) {
          Some(i) if i < n => {
            let h = all.h(i)
            let now = rows_slot_on(@flex.come_tall_at(st, h, at), g)
            froms.push(i + 1)
            lefts.push(h - now)
            own_at.push(i)
            own_h.push(now)
          }
          _ => ()
        }
      } else {
        // (going: those from the one it stood over on as much lower than counted as it is still tall)
        let i = match w.2 {
          Some(b) =>
            match laid_at.get(b) {
              Some(i) if i < n => i
              _ => n
            }
          None => n
        }
        froms.push(i)
        lefts.push(-rows_slot_on(@flex.come_tall_at(st, 0.0, at), g))
      }
    }
    { col: all, froms, lefts, own_at, own_h }
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
  // (held where it is at its foot while a field in one of its rows has the focus (Tree::row_focus_holds; the
  // coordinator of the migration's ruling, 2026-11-13), as by Scroll::holds_here, but not let go by blocks coming:
  // let go by the focus leaving its rows, which moves nothing (still at its foot, it follows it from the next block on;
  // put off it by what came under meanwhile, it is off it as one read up), or by the hand bringing it to its foot, or
  // the page asking its end (`row_let`: the focus's coming into a row it was so let go of, held again only as the focus
  // next comes into one). `row_hand_moved`: the hand moved it while so held: brought back to its foot, let go; brought
  // back to it otherwise (what came under it taken away again, the room grown), put at its foot and held from there.
  // Its pinned foot grown is counted as what it holds grown under it, held so too: known, not tested)
  let row_let = Ref(-1)
  let row_hand_moved = Ref(false)
  // (how tall what it shows was as it was last laid out: the room it shows in changed since (a keyboard's), what shows
  // held from the foot of that room where a field in a row holds it at its foot, at its foot still, Tree::holds_now's)
  let row_vh = Ref(0.0)
  let row_let_go = fn(hand : Bool) {
    if row_hand_moved.val || hand {
      row_hand_moved.val = false
      if self.tree.row_focus_holds(self.id()) is Some(n) {
        row_let.val = n
      }
    }
  }
  // (room kept under its foot for what was pressed to stay where it was as what is round it shrinks (press_stays.mbt):
  // as much as that asks while it is held, then no more than still shows of it, going as it is scrolled off)
  // (the room kept under the last block: what was pressed staying where it was as what is round it shrinks
  // (press_stays.mbt), as much as that asks while it is held; a key that went leaving its room, as tall as it was
  // (`leaves_room`). Taken first by a block come at its foot, which sets out from as tall as it is (each_by's
  // `from_of`); no more than still shows of it, going as it is scrolled off. At its foot is at its foot)
  let foot_room : @signals.Signal[Double] = @signals.signal(0.0, same=fn(a, b) { a == b })
  // (the blocks come at its foot that took the room, each with the row it is made in and how tall it set out from:
  // measured shorter than that in the fill that makes it, from as tall as it is, the rest of the room left, in that
  // layout)
  let took_room : Map[K, (View, Double)] = Map([])
  // (how far down its blocks and the room under them but that go, as they are counted now)
  let blocks_foot = fn(all : Places[K]) {
    all.foot() + room_under() + @signals.untracked(fn() { s.tuck_room.get() })
  }
  // (where the scroll was as the anchor was last put: what it moved by since, carried to the anchor)
  let anchor_x : Ref[Double?] = Ref(None)
  // (an ask put back by the last fill as it was cut short by its foot still going down (the fill's end): not at its
  // foot meanwhile, nothing following it; and the ask so put back, which the hand lets go of)
  let ask_cut = Ref(false)
  let ask_cut_was : Ref[ListAsk[K]?] = Ref(None)
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
  let held_at = fn(all : Places[K]) -> (Int, Double)? {
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
  let top_now = fn(all : Places[K], x : Double) {
    match (held_at(all), anchor_x.val) {
      (Some((i, off)), Some(was)) => all.top(i) + off + (x - was)
      _ => x
    }
  }
  // (where the top of what shows is with the column at its foot, showing `vh` of it: by its blocks as they are counted
  // now and its foot's room, followed)
  let foot_top = fn(all : Places[K], vh : Double) {
    dmax(0.0, all.foot() + room_under() + s.tuck_room.get() + foot_room.get() - vh)
  }
  // (a press in one of its blocks, press_stays.mbt: that block held so that what was pressed stays where it was: its
  // key, how far under the top of what shows its top was, what lies over what was pressed in it (each node before it
  // or before what holds it, down a column, in the block) and how tall that was then; none once the hand moves it or
  // all the press set off has ended)
  let pin : Ref[(K, Double, Array[View], Double)?] = Ref(None)
  // (what was pressed: let go, or what was over it, held no more)
  let pin_node : Ref[View?] = Ref(None)
  let unpin : Ref[() -> Unit] = Ref(fn() {  })
  let pin_ends = Ref(false)
  // (where it was scrolled to as it was pressed: moved from there by the hand, held no more; and how many blocks it had,
  // and its last, then: blocks come or gone since at its foot, where it follows it, followed again)
  let pin_x = Ref(0.0)
  let pin_with : Ref[(Int, K?)] = Ref((0, None))
  let pin_foot = Ref(false)
  // (the node its blocks are held in, once made: what they hold set coming or going kept by it, Tree's list_inner)
  let held_node = Ref(-1)
  // (how tall what lies over what was pressed is, each measured now as wide as it was last laid out; where what it is
  // or holds through its slots (a show's, a pick's, an each's) is on its way in or out, as tall as its way has it at
  // the moment it is read, as Places reads a block on its way: measured whole, a way's opening would be counted all at
  // once as it sets out)
  let over_h = fn(over : Array[View]) {
    let tree = self.tree
    let laying = tree.rooming == self.at
    let t = tree.logic_said()
    let mut h = 0.0
    for o in over {
      guard o.alive() && tree.nodes[o.at].flex.style.display != @flex.Display::DisplayNone else { continue }
      let items = if tree.nodes[o.at].slot { tree.column_items(o.at) } else { [o.at] }
      let on_way = items.iter().any(fn(k) {
        let st = tree.nodes[k].flex.style
        tree.nodes[k].live && st.come_at == st.come_at && st.come_to == st.come_to
      })
      if !on_way {
        h = h + @flex.measured_height(tree.nodes[o.at].flex, tree.nodes[o.at].flex.width)
        continue
      }
      // (one made since it was last laid out: as wide as what holds it was)
      let wide = if tree.nodes[o.at].flex.width > 0.0 {
        tree.nodes[o.at].flex.width
      } else {
        tree.nodes[tree.nodes[o.at].parent].flex.width
      }
      for k in items {
        let m = tree.nodes[k]
        guard m.live && m.flex.style.display != @flex.Display::DisplayNone else { continue }
        let st = m.flex.style
        // (how tall it comes to whole: what its way went to as it was last laid out, coming; measured, it is as tall as
        // its way had it then, never laid out yet as tall as it comes to)
        let whole = if st.come_goal == st.come_goal && st.come_to > 0.0 {
          st.come_goal / st.come_to
        } else {
          @flex.measured_height(m.flex, if m.flex.width > 0.0 { m.flex.width } else { wide })
        }
        let at = if laying && st.come_now == st.come_now { st.come_now } else { t }
        h = h + @flex.come_tall_at(st, whole, at)
      }
    }
    h
  }
  // (when all a change at `cause` set off ends: the latest end any of what was set coming (or going too, where not
  // `coming`) in it at that moment declares (its keys' ways, what its blocks hold: Tree's list_inner, a way turned back
  // too), said once the change is told whole and its column's group with it; where none declares one, as long as a
  // Move takes at most)
  let set_off_end = fn(cause : Double, coming : Bool) -> Double {
    let mut end = @double.neg_infinity
    let set_off = ways.map(fn(w) { w.0 })
    set_off.append(self.tree.list_inner_at(held_node.val, cause))
    for w in set_off {
      match w.live() {
        Some(n) if (n.coming || !coming) &&
          n.flex.style.come_at == cause &&
          n.flex.style.come_ends == n.flex.style.come_ends => end = dmax(end, n.flex.style.come_ends)
        _ => ()
      }
    }
    if end > cause {
      end
    } else {
      cause + @flex.move_most_ms
    }
  }
  s.pressed_said = fn(v) {
    // (the block it is in, made here, and what lies over it there: none, nothing held)
    let over : Array[View] = []
    let mut found : K? = None
    let mut i = v.at
    while i >= 0 && i != self.at && found is None {
      for b in blocks {
        if b.0.at == i && b.0.alive() {
          found = Some(@signals.untracked(b.1))
        }
      }
      let up = self.tree.nodes[i].parent
      if found is None && up >= 0 && self.tree.nodes[up].flex.style.direction is Column {
        for c in self.tree.nodes[up].kids {
          if c == i {
            break
          }
          over.push(self.tree.handle(c))
        }
      }
      i = up
    }
    guard found is Some(k) else { return fn() {  } }
    let all = places(laid.untracked())
    guard laid_at.get(k) is Some(j) && j < all.length() else { return fn() {  } }
    // (where the top of what shows is: at its foot, followed there, where that is)
    let shown_top = if s.at_foot() {
      foot_top(all, match s.seen.untracked() {
        Some((_, vh)) => vh
        None => 0.0
      })
    } else {
      top_now(all, @signals.untracked(at))
    }
    let below = all.top(j) - shown_top
    let was = over_h(over)
    let x_then = @signals.untracked(at)
    let foot_then = s.at_foot() && @signals.untracked(follows)
    fn() {
      (unpin.val)()
      pin.val = Some((k, below, over, was))
      pin_node.val = Some(v)
      pin_x.val = x_then
      let ks = @signals.untracked(keys)
      pin_with.val = (ks.length(), ks.last())
      pin_foot.val = foot_then
      // (all it set off ended: held so once more, in the layout of that moment, then no more. Its end the latest any
      // of what was set coming or going in it at the press's moment declares (a row's way, what a block holds; a
      // group turned back too), said once the change is told whole and its column's group with it, a wait inside a
      // wait as the ways' own; where none declares one, as long as a Move takes at most)
      pin_ends.val = false
      unpin.val = fn() {  }
      let cause = self.tree.cause_now()
      let mine = pin.val
      @signals.after_flush(fn() {
        @signals.after_flush(fn() {
          guard physical_equal(pin.val, mine) else { return }
          let end = set_off_end(cause, true)
          unpin.val = self.at_moment(end, fn() {
            pin_ends.val = true
            laid_again()
          })
        })
      })
    }
  }
  // (the floor armed by a change: from how tall the column is as its fill last left it (as tall as it shows, a floor
  // armed before counted in it), till all that change set off ends, coming or going; one armed again by another change
  // meanwhile goes on from there. Not while what is pressed holds it)
  let floor_off : Ref[() -> Unit] = Ref(fn() {  })
  let floor_n = Ref(0)
  floor_arm.val = fn(k, stretch) {
    guard !(pin.val is Some(_)) else { return }
    (floor_off.val)()
    floor_off.val = fn() {  }
    floor.val = Some((k, stretch))
    floor_n.val = floor_n.val + 1
    let mine = floor_n.val
    let cause = self.tree.cause_now()
    @signals.after_flush(fn() {
      @signals.after_flush(fn() {
        guard floor_n.val == mine && floor.val is Some(_) else { return }
        floor_off.val = self.at_moment(set_off_end(cause, false), fn() {
          if floor_n.val == mine {
            floor.val = None
          }
        })
      })
    })
  }
  floor_end.val = fn() {
    floor.val = None
    (floor_off.val)()
    floor_off.val = fn() {  }
  }
  self.owns(fn() { (floor_off.val)() }) |> ignore
  // (following its foot, scrolled back to it by the hand or the wheel, at rest there: at its foot again, kept there
  // however far that comes to be as what it holds grows, till it is moved off it; told as that comes to be so, not each
  // time the column is scrolled. By its own blocks and its anchor, as its near_foot is: by how far the scroll could
  // go as last laid out, a column moved in its fill for what came in or grew over what shows (Scroll::grew_above)
  // further than that was read at its foot before that layout said how far it goes now, and taken there: what was
  // read 100 off its foot gone as a block 150 taller than counted came in at its top.)
  let at_most = @signals.computed(fn(_) {
    guard s.seen.get() is Some((_, vh)) else { return false }
    let all = places(laid.get())
    top_now(all, at()) >= foot_top(all, vh) - 0.5 && s.rest_now() is None && s.glides_till() is None
  }, same=fn(a, b) { a == b })
  // (at its foot as Scroll::at_foot_now tells it, told only as that changes: following it there, however far that comes
  // to be; else where the top of what shows is by its anchor, as its blocks are counted now, within half a point of
  // where it would be at its foot. By its own blocks, so in the same layout as one measured anew or grown there, as
  // its near_foot is; not by how far the scroll went as last laid out, which a block come or grown has not reached yet)
  let at_foot_now = @signals.computed(fn(_) {
    if s.x.get() == @double.infinity {
      return true
    }
    guard s.seen.get() is Some((_, vh)) else { return false }
    let all = places(laid.get())
    top_now(all, at()) >= foot_top(all, vh) - 0.5
  }, same=fn(a, b) { a == b })
  s.at_foot_said = Some(fn() { at_foot_now.get() })
  // (what its foot covers of what shows, for what is brought into sight: the room it keeps under its last block)
  s.foot_covered = fn() { foot_h.get() }
  self.reacts(fn() { at_most.get() }, fn(foot) {
    if foot && @signals.untracked(follows) && !s.at_foot() && !ask_cut.val {
      // (back at its foot, having left it: followed again, whatever held it where it was, Scroll::holds_here, a
      // field in a row)
      s.held = false
      // (the hand's: the scroll moved off where its last fill put it, before a fill has seen it)
      row_let_go(anchor_x.val is Some(was) && (@signals.untracked(at) - was).abs() > 0.000001)
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
        let foot = counted(laid.get()).foot()
        foot + room_under() + s.tuck_room.get() + foot_room.get() - vh - at() < screens * vh
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
        let all = counted(laid.get())
        let x = at()
        // (by where its keys start, under its head: how far what shows is from them)
        if s.at_foot() {
          foot_top(all, vh) <= all.col.start
        } else {
          top_now(all, x) - all.col.start < screens * vh
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
  let holding = fn(all : Places[K], i : Int) {
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
  // wakes what it binds (View::rests) and the slot it is still in, none once that slot left what has slots and it was
  // taken out of it, held by no node (View::park): so many at most of each, the rest let go; all let go with the list)
  let spare : Map[Int, Array[(View, @signals.Signal[K], () -> Unit, View?)]] = Map([])
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
  // (how tall what it holds comes to with its blocks where `all` has them, and its foot's room, untracked)
  let whole_of = fn(all : Places[K]) {
    @signals.untracked(fn() { all.foot() + room_under() + s.tuck_room.get() + foot_room.get() })
  }
  // (how tall what it holds comes to: its blocks where they are now, on its host's pixels, and its foot's room)
  let whole_now = fn() {
    @signals.untracked(fn() { whole_of(places(laid.get())) })
  }
  // (what is asked of it at a cause: done as the column is laid out again, or at once where it glides there)
  match place {
    Some(p) => {
      s.to_foot = fn(_) {
        p.to_end(glide=false)
        true
      }
      p.laid_again = laid_again
      // (what a test reads of it and asks of it, as of an old view's list: Tree::lists_seen)
      let asked_tree = self.tree
      let asked_at = self.at
      asked_tree.lists_asked[asked_at] = {
        scroll: s,
        count: fn() { @signals.untracked(keys).length() },
        bring: fn(i) {
          let ks = @signals.untracked(keys)
          if i >= 0 && i < ks.length() {
            p.bring(ks[i])
          }
        },
        to_end: fn() { p.to_end(glide=false) },
      }
      self.owns(fn() { asked_tree.lists_asked.remove(asked_at) }) |> ignore
      // (what it has in sight, counted by its keys' blocks as they come to rest: their heights as counted, not as a way
      // has them, the scroll where it rests (at its foot where it follows it, where a notch eases to; where it is as a
      // fling goes), and told to the place's handlers at the hand's moments (Tree::sights_now), as that differs)
      p.sight_of = fn() {
        @signals.untracked(fn() {
          let all = Places::counted(laid.get())
          match sight_counted(all, s, self.tree.logic_said(), room_under(), foot_room.get()) {
            // (a key gone leaving its room, kept among its blocks while it fades: never told, the one over it in its
            // place, its height still counted where the foot is)
            Some(sg) if fading.val is Some((k, _)) && all.length() >= 2 => {
              let over = all.key(all.length() - 2)
              Some({
                ..sg,
                first: if sg.first == k { over } else { sg.first },
                last: if sg.last == k { over } else { sg.last },
                whole: if sg.whole == Some(k) { Some(over) } else { sg.whole },
              })
            }
            other => other
          }
        })
      }
      // (told it only once something listens (ListPlace::on_sight): till then nothing of it is worked out or owed)
      let sight_tree = self.tree
      let sight_at = self.at
      let listened = Ref(false)
      p.sight_listened = fn() {
        guard !listened.val && self.alive() else { return }
        listened.val = true
        sight_tree.sight_tellers[sight_at] = fn() { p.sight_tell() }
        sight_tree.sight_owe(sight_tree.logic_said())
      }
      self.owns(fn() {
        sight_tree.sight_tellers.remove(sight_at)
        p.sight_listened = fn() {  }
      })
      |> ignore
      if !p.sight_fns.is_empty() {
        (p.sight_listened)()
      }
      p.glide = fn(ask) {
        let all = places(laid.untracked())
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
  let anchor_put = fn(all : Places[K], top : Double, vh : Double, x : Double) {
    anchor.val = if all.length() > 0 {
      let first = holding(all, all.first_past(top).min(all.length() - 1))
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
  anchor_again.val = fn(col) {
    let all = places(col)
    guard !s.at_foot() && anchor_x.val is Some(was) && held_at(all) is Some(_) else { return }
    let x = @signals.untracked(at)
    guard (x - was).abs() > 0.000001 else { return }
    let vh = match s.seen.untracked() {
      Some((_, vh)) => vh
      None => 0.0
    }
    anchor_put(all, top_now(all, x), vh, x)
  }
  // (the keys that have slots, in order: those that meet where it shows and `slots_margin` of its heights over and
  // under it, found again only as what shows comes within `slots_near` of their ends or is more than `slots_far` from
  // them (a wheel going back and forth over where they end makes and lets go nothing), and as the keys change among
  // them; the rest have no node, the column holding a spacer over them and one under, as tall as they are counted)
  let slot_keys : @signals.Signal[Array[K]] = @signals.signal([], same=fn(a, b) { physical_equal(a, b) })
  // (where the slots' first key was found, in which column and at how many of its fillings: while it is filled no
  // more, the slots are where they were found and what covers what shows is told by places alone, no key looked up)
  let slots_found : Ref[(Column[K], Int, Int)?] = Ref(None)
  // (what the window last found shows, and the places it found it from and to: window)
  let window_found : Ref[(Array[K], Int, Int)] = Ref(([], 0, -1))
  // (the slots that hold `need` (what shows) and as much round it as where the column shows from `top`, `vh` tall,
  // asks; a block put by in a slot that leaves them taken out of it first, held by no node (View::park), kept)
  let slots_cover = fn(all : Places[K], need : Array[K], top : Double, vh : Double) {
    let n = all.length()
    if n == 0 {
      if slot_keys.untracked().length() > 0 {
        slot_keys.set([])
      }
      return
    }
    // (where what shows is: by the places the window found it at, where it is what the window found; else by its keys)
    let mut lo = n
    let mut hi = -1
    let (wnow, wlo, whi) = window_found.val
    if physical_equal(wnow, need) {
      if wlo <= whi {
        lo = wlo
        hi = whi.min(n - 1)
      }
    } else {
      for k in need {
        match laid_at.get(k) {
          Some(i) if i < n => {
            lo = lo.min(i)
            hi = hi.max(i)
          }
          _ => ()
        }
      }
    }
    let cur = slot_keys.untracked()
    let holds = fn(i : Int) {
      let j = i + cur.length() - 1
      i <= lo &&
      hi <= j &&
      (vh <= 0.0 ||
      (
        (i == 0 || all.top(i) <= top - slots_near * vh) &&
        (j == n - 1 || all.top(j) + all.h(j) >= top + vh + slots_near * vh) &&
        (i == lo || all.top(i) + all.h(i) >= top - slots_far * vh) &&
        (j == hi || all.top(j) <= top + vh + slots_far * vh)
      ))
    }
    // (the column filled no more since the slots were found: where they are, its places alone)
    let found_at = match slots_found.val {
      Some((col, at, i)) if physical_equal(col, all.col) && at == all.col.refills && i + cur.length() <= n => Some(i)
      _ => None
    }
    let covered = match found_at {
      Some(i) => cur.length() > 0 && holds(i)
      None =>
        match cur.get(0) {
          Some(a) =>
            match laid_at.get(a) {
              Some(i) if i + cur.length() <= n => {
                let mut same = true
                for t in 0..<cur.length() {
                  if all.key(i + t) != cur[t] {
                    same = false
                    break
                  }
                }
                if same {
                  slots_found.val = Some((all.col, all.col.refills, i))
                }
                same && holds(i)
              }
              _ => false
            }
          None => false
        }
    }
    if covered {
      return
    }
    let (a, b) = if vh > 0.0 {
      (
        all.first_past(top - slots_margin * vh).min(n - 1),
        all.first_past(top + vh + slots_margin * vh).min(n - 1),
      )
    } else if hi >= 0 {
      (lo, hi)
    } else {
      (0, -1)
    }
    let a = if hi >= 0 { a.min(lo) } else { a }
    let b = if hi >= 0 { b.max(hi) } else { b }
    // (found again as its keys changed (the column filled again since they were found): an end of the slots that still
    // holds as it is kept where it was, so a key come or gone costs its own slot alone, not those at an end found anew
    // a screen round what shows; each end as `covered` holds it. Found again as it was scrolled, both ends found anew
    // round what shows, as narrow as the margin)
    let (a, b) = match (cur.get(0), cur.last()) {
      (Some(f), Some(l)) if vh > 0.0 && hi >= 0 && found_at is None =>
        match (laid_at.get(f), laid_at.get(l)) {
          (Some(i), Some(j)) if i <= j && j < n => {
            let top_holds = i <= lo &&
              (i == 0 || all.top(i) <= top - slots_near * vh) &&
              (i == lo || all.top(i) + all.h(i) >= top - slots_far * vh)
            let foot_holds = hi <= j &&
              (j == n - 1 || all.top(j) + all.h(j) >= top + vh + slots_near * vh) &&
              (j == hi || all.top(j) <= top + vh + slots_far * vh)
            (if top_holds { i } else { a }, if foot_holds { j } else { b })
          }
          _ => (a, b)
        }
      _ => (a, b)
    }
    // (a block put by in a slot that leaves them: taken out of it, held by no node, as it is let go)
    for _, those in spare {
      for i, sp in those {
        match sp {
          (v, key, wake, Some(was_in)) => {
            // (its key still among the keys and out of those kept: parked; gone from the list, let go with its slot,
            // as were every slot kept)
            let at = laid_at.get(key.untracked())
            if at is Some(j) && (j < a || j > b) && v.alive() {
              was_in.park(v) |> ignore
              those[i] = (v, key, wake, None)
            }
          }
          _ => ()
        }
      }
    }
    let ks = []
    for i in a..=b {
      ks.push(all.key(i))
    }
    slots_found.val = if a <= b { Some((all.col, all.col.refills, a)) } else { None }
    slot_keys.set(ks)
  }
  seen_before.val = fn(col) {
    @signals.untracked(fn() {
      let out = []
      guard s.seen.get() is Some((_, vh)) && vh > 0.0 && !shown_now.is_empty() else { return out }
      let all = places(col)
      let top = if s.at_foot() { foot_top(all, vh) } else { top_now(all, at()) }
      for k in shown_now {
        if laid_at.get(k) is Some(i) && i < all.length() {
          out.push((k, i, all.top(i) - top))
        }
      }
      out
    })
  }
  // (what is made, the stretch it covers, as `shown_now` says)
  let made_now = fn(all : Places[K]) {
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
  let window = fn(all : Places[K], top : Double, vh : Double, lo : Int, hi : Int, up_first : Bool) -> Array[K] {
    let now = []
    // (showing none of it, a page under another: none made, the one it is held by neither, what it reads let go)
    if vh <= 0.0 {
      window_found.val = (now, 0, -1)
      return now
    }
    if lo > hi {
      let first = all.first_past(top)
      let mut i = first
      let mut last = first - 1
      while i < all.length() && all.top(i) < top + vh {
        now.push(all.key(i))
        last = i
        if !all.known(i) {
          break
        }
        i = i + 1
      }
      window_found.val = (now, first, last)
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
    let mut last = b
    if !all.known(b) {
      let mut i = b + 1
      while i < all.length() && all.top(i) < top + vh {
        if showing.contains(all.key(i)) {
          now.push(all.key(i))
          last = i
        }
        i = i + 1
      }
    }
    window_found.val = (now, a, last)
    now
  }
  // (whether what came among its keys by data or went since its fill last ran, said to come, may make its way: told so
  // as the change goes on (View::each's way_of), its fill then showing what shows from where that way sets out)
  let way_may = fn() { gone_from.val.length() > 0 || came_by_data.val.length() > 0 }
  // (while a block is on its way: those that show where all of it ends, from `top_end`, with those that show `now`, in
  // their order: what shows from where the way set out to where it ends kept made till it ends, let go then)
  let with_end = fn(all : Places[K], now : Array[K], top_end : Double, vh : Double) -> Array[K] {
    guard !ways.is_empty() else { return now }
    let more = window(counted(all.col), top_end, vh, all.length(), -1, true).filter(fn(k) { !now.contains(k) })
    guard more.length() > 0 else { return now }
    let both = now.copy()
    both.append(more)
    both.sort_by_key(fn(k) { laid_at.get(k).unwrap_or(-1) })
    both
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
      // (and where the keys changed under its slots (one come at its end, put in or taken among them): its slots
      // brought up to them now, as the change is taken, by where what shows is at its foot, before the column is laid
      // out, so that one layout lays out what comes and its fill measures it there; else a key come among what shows had
      // no slot, none drawn)
      let all = places(laid.untracked())
      let stale = match slots_found.val {
        Some((col, at, _)) => !physical_equal(col, all.col) || at != all.col.refills
        None => slot_keys.untracked().length() > 0
      }
      if stale {
        let top = foot_top(all, vh)
        slots_cover(all, window(all, top, vh, all.length(), -1, true), top, vh)
      }
      if out {
        laid_again()
      }
      return
    }
    let all = places(laid.untracked())
    // (its keys changed by data with what may make its way among them (way_of, told as the change goes on): what is
    // made let go of none yet, its fill, laid out in the change, showing what shows from where that way sets out)
    if way_may() {
      // (its slots brought up to its keys in this pass all the same, round what shows by where it is counted now and
      // what showed, so a key come there has the slot its way is made on)
      let x = top_now(all, @signals.untracked(at))
      let keep = window(all, x, vh, all.length(), -1, true).copy()
      for k in shown_now {
        if laid_at.contains(k) && !keep.contains(k) {
          keep.push(k)
        }
      }
      slots_cover(all, keep, x, vh)
      laid_again()
      return
    }
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
    let now = with_end(all, window(all, x, vh, lo, hi, true), top_now(counted(all.col), @signals.untracked(at)), vh)
    show_only(now)
    slots_cover(all, now, x, vh)
    made_now(all)
    // (what shows still past what is made: the window stopped at a block never measured whose slot nothing lays out (made
    // before as a slot round what showed, its height forgotten as the words were redone: Tree::alone_asks never asked
    // of it), so `past_made` stays true and tells nothing more: the column laid out, its fill measuring what shows.
    // Else a fling after the app came back with its glyphs moved on showed the list's ground till it came to rest)
    if past_made.untracked() {
      laid_again()
    }
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
    let row = self.tree.row_focus_holds(self.id())
    let row_holds = row is Some(n) && n != row_let.val
    if !row_holds {
      row_hand_moved.val = false
    }
    let mut held = (s.held || row_holds) && s.at_foot()
    let mut follows_foot = @signals.untracked(follows) && s.at_foot() && !held
    // (the anchor as the scroll moved it since; none yet, where the scroll is)
    let start = {
      let all = places(laid.untracked())
      let fresh = fn() {
        let i = all.first_past(x)
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
        // (moved by the hand: held where it was no more, nor by what was pressed; held by a field in a row, let go
        // of as the hand brings it back to its foot; an ask this list put back as it was cut short by its foot still
        // going down let go of, the list where the hand put it: not one its page gave anew)
        s.held = false
        match (place, ask_cut_was.val) {
          (Some(p), Some(was)) if ask_cut.val && p.asked is Some(a) && physical_equal(a, was) => {
            p.asked = None
            ask_cut.val = false
            ask_cut_was.val = None
          }
          _ => ()
        }
        if row_holds {
          row_hand_moved.val = true
        }
        if (x - pin_x.val).abs() > 0.000001 {
          pin.val = None
          (unpin.val)()
        }
        // (taken off its foot: the column held no more, the room as it is, going as it is scrolled off)
        if floor.val is Some(_) && !s.at_foot() {
          (floor_end.val)()
        }
        let all = places(laid.untracked())
        if all.length() > 0 {
          let i = ai.min(all.length() - 1).max(0)
          let at_now = all.top(i) + aoff
          let j = holding(all, all.first_past(at_now).min(all.length() - 1))
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
    // (the place's ask taken in this fill, as it was asked: put back at its end where this fill could not make what
    // shows, below)
    let mut taken : ListAsk[K]? = None
    match place {
      Some(p) =>
        match p.asked {
          Some(ToEnd) => {
            p.asked = None
            taken = Some(ToEnd)
            if row is Some(n) {
              row_let.val = n
              row_hand_moved.val = false
            }
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
                taken = Some(ask)
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
    match (pin.val, pin_node.val) {
      (Some((_, _, over, _)), Some(v)) if !v.alive() || over.iter().any(fn(o) { !o.alive() }) => {
        pin.val = None
        (unpin.val)()
      }
      _ => ()
    }
    if pin.val is Some(_) && pin_foot.val && !asked {
      let ks = @signals.untracked(keys)
      if pin_with.val != (ks.length(), ks.last()) {
        pin.val = None
        (unpin.val)()
        s.to_foot()
        // (held by a field in a row: held where it is at its foot from now, not followed)
        follows_foot = !row_holds
        held = row_holds
      }
    }
    // (held by what was pressed in a block: neither following its foot nor held at it meanwhile)
    if !asked && pin.val is Some((k, _, _, _)) && laid_at.contains(k) {
      follows_foot = false
      held = false
    }
    // (its foot followed no further than a block's top `margin` under where it shows from: held there, off its foot,
    // once it would go further, and followed no further after)
    // (held at its foot by a field in a row, the room it shows in another than as it was last so held: what shows held
    // from that room's foot, at its foot still)
    if held && row_holds && !s.held {
      let vh_now = shows().unwrap_or(0.0)
      if row_vh.val > 0.0 && vh_now > 0.0 {
        aoff = aoff + (row_vh.val - vh_now)
      }
    }
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
      // (its head and its foot measured as the blocks are, at its width, in this layout: the head's height where its
      // keys start, the foot's the room under them. The head grown or shrunk where what shows starts in it or at its
      // very top: what shows starting there still, what is under it moved with it; else what is read where it is)
      match head_v.val {
        Some(hv) if hv.alive() => {
          let hh = rows_slot_on(self.tree.height_in(hv.at, self.at, w), self.tree.rows_grid_now())
          if hh != column.start {
            let was = places(laid.untracked())
            if was.length() > 0 {
              let i = ai.min(was.length() - 1).max(0)
              let shown_from = was.top(i) + aoff
              if shown_from < column.start || shown_from <= 0.0 {
                aoff = aoff - (hh - column.start)
              }
            }
            column.start_at(hh)
            head_tall.set(hh)
            tell()
          }
        }
        _ => ()
      }
      match foot_v.val {
        // (the foot's on the host's pixels as the head's is, the one reading of the room under the last block: the foot
        // placed that tall, so its top lies where the last block ends)
        Some(fv) if fv.alive() => foot_h.set(rows_slot_on(self.tree.height_in(fv.at, self.at, w), self.tree.rows_grid_now()))
        _ => ()
      }
      let all = places(laid.untracked())
      vh = shows().unwrap_or(0.0)
      if all.length() == 0 {
        found = []
        show_only([])
        top = 0.0
        break
      }
      // (a block brought to the middle: by its height as it is counted now, measured or not, again as it is measured)
      ai = ai.min(all.length() - 1).max(0)
      // (held by what was pressed in a block: the block's top as far up as what lies over what was pressed grew since,
      // the room under its foot as that asks)
      let mut pressed_holds = false
      if !asked && pin.val is Some((k, below, over, was)) && laid_at.get(k) is Some(i) && i < all.length() {
        ai = i
        pressed_holds = true
        aoff = over_h(over) - was - below
        foot_room.set(dmax(0.0, all.top(i) + aoff + vh - blocks_foot(all)))
      } else if floor.val is Some((lk, e0)) {
        // (a key come at its foot: the stretch from the last that stayed as long as it was, it and what is under it and
        // the foot as they show now)
        match laid_at.get(lk) {
          Some(i) if i < all.length() => foot_room.set(dmax(0.0, e0 - (blocks_foot(all) - all.top(i))))
          _ => (floor_end.val)()
        }
      }
      if centring {
        aoff = counted(laid.untracked()).h(ai) / 2.0 - vh / 2.0
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
      } else if pressed_holds || (all.top(ai) + all.h(ai) > top && all.top(ai) < top + vh) {
        // (held by what was pressed in it, the block shows by that alone, where what is over that comes to now: what
        // shows goes out from it, never found by its place as counted at the last layout. As tall as it was then, what
        // it opened over the pressed grown since by more than a screen (no frame for 88 ms) put it off what shows: let
        // go, made anew, what it had opened shut, 2026-11-12. Made, it is measured in this pass and those round it
        // found again by where it ends now)
        ai
      } else {
        all.first_past(top).min(all.length() - 1)
      }
      let now = window(all, top, vh, si, si, !foot && !centring)
      // (a block on its way: what shows where all of it ends as well, kept made till then)
      let now = if !ways.is_empty() {
        let end = counted(all.col)
        let most_end = dmax(0.0, whole_of(end) - vh)
        with_end(all, now, if foot { most_end } else { dclamp(end.top(ai) + (top - all.top(ai)), 0.0, most_end) }, vh)
      } else {
        now
      }
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
      slots_cover(all, now, top, vh)
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
    if pin_ends.val {
      pin_ends.val = false
      pin.val = None
    }
    // (held by what was pressed no more: the room kept for it no more than still shows)
    if !(pin.val is Some((k, _, _, _)) && laid_at.contains(k)) {
      let left = dmax(0.0, top + vh - blocks_foot(places(laid.untracked())))
      if left < foot_room.untracked() {
        foot_room.set(left)
      }
    }
    // (an ask is taken only by a fill that could make what shows: one laid out where what shows could not be made in it
    // (its slots not made yet: a layout asked inside a change's open batch, as a structure's first making reads where
    // something is laid out, View::laid_window_now) measures nothing, and what it put would be held by a block only
    // counted. The ask put back, unless another came meanwhile: the next fill takes it anew, the block it asks for held
    // through every pass as what shows is made and measured)
    // So too one that could not put the list where it asks: the place it gives cut short by a foot still to go down
    // (what comes under it on its way: where all of it ends, the list goes further than it does now), the next fill
    // taking it anew, each going down with its foot till the block asked is where it was asked; taken for good by the
    // first not cut short, or cut only where the list ends (asked further than it ever goes: at its foot, done)
    let cut = match taken {
      Some(ToEnd) | None => false
      Some(_) => {
        let all = places(laid.untracked())
        if all.length() == 0 {
          false
        } else {
          let i = ai.min(all.length() - 1).max(0)
          let wants = all.top(i) + aoff
          let ends = dmax(0.0, whole_of(counted(laid.untracked())) - vh)
          wants > top + 0.5 && ends > top + 0.5
        }
      }
    }
    ask_cut.val = false
    match (taken, place) {
      (Some(ask), Some(p)) if p.asked is None &&
        (cut || found.iter().any(fn(k) { !showing.contains(k) })) => {
        p.asked = Some(ask)
        ask_cut.val = cut
        ask_cut_was.val = if cut { Some(ask) } else { None }
      }
      (Some(_), _) =>
        // (what it has in sight owed as of then, told once this layout is done: ListPlace::on_sight)
        self.tree.sight_owe(self.tree.logic_said())
      _ => ()
    }
    // (a block come at its foot that took the room, measured now: shorter than the room it set out from, from as tall
    // as it is (the rest of the room the floor's, so nothing over it comes down))
    if took_room.length() > 0 {
      for k in took_room.keys().collect() {
        guard took_room.get(k) is Some((row, r)) else { continue }
        match (row.live(), heights.get(k)) {
          (Some(m), Some(h)) => {
            took_room.remove(k)
            let st = m.flex.style
            if m.coming && h < r - 0.001 && st.come_from > h {
              st.come_from = h
              self.tree.layout_marked_at(row.at)
            }
          }
          (None, _) => took_room.remove(k) |> ignore
          _ => ()
        }
      }
    }
    // (what the last pass found, alone: what showed before and shows no more let go now, in this layout)
    show_only(found)
    slots_cover(places(laid.untracked()), found, top, vh)
    let live = blocks.filter(fn(b) { b.0.alive() })
    blocks.clear()
    blocks.append(live)
    let all = places(laid.untracked())
    // (how tall the column is as this fill leaves it and where its blocks are: what a floor armed next is held to)
    laid_whole.val = blocks_foot(all) + foot_room.untracked()
    laid_last.val = Some(all)
    match floor.val {
      Some((lk, _)) =>
        match laid_at.get(lk) {
          Some(i) if i < all.length() => laid_stretch.val = laid_whole.val - all.top(i)
          _ => ()
        }
      None => ()
    }
    // (the anchor from now, where the scroll is put: anchor_put)
    anchor_put(all, top, vh, top)
    row_vh.val = vh
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
    } else if !follows_foot && s.at_foot() {
      // (held by what was pressed, off its foot from where it was there)
      s.put(top)
    } else if !follows_foot && (top - x).abs() > 0.000001 {
      if s.as_list && !asked {
        s.grew_above(top - x)
      } else {
        s.put(top)
      }
    }
    // (back at its foot at rest, where it follows its foot: kept there from now as what it holds grows; not where an
    // ask cut short by its foot still going down was put back, the next fill going on with it)
    if !follows_foot &&
      !held &&
      !ask_cut.val &&
      !(pin.val is Some((k, _, _, _)) && laid_at.contains(k)) &&
      @signals.untracked(follows) &&
      vh > 0.0 &&
      top >= dmax(0.0, whole_now() - vh) - 0.5 &&
      s.rest_now() is None &&
      s.glides_till() is None {
      s.held = false
      row_let_go(false)
      s.to_foot()
    }
    seen_rows.clear()
    for k in shown_now {
      seen_rows[k] = true
    }
    // (what came or went by the last change of its keys, told its rows by now: what shows found from here by its ways)
    if came_by_data.val.length() > 0 {
      came_by_data.val = Map([])
    }
    if gone_from.val.length() > 0 {
      gone_from.val = Map([])
    }
    self.tree.room_bindings_run()
  }
  s.whole = Some(whole_now)
  // (its ways kept till the latest end any of them declares (Style's come_ends, said as the change that set it was
  // taken), waited for as a moment (View::at_moment); there, those whose end is past let go, what shows found again
  // without them, the rest waited for again: one set off anew in a later change, as long as that says. One whose end
  // its layout has not said yet (not laid out in its change) ends at the longest a Move takes from its moment, as
  // View::comes waits for it; one never set off (its column's motion reduced, the tree not drawn yet) has no moment)
  let way_ends = fn(n : Node) {
    let st = n.flex.style
    if st.come_ends == st.come_ends {
      st.come_ends
    } else {
      st.come_at + @flex.move_most_ms
    }
  }
  let ways_due : Ref[() -> Unit] = Ref(fn() {  })
  ways_due.val = fn() {
    let t = self.tree.logic_said()
    let left = ways.filter(fn(w) { w.0.live() is Some(n) && way_ends(n) > t })
    if left.length() != ways.length() {
      ways.clear()
      ways.append(left)
      laid_again()
    }
    (ways_off.val)()
    ways_off.val = fn() {  }
    let mut end = @double.neg_infinity
    for w in ways {
      if w.0.live() is Some(n) {
        end = dmax(end, way_ends(n))
      }
    }
    if end > t {
      ways_off.val = self.at_moment(end, fn() { (ways_due.val)() })
    }
  }
  self.owns(fn() { (ways_off.val)() }) |> ignore
  // Whether a row its keys' change made or lets go (View::each's, `coming` or going) makes its way: where it is seen,
  // as it is told. Coming: come by data (not moved among them), its page saying it comes (`comes`, asked once now), and
  // where it ends seen, at its foot where it follows it; off it under what is read (the block holding the top of what
  // shows over it) and over where what shows ends. Going: it showed, at its foot or under the top of what showed. Else
  // there or gone at once. One that makes its way kept among its ways (Places) till that ends.
  // (the slot of key `k`, by its key while it is made: as tall as it is now)
  let slot_views : Map[K, View] = Map([])
  let slot_tall = fn(k : K) {
    match slot_views.get(k) {
      Some(v) if v.alive() => self.tree.along_now(v.at, self.tree.cause_now())
      _ => 0.0
    }
  }
  // (how tall a block come at its foot sets out from: all the room under the last block, that one gone in its place
  // in the same change counted in it, the room none from then; measured shorter than that, from as tall as it is, the
  // rest of the room left: so the column is as tall as it was at that moment, and what is over it goes up by no more
  // than it needs past the room)
  // (the same where it comes with no way (there at once: motion reduced, or not seen to come): the room less by as tall
  // as it is, in the fill that measures it)
  let take_room = fn(k : K, row : View) -> Double {
    let quiet = gone_quiet.keys().filter(fn(g) { gone_quiet.get(g) == Some(false) }).collect()
    for g in quiet {
      gone_quiet[g] = true
      floor_raise()
      foot_room.set(foot_room.untracked() + slot_tall(g))
    }
    let r = foot_room.untracked()
    guard r > 0.0 && came_by_data.val.contains(k) else { return 0.0 }
    foot_room.set(0.0)
    took_room[k] = (row, r)
    r
  }
  let from_of = fn(k : K, row : View) -> Double { take_room(k, row) }
  // (a key gone leaving its room: what it showed fading out where it is, as a pick's that leaves (pick_leave.mbt), its
  // slot as tall as it is till that and its way in are done, then let go; back, seen again whole)
  let fade_off = Ref(fn() {  })
  let faded : Array[View] = []
  fade_undo.val = fn(k) {
    for b in blocks {
      if b.0.alive() && @signals.untracked(b.1) == k {
        b.0.alpha(Is(1.0)) |> ignore
      }
    }
  }
  fade_go.val = fn(k) {
    guard fading.val is Some((f, went)) && f == k else { return }
    for b in blocks {
      if b.0.alive() && @signals.untracked(b.1) == k {
        let v = b.0
        let key = b.1
        faded.push(v)
        // (by the key it holds: a block put by and taken for another key meanwhile seen whole)
        v.alpha(
          By(fn() {
            guard key() == k && fading.val is Some((f, _)) && f == k else { return 1.0 }
            let t = v.drawn_while(fn(now) { now < went + list_leaves_ms })
            1.0 - leave_eased((t - went) / list_leaves_ms)
          }),
        )
        |> ignore
      }
    }
    // (as long as that, and as its way in has still to go)
    let mut end = went + list_leaves_ms
    for w in ways {
      if w.1 == k && w.0.live() is Some(m) && m.coming {
        let e = m.flex.style.come_ends
        if e == e && e > end {
          end = e
        }
      }
    }
    (fade_off.val)()
    fade_off.val = self.at_moment(end, fn() {
      guard fading.val is Some((f, _)) && f == k else { return }
      fading.val = None
      // (what was faded and is still there, whole again: let go now, or put by and taken for another key)
      for v in faded {
        if v.alive() {
          v.alpha(Is(1.0)) |> ignore
        }
      }
      faded.clear()
      gone_quiet[k] = false
      fade_rev.set(fade_rev.untracked() + 1)
    })
  }
  self.owns(fn() { (fade_off.val)() }) |> ignore
  // (the room under the last block no more than still showed of it as the list goes back down to it once scrolled
  // up off it: read up by less than the room, off its foot by as much, and on the way back at its foot with what still
  // showed; the scroll read only while there is one; not while what was pressed holds it, as the fill keeps it then)
  let room_x : Ref[Double?] = Ref(None)
  self.reacts(fn() {
    guard foot_room.get() > 0.0 else { return None }
    // (where it comes to rest: where a wheel's notch eases to, else where it is)
    match s.notch.get() {
      Some(nt) if s.fling.get() is None && s.edge.get() is None => Some(nt.x0 + nt.total)
      _ => Some(at())
    }
  }, fn(x) {
    // (at its foot, followed: where it is drawn moves with the room it shows in, no hand's; off it, where it was, and
    // so where it went back down from, at its foot again or not)
    guard x is Some(x) else {
      room_x.val = None
      return
    }
    let was = room_x.val
    room_x.val = if s.at_foot() { None } else { Some(x) }
    guard was is Some(w) && x > w + 0.000001 else { return }
    guard !(pin.val is Some((k, _, _, _)) && laid_at.contains(k)) else { return }
    guard s.seen.untracked() is Some((_, vh)) && vh > 0.0 else { return }
    let all = places(laid.untracked())
    let left = dmax(0.0, top_now(all, w) + vh - blocks_foot(all))
    if left < foot_room.untracked() {
      foot_room.set(left)
    }
  })
  let way_of = fn(k : K, row : View, coming : Bool) -> Bool {
    let ok = @signals.untracked(fn() {
      guard !at_once && s.seen.get() is Some((_, vh)) && vh > 0.0 else { return false }
      if coming {
        let col = laid.get()
        guard came_by_data.val.contains(k) && laid_at.get(k) is Some(i) && i < col.length() else {
          return false
        }
        let all = places(col)
        if s.at_foot() {
          let end = counted(col)
          end.top(i) + end.h(i) > dmax(0.0, whole_of(end) - vh)
        } else {
          let top = top_now(all, at())
          let under = match held_at(all) {
            Some((a, _)) => i > a
            None => true
          }
          under && all.top(i) < top + vh
        }
      } else {
        match gone_from.val.get(k) {
          Some((off, _)) => s.at_foot() || (off >= 0.0 && off < vh)
          None => false
        }
      }
    })
    // (gone leaving its room: at once, the room under the last block as tall as it was, where not counted already)
    match gone_quiet.get(k) {
      Some(counted) if !coming => {
        gone_quiet.remove(k)
        if !counted {
          floor_raise()
          let h = self.tree.along_now(row.at, self.tree.cause_now())
          foot_room.set(foot_room.untracked() + h)
        }
        return false
      }
      _ => ()
    }
    // (come at its foot with no way: it takes the room all the same, there at once)
    if coming && !ok && @signals.untracked(fn() { s.at_foot() }) {
      take_room(k, row) |> ignore
    }
    if ok {
      let left = ways.filter(fn(w) { w.0.at != row.at })
      ways.clear()
      ways.append(left)
      ways.push((row, k, if coming { None } else { gone_from.val.get(k).bind(fn(g) { g.1 }) }))
      // (waited for once its end is said: this is asked before the each sets the row off (View::comes), which queues
      // its own wait for the change told whole, the change's layout that measures it and its column's group then; this
      // one queued after those, a wait inside a wait, so that it reads the end they said)
      @signals.after_flush(fn() { @signals.after_flush(fn() { (ways_due.val)() }) })
    }
    ok
  }
  let out = self.scrolls(s, slop?=slop, bar?=bar, bar_clear~, fn(held) {
    held.padding(By(fn() { (0.0, 0.0, 0.0, room_under() + s.tuck_room.get() + foot_room.get()) })) |> ignore
    // (what its blocks hold that comes or goes down a column in them: kept, how long a press there set off goes, and in
    // its one way unless it is said at once)
    held.list_keeps_inner(held.at, !at_once)
    held_node.val = held.at
    // (short of what shows, its blocks at its foot: at least as tall as the room it shows them in, they at its end; with
    // a head, the head at its top, the room left under it, over its blocks)
    if from_end {
      held.min_height_share(Is(Some(1.0))) |> ignore
      if head is None {
        held.lies_along(Is(Lies::End)) |> ignore
      }
    }
    // (its head, over its keys' blocks, as tall as what the page builds in it: where its keys start, its fill measuring it)
    match head {
      Some(make_head) =>
        // (as tall as where its keys start, what the page builds in it at its top)
        held.box(fn(o) {
          o.height(By(fn() { Some(head_tall.get()) })).shrink(Is(0.0)) |> ignore
          o.box(fn(h) {
            h.shrink(Is(0.0)) |> ignore
            head_v.val = Some(h)
            make_head(h)
          })
          |> ignore
        })
        |> ignore
      None => ()
    }
    // (over the slots, as tall as the blocks over them are counted: on the grid, as their tops are)
    held.box(fn(o) {
      if from_end && head is Some(_) {
        o.grow(Is(1.0)) |> ignore
      }
      o
      .height(By(fn() {
        let all = laid.get()
        match slot_keys.get().get(0) {
          Some(k) =>
            match laid_at.get(k) {
              Some(i) if i < all.length() => Some(all.top(i) - all.start)
              _ => Some(0.0)
            }
          None => Some(0.0)
        }
      }))
      .shrink(Is(0.0))
      |> ignore
    })
    |> ignore
    held.each_by(fn() { slot_keys.get() }, fn(k) { k }, way_of~, from_of~, fn(slot, item) {
      let k = item.untracked()
      let cell = @signals.signal(shown_now.contains(k), same=fn(a, b) { a == b })
      shown[k] = cell
      slot.owns(fn() { if shown.get(k) is Some(c) && physical_equal(c, cell) { shown.remove(k) } }) |> ignore
      let shows = fn() { cell.get() }
      // (its slot by its key, while it is: how tall it is now, as its room is taken, slot_tall)
      slot_views[k] = slot
      slot.owns(fn() { if slot_views.get(k) is Some(v) && physical_equal(v, slot) { slot_views.remove(k) } }) |> ignore
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
                  Some((v, key, wake, Some(was_in))) if v.alive() && physical_equal(was_in, slot) => {
                    showing[k] = true
                    // (a block given another key: what that makes or lets go in it so at once, key_taken.mbt)
                    key_taking_set(slot.tree, v.id())
                    key.set(k)
                    wake()
                    mine.val = Some((v, key))
                  }
                  // (in another's slot, out of sight there, or held by no node since that slot left what has slots: taken
                  // into this one, made this one's)
                  Some((v, key, wake, was_in)) if v.alive() => {
                    match was_in {
                      Some(w) => w.park(v) |> ignore
                      None => ()
                    }
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
                  let wake = v.rests()
                  // (its key gone from the list: let go with its slot, as were every slot kept)
                  if slot_keys.untracked().contains(k) || !laid_at.contains(k) {
                    all.push((v, key, wake, Some(slot)))
                  } else {
                    // (its slot no more among those kept (found anew in the same change, let go as it is told): taken
                    // out of it first, held by no node, so the slot's going lets go none of it)
                    slot.park(v) |> ignore
                    all.push((v, key, wake, None))
                  }
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
                match all.search_by(fn(b) { b.3 is Some(w) && physical_equal(w, slot) }) {
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
    })
    // (under the slots, as tall as the blocks under them are counted)
    held.box(fn(o) {
      o
      .height(By(fn() {
        let all = laid.get()
        let foot = counted(all).foot()
        match slot_keys.get().last() {
          Some(k) =>
            match laid_at.get(k) {
              Some(i) if i < all.length() => Some(dmax(0.0, foot - (all.top(i) + all.h(i))))
              _ => Some(foot - all.start)
            }
          None => Some(foot - all.start)
        }
      }))
      .shrink(Is(0.0))
      |> ignore
    })
    |> ignore
  })
  // (its foot: pinned at the foot of what shows, over what scrolls (drawn after it, what is under it its own), as wide
  // as the list; as tall as what the page builds in it, its fill measuring it, the room kept under its last block)
  match foot {
    Some(make_foot) =>
      self.box(fn(f) {
        let fs = self.tree.nodes[f.at].flex.style
        fs.position = @flex.PositionType::Absolute
        fs.set_inset_left(Pt(0.0))
        fs.set_inset_right(Pt(0.0))
        fs.set_inset_bottom(Pt(0.0))
        fs.set_inset_top(Auto)
        // (as tall as the room under the last block, on the grid: what the page builds in it at its top, as the head's)
        f.height(By(fn() { Some(foot_h.get()) })).shrink(Is(0.0)) |> ignore
        // (what comes, goes or resizes in it goes in the list's one way, as what its blocks hold does, unless it is said
        // at once: Tree::come_group_join by Tree's list_feet)
        if !at_once && held_node.val >= 0 {
          let tree = self.tree
          let at = f.at
          tree.list_feet[at] = held_node.val
          f.owns(fn() { tree.list_feet.remove(at) }) |> ignore
        }
        f.box(fn(i) {
          i.shrink(Is(0.0)) |> ignore
          foot_v.val = Some(i)
          make_foot(i)
        })
        |> ignore
      })
      |> ignore
    None => ()
  }
  // (those put by let go with the list: held by nothing, let go by nothing else)
  self.owns(spare_let_go) |> ignore
  out
}

///|
/// How far past where a page's list shows, in its heights, its slots reach over and under as they are found again
/// (View::scrolls_window): a screen, so that what a hand's move or a wheel's turn brings in is there already.
let slots_margin : Double = 1.0

///|
/// How near where a page's list shows comes to its slots' end, in its heights, before they are found again: half the
/// margin, so they are widened before what shows reaches their end, not as it does.
let slots_near : Double = 0.5

///|
/// How far past where a page's list shows its slots may reach, in its heights, before they are found again narrower:
/// twice the margin, so that a wheel going back and forth over where they end widens once and narrows never.
let slots_far : Double = 2.0

///|
/// How many blocks of one kind a list keeps put by (View::scrolls_window's `reused`): as many as come to show at once
/// as it is scrolled, the rest let go.
let spare_most : Int = 4

///|
/// How long what a key gone leaving its room showed takes to fade out where it is (View::scrolls_window's
/// `leaves_room`): as what goes from a list (the app's leave_ms), its fade alone.
let list_leaves_ms : Double = 200.0

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
  /// what is told what is in sight as that changes (ListPlace::on_sight), what was told last (ListPlace::sight_now),
  /// and what its list has in sight as it is counted now (none before it is made)
  priv sight_fns : Array[(Sight[K]) -> Unit]
  priv mut sight : Sight[K]?
  priv mut sight_of : () -> Sight[K]?
  priv mut sight_listened : () -> Unit
}

///|
/// One for a page's list, asking nothing yet.
pub fn[K] ListPlace::new() -> ListPlace[K] {
  { asked: None, from: None, laid_again: fn() {  }, glide: fn(_) { false }, sight_fns: [], sight: None, sight_of: fn() { None }, sight_listened: fn() {  } }
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
