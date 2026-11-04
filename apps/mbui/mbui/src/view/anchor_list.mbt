// A long list laid out from its anchor (retained.md rule 11; Compose's LazyListState and LazyListMeasure, laid out
// reversed as Flutter's `reverse` and Compose's `reverseLayout` are): where it is scrolled to is a row's key and how far
// that row's foot is under the window's, and each layout measures rows out from it, the anchor's first, till the window
// and a little more over and under it is filled. No row off that is measured or gone through: what it costs is what
// shows, whatever the list's length. At its end the anchor is the newest row, 0 under the foot.

///|
/// Where a list laid out from its end is: the row whose foot is the nearest under the window's foot, or at it (`key`),
/// how far its foot is under the window's (`under`, 0 or more: what of it is past the foot), and its index as it was
/// last laid out (`near`, where its key is looked for first). None: at the end.
pub(all) struct ListAnchor[K] {
  key : K
  under : Double
  near : Int
} derive(Eq)

///|
/// What one layout of the list measured and placed: the rows from `first` to `last` (indexes, `last` the newest one
/// placed), each one's top in the window (its foot's distance from the window's top: `tops[i - first]` and
/// `heights[i - first]`), and where it is now (`anchor`, None at its end). `start`/`end`: whether its first and last rows
/// are among them, the oldest row's top and the newest's foot where they are.
pub(all) struct ListLaid[K] {
  first : Int
  last : Int
  keys : Array[K]
  tops : Array[Double]
  heights : Array[Double]
  anchor : ListAnchor[K]?
  at_start : Bool
  at_end : Bool
} derive(Eq)

///|
/// Lay out the list of `n` rows (`key(i)`, oldest first) from `anchor` in a window `h` tall, scrolled `by` more toward
/// its start (what it holds moves down: older rows come in over it; negative, toward its end), each row's height
/// `measure(i)` as it is laid out, and `ahead` more over and under the window measured too (made ahead of being in
/// sight). `find(key, near)` is where a key is, looked for from near where it was; one gone, the anchor goes to the row
/// near where it was. A list shorter than the window lies at its foot; one scrolled past its start is held there, past
/// its end at its end.
pub fn[K : Eq] list_laid_from_end(
  n : Int,
  key : (Int) -> K,
  find : (K, Int) -> Int?,
  measure : (Int) -> Double,
  anchor : ListAnchor[K]?,
  h : Double,
  by? : Double = 0.0,
  ahead? : Double = 0.0,
  known? : (Int) -> Double? = fn(_) { None },
  slack? : Double = 0.0,
) -> ListLaid[K] {
  if n == 0 {
    return { first: 0, last: -1, keys: [], tops: [], heights: [], anchor: None, at_start: true, at_end: true }
  }
  // (the anchor's row and how far its foot is under the window's, scrolled `by`)
  let (start_i, start_under) = match anchor {
    None => (n - 1, 0.0)
    Some(a) =>
      match find(a.key, a.near) {
        Some(i) => (i, a.under)
        None => (if a.near < n { if a.near < 0 { 0 } else { a.near } } else { n - 1 }, a.under)
      }
  }
  let mut under = start_under + by
  let measured : Map[Int, Double] = Map([])
  let height_of = fn(i : Int) {
    match measured.get(i) {
      Some(v) => v
      None => {
        let v = measure(i)
        measured[i] = v
        v
      }
    }
  }
  // (a row only gone past on the way to the anchor, as tall as it was last measured: not made again for it)
  let passed = fn(i : Int) {
    match measured.get(i) {
      Some(v) => v
      None =>
        match known(i) {
          Some(v) => v
          None => height_of(i)
        }
    }
  }
  let mut i = start_i
  // (scrolled toward its end, the anchor's foot over the window's: the newer rows under it come into the window, the
  // newest's foot held at the foot)
  while under < 0.0 && i < n - 1 {
    i = i + 1
    under = under + passed(i)
  }
  if under < 0.0 {
    under = 0.0
  }
  // (scrolled toward its start: a row wholly under the foot is no more the anchor, the one over it is)
  while i > 0 && under >= passed(i) {
    under = under - passed(i)
    i = i - 1
  }
  // (from the anchor's foot up, each row over the one before, till the window's top and `ahead` over it)
  let up_tops : Array[Double] = []
  let mut foot = h + under
  let mut j = i
  while j >= 0 && foot > -ahead {
    foot = foot - height_of(j)
    up_tops.push(foot)
    j = j - 1
  }
  let first = j + 1
  // (its start come in the window under its top: held at the top, the rows under the anchor drawn up under it as far
  // as there are any; all it holds shorter than the window, at the foot, at its end)
  let mut shift = 0.0
  // (`slack` of it may show past its start: room kept there for a row tucked out of sight, list_laid_from_top's)
  if first == 0 && foot > slack {
    let mut past = under
    let mut k = i
    while past < foot - slack && k < n - 1 {
      k = k + 1
      past = past + height_of(k)
    }
    shift = dmin(foot - slack, past)
  }
  under = under - shift
  let keys : Array[K] = []
  let tops : Array[Double] = []
  let heights : Array[Double] = []
  for q in 0..<up_tops.length() {
    let r = up_tops.length() - 1 - q
    let at = i - r
    keys.push(key(at))
    tops.push(up_tops[r] - shift)
    heights.push(height_of(at))
  }
  // (and the rows under the anchor, in the window or `ahead` under it)
  let mut last = i
  let mut top = h + under
  while last < n - 1 && top < h + ahead {
    last = last + 1
    let hl = height_of(last)
    keys.push(key(last))
    tops.push(top)
    heights.push(hl)
    top = top + hl
  }
  // (the anchor again: the row whose foot is the nearest under the window's foot, or at it)
  let mut a = -1
  for q in 0..<keys.length() {
    if tops[q] + heights[q] >= h - 0.001 {
      a = q
      break
    }
  }
  let anchor = if a < 0 {
    None
  } else {
    let ai = first + a
    let au = tops[a] + heights[a] - h
    if ai == n - 1 && au <= 0.001 { None } else { Some({ key: keys[a], under: dmax(0.0, au), near: ai }) }
  }
  {
    first,
    last,
    keys,
    tops,
    heights,
    anchor,
    at_start: first == 0 && tops.length() > 0 && tops[0] >= -0.001,
    at_end: anchor is None,
  }
}

///|
/// The same laid out from its start (a page's list, the chats'): its anchor the row whose top is the nearest over the
/// window's top, or at it, and how far its top is over the window's (`under`); none at its start. What it holds lies
/// at the window's top where it is shorter; `by` scrolls it toward its end (what it holds moves up). Its result as
/// list_laid_from_end's, its rows from the oldest down: `at_end` there is at its start here (where it rests), and
/// `at_start` at its end.
pub fn[K : Eq] list_laid_from_top(
  n : Int,
  key : (Int) -> K,
  find : (K, Int) -> Int?,
  measure : (Int) -> Double,
  anchor : ListAnchor[K]?,
  h : Double,
  by? : Double = 0.0,
  ahead? : Double = 0.0,
  known? : (Int) -> Double? = fn(_) { None },
  slack? : Double = 0.0,
) -> ListLaid[K] {
  // (the same list turned over: its last row its first, its foot its top)
  let m = fn(i : Int) { n - 1 - i }
  let r = list_laid_from_end(
    n,
    fn(i) { key(m(i)) },
    fn(k, near) { find(k, m(near)).map(m) },
    fn(i) { measure(m(i)) },
    anchor.map(fn(a) { { ..a, near: m(a.near) } }),
    h,
    by~,
    ahead~,
    known=fn(i) { known(m(i)) },
    slack~,
  )
  let count = r.keys.length()
  let keys = []
  let tops = []
  let heights = []
  for q in 0..<count {
    let p = count - 1 - q
    keys.push(r.keys[p])
    heights.push(r.heights[p])
    tops.push(h - r.tops[p] - r.heights[p])
  }
  {
    first: m(r.last),
    last: m(r.first),
    keys,
    tops,
    heights,
    anchor: r.anchor.map(fn(a) { { ..a, near: m(a.near) } }),
    at_start: r.at_start,
    at_end: r.at_end,
  }
}
