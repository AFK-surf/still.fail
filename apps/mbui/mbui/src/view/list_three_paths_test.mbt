// A page's list on a host's pixels (Tree::set_rows_grid) is drawn the same, to the bit, however it came to where it
// shows: scrolled there by the wheel a turn at a time, asked there (ListPlace::bring) from its top, or made there (asked
// before its first frame). Each row's top is the grid's own number for its pixel (#5449); where the column is scrolled
// to is come to by other sums on each path, so where its first row comes to is put on the grid's own number too, not
// left as a top less the scroll (Scroll::held_dy): states a pixel apart or less are one where rows are on pixels. On no
// grid nothing says which number a place is: the scroll the wheel's turns came to and the one asked for are two states
// a few last bits apart, and each draws what it is; there the three are as near as that, and the same path twice the
// same to the bit.

///|
/// How tall key `k`'s row is: no binary fraction, no whole number of pixels at 2.75 or 3.5.
fn three_tall(k : Int) -> Double {
  match k % 4 {
    0 => 22.1
    1 => 31.7
    2 => 40.0 * 1.3
    _ => 27.3
  }
}

///|
/// A list of 200 keys in a box 300 by 200 on the grid of `g` pixels a point, each row as tall as three_tall says with
/// words of its key; `first` asked before its first frame. The tree and what asks it to show a block.
fn three_case(g : Double, first? : (@view.ListPlace[Int]) -> Unit = fn(_) {  }) -> (@view.Tree, @view.ListPlace[Int]) {
  let place : @view.ListPlace[Int] = @view.ListPlace::new()
  let tree = @view.Tree::new(
    fn(root) {
      root.box(fn(o) {
        o.width(Is(Some(300.0))).height(Is(Some(200.0))) |> ignore
        o.scrolls_window(@view.Scroll::list(), fn() { Array::makei(200, fn(i) { i }) }, est=30.0, place~, fn(b, k) {
          b.box(fn(l) { l.height(Is(Some(three_tall(k)))).words(Is("row \{k}")) |> ignore }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  if g > 0.0 {
    tree.set_rows_grid(g)
  }
  first(place)
  tree.frame(390.0, 844.0) |> ignore
  tree.frame(390.0, 844.0) |> ignore
  (tree, place)
}

///|
/// The words drawn in the list's box and where, top down, each number as its bits: read off the tree into plain values.
fn three_picture(t : @view.Tree) -> Array[(String, Int64, Int64, Int64, Int64)] {
  let out = t
    .drawn()
    .filter(fn(d) { d.words != "" && d.y + d.h > 0.0 && d.y < 200.0 })
    .map(fn(d) {
      (d.words, d.x.reinterpret_as_int64(), d.y.reinterpret_as_int64(), d.w.reinterpret_as_int64(), d.h.reinterpret_as_int64())
    })
  out.sort_by(fn(a, b) { a.2.reinterpret_as_double().compare(b.2.reinterpret_as_double()) })
  out
}

///|
/// Whether two pictures are the same rows within `near` of one another, each number.
fn three_near(a : Array[(String, Int64, Int64, Int64, Int64)], b : Array[(String, Int64, Int64, Int64, Int64)], near : Double) -> Bool {
  let d = fn(x : Int64, y : Int64) { (x.reinterpret_as_double() - y.reinterpret_as_double()).abs() <= near }
  a.length() == b.length() &&
  a.iter().zip(b.iter()).all(fn(p) { p.0.0 == p.1.0 && d(p.0.1, p.1.1) && d(p.0.2, p.1.2) && d(p.0.3, p.1.3) && d(p.0.4, p.1.4) })
}

///|
/// The first entry two pictures differ in, its numbers as they are.
fn three_apart(a : Array[(String, Int64, Int64, Int64, Int64)], b : Array[(String, Int64, Int64, Int64, Int64)]) -> String {
  let n = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<n {
    if a[i] != b[i] {
      return "[\{i}] \{a[i].0} y \{a[i].2.reinterpret_as_double()} against \{b[i].0} y \{b[i].2.reinterpret_as_double()}"
    }
  }
  "\{a.length()} against \{b.length()}"
}

///|
/// Where the list shows by each path on grid `g`, each ending with the same key's top at the top of what shows (a
/// list's state is its anchor: which key is at its top and how far in): scrolled there by the wheel (its last turn as far
/// as that key's row is drawn down from the top), asked there (ListPlace::bring), made there (asked before its first
/// frame), and scrolled 150 past it and back; each read into plain values before the next is made.
fn three_paths(g : Double) -> Array[Array[(String, Int64, Int64, Int64, Int64)]] {
  let row_of = fn(w : String) {
    let mut k = 0
    for ch in w.exact_view(start=4) {
      k = k * 10 + (ch.to_int() - '0'.to_int())
    }
    k
  }
  let (s, _) = three_case(g)
  // (each turn at its own moment, the tree brought to it as it is taken: Tree::wheel_at)
  for t in 0..<20 {
    s.wheel_at(150.0, 100.0, 0.0, 97.0, 0, 10.0 + t.to_double()) |> ignore
  }
  s.frame(390.0, 844.0) |> ignore
  // (the first row whose top is in sight, and how far down it is drawn: the last turn as far)
  let mut key = 0
  let mut top_y = 1.0e9
  for d in s.drawn() {
    if d.words.has_prefix("row ") && d.y >= 0.0 && d.y < top_y {
      top_y = d.y
      key = row_of(d.words)
    }
  }
  s.wheel_at(150.0, 100.0, 0.0, top_y, 0, 60.0) |> ignore
  s.frame(390.0, 844.0) |> ignore
  s.frame(390.0, 844.0) |> ignore
  let scrolled = three_picture(s)
  let (j, p) = three_case(g)
  p.bring(key)
  j.frame(390.0, 844.0) |> ignore
  j.frame(390.0, 844.0) |> ignore
  let jumped = three_picture(j)
  let (m, _) = three_case(g, first=fn(p) { p.bring(key) })
  let made = three_picture(m)
  // (past it and back: the same turns and the last, 150 further, then 150 back)
  let (b, _) = three_case(g)
  // (each turn at its own moment, the tree brought to it as it is taken: Tree::wheel_at)
  for t in 0..<20 {
    b.wheel_at(150.0, 100.0, 0.0, 97.0, 0, 10.0 + t.to_double()) |> ignore
  }
  b.frame(390.0, 844.0) |> ignore
  b.wheel_at(150.0, 100.0, 0.0, top_y + 150.0, 0, 60.0) |> ignore
  b.frame(390.0, 844.0) |> ignore
  b.wheel_at(150.0, 100.0, 0.0, -150.0, 0, 70.0) |> ignore
  b.frame(390.0, 844.0) |> ignore
  b.frame(390.0, 844.0) |> ignore
  [scrolled, jumped, made, three_picture(b)]
}

///|
test "a page's list of 200 keys on a host's pixels (1, 2, 2.75, 3, 3.5 a point) is drawn the same, to the bit, scrolled there, asked there, made there and scrolled past it and back; on no grid, as near as the states are, and the same path twice the same" {
  let faults = []
  let names = ["scrolled there", "asked there", "made there", "past it and back"]
  for g in [1.0, 2.0, 2.75, 3.0, 3.5] {
    let ps = three_paths(g)
    for i in 1..<4 {
      if ps[i] != ps[0] {
        faults.push("on \{g}: \{names[i]} \{three_apart(ps[i], ps[0])}")
      }
    }
  }
  let ps = three_paths(0.0)
  for i in 1..<4 {
    if !three_near(ps[i], ps[0], 1.0e-9) {
      faults.push("on no grid, \{names[i]} not within 1e-9: \{three_apart(ps[i], ps[0])}")
    }
  }
  let again = three_paths(0.0)
  for i in 0..<4 {
    if again[i] != ps[i] {
      faults.push("on no grid, \{names[i]} again: \{three_apart(again[i], ps[i])}")
    }
  }
  assert_eq(faults, [])
}
