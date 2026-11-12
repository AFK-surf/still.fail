// A page's list's blocks as they are counted (list_window.mbt's Column): where each one's top is, and which is the
// first whose foot is past a place, a function of the heights as they are now and of how many there are, the same to
// the bit whatever order they were measured in, and after a height changed and changed back as if it never had.

///|
/// Key `k`'s height: no binary fraction.
fn heights_of(k : Int) -> Double {
  match k % 4 {
    0 => 40.0 * 1.3
    1 => 51.7
    2 => 63.1
    _ => 22.9
  }
}

///|
/// A column of `n` keys counted 80 each, then told each one's height in the order `order` says, on the grid `g`.
fn heights_told(n : Int, order : Array[Int], g : Double) -> Column[Int] {
  let c : Column[Int] = Column::new()
  c.fill(Array::makei(n, fn(i) { i }), Array::make(n, (rows_slot_on(80.0, g), false)), g)
  for k in order {
    c.set(k, rows_slot_on(heights_of(k), g), true)
  }
  c
}

///|
/// Each top's bits, and the first past each of a sweep of places (and just either side of each top).
fn heights_read(c : Column[Int]) -> (Array[Int64], Array[Int]) {
  let tops = Array::makei(c.length(), fn(i) { c.top(i).reinterpret_as_int64() })
  let pasts = []
  let mut y = -3.0
  while y < c.top(c.length() - 1) + 100.0 {
    pasts.push(c.first_past(y))
    y = y + 7.3
  }
  for i in 0..<c.length() {
    let t = c.top(i)
    pasts.push(c.first_past(t))
    pasts.push(c.first_past(t - 0.000001))
    pasts.push(c.first_past(t + 0.000001))
  }
  (tops, pasts)
}

///|
test "a list's blocks' heights told first to last, last to first and shuffled: every top and every first past a place the same to the bit, on no grid, on 2.75 and on 3.5" {
  for g in [0.0, 2.75, 3.5] {
    for n in [1, 2, 3, 300, 1500] {
      let down = heights_read(heights_told(n, Array::makei(n, fn(i) { i }), g))
      let up = heights_read(heights_told(n, Array::makei(n, fn(i) { n - 1 - i }), g))
      let shuffled = heights_read(heights_told(n, Array::makei(n, fn(i) { i * 7919 % n }), g))
      assert_true(down == up, msg="on \{g}, \{n} keys: told last to first")
      assert_true(down == shuffled, msg="on \{g}, \{n} keys: told shuffled")
    }
  }
}

///|
test "a list's block's height changed and changed back: every top and every first past a place as if it never had, to the bit" {
  for g in [0.0, 2.75, 3.5] {
    let n = 300
    let kept = heights_told(n, Array::makei(n, fn(i) { i }), g)
    let moved = heights_told(n, Array::makei(n, fn(i) { i }), g)
    for k in [0, 7, 150, 299] {
      moved.set(k, rows_slot_on(heights_of(k) + 17.31, g), true)
      moved.set(k, rows_slot_on(80.0, g), false)
    }
    for k in [0, 7, 150, 299] {
      moved.set(k, rows_slot_on(heights_of(k), g), true)
    }
    assert_true(heights_read(kept) == heights_read(moved), msg="on \{g}: changed and changed back")
  }
}

///|
test "a list's blocks counted: on a grid each top the grid's own number for its pixel, each foot no higher than the next one's" {
  for g in [2.75, 3.5] {
    let c = heights_told(1500, Array::makei(1500, fn(i) { i * 7919 % 1500 }), g)
    let off = []
    for i in 0..<c.length() {
      let t = c.top(i)
      if t.reinterpret_as_int64() != ((t * g).round() / g).reinterpret_as_int64() {
        off.push((i, t))
      }
      if i + 1 < c.length() && c.top(i + 1) < t + c.hs[i] - 0.000001 {
        off.push((i, t))
      }
    }
    assert_eq(off, [], msg="on \{g}")
  }
}

///|
/// Column `c` filled again for `keys` as the list fills it (View::scrolls_window's `laid`): kept up to the first key
/// that is another, each height from there put anew.
fn heights_refilled(c : Column[Int], keys : Array[Int], g : Double) -> Unit {
  let p = c.refill(keys, g)
  for i in p..<keys.length() {
    c.put(i, rows_slot_on(heights_of(keys[i]), g), true)
  }
  c.summed()
}

///|
/// A column filled whole for `keys`, each its height.
fn heights_whole(keys : Array[Int], g : Double) -> Column[Int] {
  let c : Column[Int] = Column::new()
  c.fill(keys, keys.map(fn(k) { (rows_slot_on(heights_of(k), g), true) }), g)
  c
}

///|
test "a list's keys changed, kept up to the first that is another: after appends, a page put before the first, one replaced and one taken out, every top and every first past a place as filled whole, to the bit" {
  for g in [0.0, 2.75, 3.5] {
    let c : Column[Int] = Column::new()
    let mut keys = Array::makei(500, fn(i) { i })
    heights_refilled(c, keys, g)
    let wrong = []
    // (one at a time past 512, where the tree grows a level)
    for a in 500..<520 {
      keys = keys + [a]
      heights_refilled(c, keys, g)
      if heights_read(c) != heights_read(heights_whole(keys, g)) {
        wrong.push("appended \{a}")
      }
    }
    keys = Array::makei(50, fn(i) { -50 + i }) + keys
    heights_refilled(c, keys, g)
    if heights_read(c) != heights_read(heights_whole(keys, g)) {
      wrong.push("a page put before the first")
    }
    keys = keys.mapi(fn(i, k) { if i == 260 { 10000 } else { k } })
    heights_refilled(c, keys, g)
    if heights_read(c) != heights_read(heights_whole(keys, g)) {
      wrong.push("one replaced in the middle")
    }
    keys = keys.filter(fn(k) { k != 100 })
    heights_refilled(c, keys, g)
    if heights_read(c) != heights_read(heights_whole(keys, g)) {
      wrong.push("one taken out")
    }
    keys = keys.filter(fn(k) { k < 400 })
    heights_refilled(c, keys, g)
    if heights_read(c) != heights_read(heights_whole(keys, g)) {
      wrong.push("its last ones taken out, the tree a level less")
    }
    assert_eq(wrong, [], msg="on \{g}")
  }
}

///|
/// All of it again: `keys`, each with its height as laid out on the grid of `g` pixels a point and whether it was laid
/// out.
fn[K : Eq] Column::fill(self : Column[K], keys : Array[K], hs : Array[(Double, Bool)], g : Double) -> Unit {
  self.refill(keys, g, whole=true) |> ignore
  for i, h in hs {
    self.put(i, h.0, h.1)
  }
  self.summed()
}
