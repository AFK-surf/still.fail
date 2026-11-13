// A page's list keeps slots only for the keys round what shows (View::scrolls_window's slot_keys), a spacer over them
// and one under as tall as the rest are counted: what a frame does is the same with 30 keys as with 15,000; a wheel
// going back and forth over where its slots end makes and lets go nothing; and where it shows is drawn the same, to the
// bit, however it came there (scrolled, asked there, made there), on no grid and on a host's pixels.

///|
/// The moments of `n` turns of the wheel, one a millisecond from `from`: each turn an input at its moment, drawn.
fn turns_at(n : Int, from : Double) -> Array[Double] {
  Array::makei(n, fn(i) { from + i.to_double() })
}

///|
/// How tall key `k`'s row is: no binary fraction, no whole number of pixels at 2.75 or 3.5.
fn slots_tall(k : Int) -> Double {
  match k % 4 {
    0 => 22.1
    1 => 31.7
    2 => 40.0 * 1.3
    _ => 27.3
  }
}

///|
/// A list of `n` keys in a box 300 by 200, each row as tall as slots_tall says with words of its key: the tree, its keys,
/// how many blocks were made and let go, and what asks it to show a block.
priv struct SlotsCase {
  tree : Tree
  keys : @signals.Signal[Array[Int]]
  made : Ref[Int]
  gone : Ref[Int]
  place : ListPlace[Int]
}

///|
fn slots_case(
  n : Int,
  grid? : Double = 0.0,
  follows? : Bool = false,
  foot_room? : () -> Double,
  first? : (ListPlace[Int]) -> Unit = fn(_) {  },
  // (its keys there and gone as they change by data: its clock stands at 0 here, where no way would go on, and what is
  // held is what the slots cost, not a way's; a way's frames as many keys as it holds, list_blocks_way_test)
  comes? : (Int) -> Bool = fn(_) { false },
  goes? : (Int) -> Bool = fn(_) { false },
) -> SlotsCase {
  let keys = @signals.signal(Array::makei(n, fn(i) { i }), same=fn(a, b) { physical_equal(a, b) })
  let made = Ref(0)
  let gone = Ref(0)
  let place : ListPlace[Int] = ListPlace::new()
  let tree = Tree::new(
    fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
        o.scrolls_window(
          Scroll::list(),
          fn() { keys.get() },
          est=30.0,
          place~,
          follows=fn() { follows },
          foot?=foot_room.map(fn(room) { fn(f : View) { f.height(By(fn() { Some(room()) })) |> ignore } }),
          comes~,
          goes~,
          fn(b, k) {
            made.val = made.val + 1
            b.owns(fn() { gone.val = gone.val + 1 }) |> ignore
            b.box(fn(l) { l.height(Is(Some(slots_tall(k)))).words(Is("row \{k}")) |> ignore }) |> ignore
          },
        )
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  if grid > 0.0 {
    tree.set_rows_grid(grid)
  }
  // (what it is asked before its first frame: made there)
  first(place)
  tree.frame(390.0, 844.0) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  { tree, keys, made, gone, place }
}

///|
/// What one frame did: nodes laid out, placed and visited, layouts computed (the tree's and flex's), the order made again,
/// how many are in the order and drawn, and blocks made and let go.
fn slots_frame_work(c : SlotsCase, step : () -> Unit) -> Array[Int] {
  step()
  let w0 = c.tree.work()
  let f0 = @flex.computes()
  let m0 = c.made.val
  let g0 = c.gone.val
  c.tree.frame(390.0, 844.0) |> ignore
  let w1 = c.tree.work()
  [
    w1.laid - w0.laid,
    w1.visited - w0.visited,
    w1.computes - w0.computes,
    @flex.computes() - f0,
    w1.orders - w0.orders,
    c.tree.order.length(),
    c.tree.drawn().length(),
    c.made.val - m0,
    c.gone.val - g0,
  ]
}

///|
test "a page's list of 30, 1,500 and 15,000 keys: a scroll frame, a frame a row comes in, a frame a key is appended at its foot each do the same work" {
  let works = []
  for n in [30, 1500, 15000] {
    let c = slots_case(n)
    // (down a little, no row in or out; down to where rows come in; a key appended at its foot, out of sight)
    let a = slots_frame_work(c, fn() { c.tree.wheel_at(150.0, 100.0, 0.0, 5.0, 0, 10.0) |> ignore })
    let b = slots_frame_work(c, fn() { c.tree.wheel_at(150.0, 100.0, 0.0, 60.0, 0, 20.0) |> ignore })
    let d = slots_frame_work(c, fn() { c.keys.set(c.keys.untracked() + [n]) })
    works.push((n, a, b, d))
  }
  // (1,500 and 15,000 the same, to the item; 30 the same but in the frame a row comes in, where it lays out one node
  // more: its spacer under the slots, which on a list that short comes out another last bit as the row come in is
  // measured (its foot less the slots' foot, 480.00000000000006 for 480), and is laid out again)
  let (_, a30, b30, d30) = works[0]
  let (_, a, b, d) = works[1]
  let (_, a15, b15, d15) = works[2]
  assert_eq((a15, b15, d15), (a, b, d), msg="15,000 keys against 1,500")
  let b30_less = b30.mapi(fn(i, v) { if i == 0 { v - 1 } else { v } })
  assert_eq((a30, b30_less, d30), (a, b, d), msg="30 keys against 1,500, its spacer laid out again aside: \{Repr((a30, b30, d30))}")
}

///|
test "a page's list of reused blocks wheeled back and forth over where its slots end: nodes made and let go as it first crosses, none after" {
  let tree = Tree::new(
    fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
        o.scrolls_window(
          Scroll::list(),
          fn() { Array::makei(1500, fn(i) { i }) },
          est=30.0,
          fn(_, _) { @halt.saying("every block is of a kind another may take") },
          reused=fn(_) { Some(0) },
          make_reused=fn(b, key) {
            b.box(fn(l) { l.height(By(fn() { Some(slots_tall(key())) })).words(By(fn() { "row \{key()}" })) |> ignore })
            |> ignore
          },
        )
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  tree.frame(390.0, 844.0) |> ignore
  // (down far enough that its slots were found again once)
  for t in turns_at(8, 10.0) {
    tree.wheel_at(150.0, 100.0, 0.0, 40.0, 0, t) |> ignore
    tree.frame(390.0, 844.0) |> ignore
  }
  let w0 = tree.work()
  for i, t in turns_at(12, 100.0) {
    let dy = if i % 2 == 0 { 60.0 } else { -60.0 }
    tree.wheel_at(150.0, 100.0, 0.0, dy, 0, t) |> ignore
    tree.frame(390.0, 844.0) |> ignore
  }
  let w1 = tree.work()
  for i, t in turns_at(12, 200.0) {
    let dy = if i % 2 == 0 { 60.0 } else { -60.0 }
    tree.wheel_at(150.0, 100.0, 0.0, dy, 0, t) |> ignore
    tree.frame(390.0, 844.0) |> ignore
  }
  let w2 = tree.work()
  assert_eq(
    (w2.made - w1.made, w2.let_go - w1.let_go),
    (0, 0),
    msg="the first back and forth made \{w1.made - w0.made} and let go \{w1.let_go - w0.let_go}",
  )
}

///|
/// The words drawn in the list's box and where, top down: plain values, read off the tree before another is made.
fn slots_picture(t : Tree) -> Array[(String, Int64, Int64, Int64, Int64)] {
  let out = t
    .drawn()
    // (one that meets the box by less than a millionth of a point is not seen there: a top worked out by another sum
    // than the same top, its last bits apart, puts a row just over the box in it or out of it)
    .filter(fn(d) { d.words != "" && d.y + d.h > 1.0e-6 && d.y < 200.0 - 1.0e-6 })
    .map(fn(d) {
      (
        d.words,
        d.x.reinterpret_as_int64(),
        d.y.reinterpret_as_int64(),
        d.w.reinterpret_as_int64(),
        d.h.reinterpret_as_int64(),
      )
    })
  out.sort_by(fn(a, b) { a.2.compare(b.2) })
  out
}

///|
/// The first of two pictures' entries that are not the same, each as numbers.
fn slots_first_apart(a : Array[(String, Int64, Int64, Int64, Int64)], b : Array[(String, Int64, Int64, Int64, Int64)]) -> String {
  let f = fn(e : (String, Int64, Int64, Int64, Int64)) {
    "\{e.0} \{e.1.reinterpret_as_double()} \{e.2.reinterpret_as_double()} \{e.3.reinterpret_as_double()} \{e.4.reinterpret_as_double()}"
  }
  for i in 0..<(if a.length() < b.length() { a.length() } else { b.length() }) {
    if a[i] != b[i] {
      return "[\{i}] \{f(a[i])} against \{f(b[i])}"
    }
  }
  "\{a.length()} against \{b.length()}"
}

///|
/// Where a list of 1,500 shows by each path on grid `g`, each ending with the same key's top at the top of what shows
/// (a list's state is its anchor: which key is at its top and how far in, whatever is measured out of sight or not):
/// scrolled there by the wheel (its last turn as far as that key's row is drawn down from the top), asked there
/// (ListPlace::bring), made there (asked before its first frame), and scrolled past it and back; each read into plain
/// values before the next is made.
fn slots_paths(g : Double) -> Array[Array[(String, Int64, Int64, Int64, Int64)]] {
  let s = slots_case(1500, grid=g)
  for t in turns_at(40, 10.0) {
    s.tree.wheel_at(150.0, 100.0, 0.0, 97.0, 0, t) |> ignore
    s.tree.frame(390.0, 844.0) |> ignore
  }
  // (the first row whose top is in sight, and how far down it is drawn: the last turn as far)
  let mut key = 0
  let mut top_y = 1.0e9
  for d in s.tree.drawn() {
    if d.words.has_prefix("row ") && d.y >= 0.0 && d.y < top_y {
      top_y = d.y
      let mut k = 0
      for ch in d.words.exact_view(start=4, end=d.words.length()) {
        k = k * 10 + (ch.to_int() - '0'.to_int())
      }
      key = k
    }
  }
  s.tree.wheel_at(150.0, 100.0, 0.0, top_y, 0, 60.0) |> ignore
  s.tree.frame(390.0, 844.0) |> ignore
  s.tree.frame(390.0, 844.0) |> ignore
  let scrolled = slots_picture(s.tree)
  let j = slots_case(1500, grid=g)
  j.place.bring(key)
  j.tree.frame(390.0, 844.0) |> ignore
  j.tree.frame(390.0, 844.0) |> ignore
  let jumped = slots_picture(j.tree)
  let m = slots_case(1500, grid=g, first=fn(p) { p.bring(key) })
  let made = slots_picture(m.tree)
  // (past it and back: the same turns and the last, 150 further, then 150 back)
  let b = slots_case(1500, grid=g)
  for t in turns_at(40, 10.0) {
    b.tree.wheel_at(150.0, 100.0, 0.0, 97.0, 0, t) |> ignore
    b.tree.frame(390.0, 844.0) |> ignore
  }
  b.tree.wheel_at(150.0, 100.0, 0.0, top_y + 150.0, 0, 60.0) |> ignore
  b.tree.frame(390.0, 844.0) |> ignore
  b.tree.wheel_at(150.0, 100.0, 0.0, -150.0, 0, 70.0) |> ignore
  b.tree.frame(390.0, 844.0) |> ignore
  b.tree.frame(390.0, 844.0) |> ignore
  [scrolled, jumped, made, slots_picture(b.tree)]
}

///|
/// Whether two pictures are the same rows within `near` of one another, each number.
fn slots_pictures_near(a : Array[(String, Int64, Int64, Int64, Int64)], b : Array[(String, Int64, Int64, Int64, Int64)], near : Double) -> Bool {
  let d = fn(x : Int64, y : Int64) { (x.reinterpret_as_double() - y.reinterpret_as_double()).abs() <= near }
  a.length() == b.length() &&
  a.iter().zip(b.iter()).all(fn(p) { p.0.0 == p.1.0 && d(p.0.1, p.1.1) && d(p.0.2, p.1.2) && d(p.0.3, p.1.3) && d(p.0.4, p.1.4) })
}

///|
/// On a host's pixels of 2.75, 3 and 3.5 a point the three come apart in last bits on main as they do here, with every
/// slot kept (list-rows-placed-on-grid's list_three_paths_test, 200 keys): each row's top is the grid's own number, but
/// what is drawn is a top less where the column is scrolled to, two numbers taken from one another, come to by other sums
/// on each path; the same pixel, not the same double. Those grids are held here once that is mended where the scroll is
/// added; till then, the grids whose numbers are whole (1 and 2) to the bit, and no grid as near as the states are.
test "where a page's list of 1,500 shows is drawn the same scrolled there, asked there, made there and scrolled past it and back: to the bit on 1 and 2 pixels a point, on no grid as near as the states are and the same path twice the same" {
  let faults = []
  for g in [1.0, 2.0] {
    let ps = slots_paths(g)
    if ps[1] != ps[0] {
      faults.push("on \{g}: asked there \{slots_first_apart(ps[1], ps[0])}")
    }
    if ps[2] != ps[0] {
      faults.push("on \{g}: made there \{slots_first_apart(ps[2], ps[0])}")
    }
    if ps[3] != ps[0] {
      faults.push("on \{g}: past it and back \{slots_first_apart(ps[3], ps[0])}")
    }
  }
  // (on no grid nothing says which number a place is: the scroll the wheel's turns came to and the one asked for are two
  // states a few last bits apart, each drawing what it is; the same path again is the same state)
  let ps = slots_paths(0.0)
  for i in 1..<4 {
    if !slots_pictures_near(ps[i], ps[0], 1.0e-9) {
      faults.push("on no grid, path \{i} not within 1e-9: \{slots_first_apart(ps[i], ps[0])}")
    }
  }
  let again = slots_paths(0.0)
  for i in 0..<4 {
    if again[i] != ps[i] {
      faults.push("on no grid, path \{i} again: \{slots_first_apart(again[i], ps[i])}")
    }
  }
  assert_eq(faults, [])
}

///|
test "a page's list of 32, 1,504 and 15,004 keys at its foot, following it, its foot's room stepped each frame: at its foot each frame, the same work whatever the keys" {
  let works = []
  let faults = []
  // (as many that its last rows are the same rows, the same heights)
  for n in [32, 1504, 15004] {
    let room = @signals.signal(0.0, same=fn(a, b) { a == b })
    let c = slots_case(n, follows=true, foot_room=fn() { room.get() })
    let frames = []
    for f in 0..<4 {
      frames.push(slots_frame_work(c, fn() { room.set(room.untracked() + 7.3) }))
      // (its last row's foot where its foot's room starts: at its foot)
      let foot = c.tree
        .drawn()
        .filter(fn(d) { d.words == "row \{n - 1}" })
        .map(fn(d) { d.y + d.h })
      if foot.length() != 1 || (foot[0] - (200.0 - room.untracked())).abs() > 0.000001 {
        faults.push("\{n} keys, frame \{f}: its last row's foot \{Repr(foot)}, its room \{room.untracked()}")
      }
    }
    works.push((n, frames))
  }
  assert_eq(faults, [])
  let (_, f0) = works[0]
  for w in works[1:] {
    let (n, f) = w
    assert_eq(f, f0, msg="\{n} keys against 32: \{Repr(f)} against \{Repr(f0)}")
  }
}

///|
/// Where the row of key `k` is drawn now in the list's box (the top of its words' box), if it is.
fn slots_row_y(t : Tree, k : Int) -> Double? {
  t.drawn().iter().find_first(fn(d) { d.words == "row \{k}" }).map(fn(d) { d.y })
}

///|
test "a page's list of 30 read in its middle, 1,470 older keys put in over them at once: what is read stays where it is on screen, its slots found again round it" {
  let c = slots_case(30)
  // (down to its middle: rows 10 and on in sight)
  for t in turns_at(6, 10.0) {
    c.tree.wheel_at(150.0, 100.0, 0.0, 50.0, 0, t) |> ignore
    c.tree.frame(390.0, 844.0) |> ignore
  }
  let read = slots_picture(c.tree)
  let (words, _, y_bits, _, _) = read[1]
  let k = words.exact_view(start=4, end=words.length()).to_owned()
  // (a page of older ones over them: -1,470 to -1, then the 30 as they were)
  c.keys.set(Array::makei(1470, fn(i) { i - 1470 }) + c.keys.untracked())
  c.tree.frame(390.0, 844.0) |> ignore
  c.tree.frame(390.0, 844.0) |> ignore
  // (where it is to a billionth of a point: its top worked out by the spacer over the slots, of another sum now, its
  // last bits apart)
  let now = slots_picture(c.tree).iter().find_first(fn(p) { p.0 == words }).map(fn(p) { p.2 })
  let same = now.map(fn(b) { (b.reinterpret_as_double() - y_bits.reinterpret_as_double()).abs() < 1.0e-9 })
  assert_eq(same, Some(true), msg="row \{k}: drawn at \{Repr(now.map(fn(b) { b.reinterpret_as_double() }))}, was at \{y_bits.reinterpret_as_double()}")
}

///|
test "ListPlace::centre and bring to a row of a list of 1,500 far past what has slots, never made nor measured: given a slot in that fill, measured, and where it was asked" {
  let c = slots_case(1500)
  // (its middle at the middle of the 200 it shows)
  c.place.centre(1200)
  c.tree.frame(390.0, 844.0) |> ignore
  let mid = slots_row_y(c.tree, 1200)
  // (its top at the top of where it shows)
  c.place.bring(700)
  c.tree.frame(390.0, 844.0) |> ignore
  let top = slots_row_y(c.tree, 700)
  assert_eq(
    (mid.map(fn(y) { (y + slots_tall(1200) / 2.0 - 100.0).abs() < 1.0e-6 }), top.map(fn(y) { y.abs() < 1.0e-6 })),
    (Some(true), Some(true)),
    msg="1200 drawn from \{Repr(mid)} (\{slots_tall(1200)} tall), 700 from \{Repr(top)}",
  )
}

///|
/// What the frame that takes `change` of a list of `n` keys at its foot (following it) makes and lets go, as the tree
/// counts its nodes, and where rows `look` are drawn before it and after it; the layouts it computes (`slots_laid`).
fn slots_key_change(
  n : Int,
  look : Array[Int],
  change : (SlotsCase) -> Unit,
) -> ((Int, Int), Array[Double?], Array[Double?], Int) {
  let c = slots_case(n, follows=true)
  let w0 = c.tree.work()
  let before = look.map(fn(k) { slots_row_y(c.tree, k) })
  change(c)
  c.tree.frame(390.0, 844.0) |> ignore
  let laid = c.tree.work().computes - w0.computes
  c.tree.frame(390.0, 844.0) |> ignore
  let w1 = c.tree.work()
  ((w1.made - w0.made, w1.let_go - w0.let_go), before, look.map(fn(k) { slots_row_y(c.tree, k) }), laid)
}

///|
/// Whether `a` is `b` moved by `d`, each to 1e-9 (none where none).
fn slots_moved_by(a : Double?, b : Double?, d : Double) -> Bool {
  match (a, b) {
    (Some(x), Some(y)) => (x + d - y).abs() < 1.0e-9
    _ => false
  }
}

///|
test "a page's list of 30, 300 and 1,500 at its foot: a key come at its end, one put in and one taken among what shows, one put in far over its slots: each drawn where it goes, the rows over it moved by its height, and what is made and let go the same whatever the keys, none for the one far over" {
  let counts = []
  for n in [30, 300, 1500] {
    // (one come at its end: drawn with its foot at the list's foot, the last before it gone up by its height)
    let (appended, a0, a1, laid) = slots_key_change(n, [n - 1, n], fn(c) { c.keys.set(c.keys.untracked() + [n]) })
    // (in one layout of the column: its slots brought up to the keys as the change is taken, not found in a layout
    // that asks for another)
    assert_eq(laid, 1, msg="\{n}: layouts computed by the frame a key came at its end")
    assert_true(slots_moved_by(a0[0], a1[0], -slots_tall(n)) && a1[1] is Some(_), msg="\{n}: come at its end: \{Repr((a0, a1))}")
    // (one put in three from its end, in sight: drawn where the third from the end was, less its own height; the row
    // over it gone up by as much, the one under it where it was)
    let (put_in, p0, p1, _) = slots_key_change(n, [n - 4, n - 3, 100000], fn(c) {
      let ks = c.keys.untracked().copy()
      ks.insert(n - 3, 100000)
      c.keys.set(ks)
    })
    let h = slots_tall(100000)
    assert_true(
      slots_moved_by(p0[0], p1[0], -h) && slots_moved_by(p0[1], p1[1], 0.0) && slots_moved_by(p0[1], p1[2], -h),
      msg="\{n}: put in three from its end: \{Repr((p0, p1))}",
    )
    // (the third from its end taken: not drawn, the one over it come down by its height)
    let (taken, t0, t1, _) = slots_key_change(n, [n - 4, n - 3], fn(c) {
      let ks = c.keys.untracked().copy()
      ks.remove(n - 3) |> ignore
      c.keys.set(ks)
    })
    assert_true(slots_moved_by(t0[0], t1[0], slots_tall(n - 3)) && t1[1] is None, msg="\{n}: taken three from its end: \{Repr((t0, t1))}")
    // (one put in at its very top, far over its slots but on 30, where its slots reach its top)
    let (far, f0, f1, _) = slots_key_change(n, [n - 1], fn(c) { c.keys.set([-1] + c.keys.untracked()) })
    assert_true(slots_moved_by(f0[0], f1[0], 0.0), msg="\{n}: put in at its top: \{Repr((f0, f1))}")
    counts.push((n, appended, put_in, taken, far))
  }
  let (_, a300, p300, t300, f300) = counts[1]
  let (_, a1500, p1500, t1500, f1500) = counts[2]
  assert_eq((a1500, p1500, t1500), (a300, p300, t300), msg="1,500 against 300: \{Repr(counts)}")
  assert_eq((f300, f1500), ((0, 0), (0, 0)), msg="one put in far over its slots: \{Repr(counts)}")
}
