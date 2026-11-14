// panel_list_node and capped_node beside the old view's panel_list and Ctx::capped, in one window: the old at its left
// (an old view hosted in a node: @ui.old), the node at its right, 200 further across, each holding the same rows. What
// each draws, at the same moments, is the same: where each row's words stand and how faded, the bar, which rows are made.

///|
/// A row's height: 30, 40 and 50 in turn.
fn lists_row_h(i : Int) -> Double {
  30.0 + (i % 3).to_double() * 10.0
}

///|
/// The top of row `i` in what scrolls.
fn lists_row_top(i : Int) -> Double {
  let mut top = 0.0
  for k in 0..<i {
    top = top + lists_row_h(k)
  }
  top
}

///|
/// How many rows meet a room `room` tall scrolled `at` down, of `n`.
fn lists_meeting(n : Int, at : Double, room : Double) -> Int {
  let mut count = 0
  for i in 0..<n {
    let top = lists_row_top(i)
    if top < at + room && top + lists_row_h(i) > at {
      count = count + 1
    }
  }
  count
}

///|
/// A row's words.
// kept across runs: a value (no field of it changes)
let lists_words : @ui.TextStyle = @ui.text_style(size=Ui, color=Fg, wrap=false)

///|
/// How far across the node's column stands from the old one's.
let lists_apart : Double = 200.0

///|
/// How tall the lists' room is (and capped's most).
let lists_room : Double = 300.0

///|
/// A window 400 wide holding at its left an old view's panel_list (`capped`: a Ctx::capped holding all its rows, then
/// words under it) and at its right panel_list_node (capped_node), each 180 wide, from 10 across, `n` rows of
/// lists_row_h each; a list in a room lists_room tall filling it, capped in a column 400 tall. The rows the old one made
/// as it was last built, and how many of the node one's are made now.
fn lists_tester(n : Int, capped? : Bool = false, platform? : Int = 0) -> (@ui.Tester, Array[Int], Ref[Int]) {
  let t = @ui.Tester::new(fn(_c) {  }, w=400.0, h=500.0, platform~)
  t.check_looks(false)
  let old_made : Array[Int] = []
  let new_made = Ref(0)
  let column = if capped { 400.0 } else { lists_room }
  @ui.set_view_app(fn(root) {
    root.row(Is(true)) |> ignore
    root.box(fn(g) { g.width(Is(Some(10.0))) |> ignore }) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(180.0))).height(Is(Some(column))) |> ignore
      @ui.old(h, fn(c) {
        old_made.clear()
        let row = fn(i : Int) {
          c.box(style=@ui.style(w=Full, h=Fixed(lists_row_h(i))), fn() { c.text("old \{i}", style=lists_words) |> ignore })
          |> ignore
        }
        if capped {
          c.capped("lists/old", lists_room, fn() {
            for i in 0..<n {
              row(i)
            }
          })
          |> ignore
          c.text("old end", style=lists_words) |> ignore
        } else {
          panel_list(c, "lists/old", n, 40.0, fn(i) {
            old_made.push(i)
            row(i)
          })
          |> ignore
        }
      }).grow(Is(1.0))
      |> ignore
    })
    |> ignore
    root.box(fn(g) { g.width(Is(Some(lists_apart - 180.0))) |> ignore }) |> ignore
    root.box(fn(h) {
      h.width(Is(Some(180.0))).height(Is(Some(column))) |> ignore
      let row = fn(b : @view.View, i : Int) {
        b.height(Is(Some(lists_row_h(i)))) |> ignore
        words_node(b, fn() { "new \{i}" }, fn() { lists_words }) |> ignore
      }
      if capped {
        capped_node(h, fn() { lists_room }, fn(s) {
          for i in 0..<n {
            s.box(fn(b) { row(b, i) }) |> ignore
          }
        })
        |> ignore
        words_node(h, fn() { "new end" }, fn() { lists_words }) |> ignore
      } else {
        panel_list_node(
          h,
          fn() { Array::makei(n, fn(i) { i }) },
          fn(b, i) {
            new_made.val += 1
            b.owns(fn() { new_made.val -= 1 }) |> ignore
            row(b, i)
          },
          est=40.0,
          fills=true,
        )
        |> ignore
      }
    })
    |> ignore
  })
  t.draw()
  (t, old_made, new_made)
}

///|
/// What is drawn of a column's words where they meet its room (and its `end`, under it), each as `name` row (or `end`)
/// at x, y in the column's own terms, its alpha: the old's (`side` "old") or the node's ("new"), by what they say.
fn lists_words_of(t : @ui.Tester, side : String) -> Map[String, (Double, Double, Double)] {
  let dx = if side == "old" { 10.0 } else { 10.0 + lists_apart }
  let out : Map[String, (Double, Double, Double)] = Map([])
  for w in t.words() {
    // (a row's words where they meet its room: those past it cut away, whether made or not)
    if w.0.has_prefix(side + " ") && (w.0 == side + " end" || (w.2 + w.4 > 0.0 && w.2 < lists_room)) {
      out[w.0.exact_view(start=side.length() + 1).to_owned()] = (w.1 - dx, w.2, w.5)
    }
  }
  out
}

///|
/// Fails where the two columns' words stand otherwise, or differ in which are drawn (`at`: the moment, said).
fn lists_same_words(t : @ui.Tester, at : String) -> Unit raise {
  let old = lists_words_of(t, "old")
  let new = lists_words_of(t, "new")
  assert_true(old.length() > 0, msg="\{at}: no old words")
  let keys_old = old.keys().collect()
  keys_old.sort()
  let keys_new = new.keys().collect()
  keys_new.sort()
  assert_eq(keys_new, keys_old, msg="\{at}: rows drawn")
  for k, o in old {
    let n = new.get(k).unwrap()
    assert_true(
      (n.0 - o.0).abs() < 0.01 && (n.1 - o.1).abs() < 0.01 && (n.2 - o.2).abs() < 0.01,
      msg="\{at}: row \{k} old \{Repr(o)} new \{Repr(n)}",
    )
  }
}

///|
/// What is drawn as rectangles in a column (its bar, its fades' ground), in the column's own terms, in order.
fn lists_rects_of(t : @ui.Tester, side : String) -> Array[String] {
  let x0 = if side == "old" { 10.0 } else { 10.0 + lists_apart }
  let out = []
  let r2 = fn(v : Double) { ((v * 100.0).round() / 100.0).to_string() }
  for r in t.drawn_rects() {
    if r.0 >= x0 - 0.5 && r.0 < x0 + 180.0 + 0.5 {
      // (its ink less its alpha, which a fade's moment may round one way or the other: lists_alphas)
      out.push(r2(r.0 - x0) + "," + r2(r.1) + " " + r2(r.2) + "x" + r2(r.3) + " " + (r.4 >> 8).to_string())
    }
  }
  out.sort()
  out
}

///|
/// The alphas of what is drawn as rectangles in a column, in the order lists_rects_of has them.
fn lists_alphas(t : @ui.Tester, side : String) -> Array[Int] {
  let x0 = if side == "old" { 10.0 } else { 10.0 + lists_apart }
  let out : Array[(Double, Double, Int)] = []
  for r in t.drawn_rects() {
    if r.0 >= x0 - 0.5 && r.0 < x0 + 180.0 + 0.5 {
      out.push((r.0 - x0, r.1, (r.4 & 0xFFL).to_int()))
    }
  }
  out.sort_by(fn(a, b) { if a.0 != b.0 { a.0.compare(b.0) } else { a.1.compare(b.1) } })
  out.map(fn(a) { a.2 })
}

///|
/// Fails where the two columns draw other rectangles, or their alphas differ by more than one in 255 (`at`: the
/// moment, said).
fn lists_same_rects(t : @ui.Tester, at : String) -> Unit raise {
  let (rn, ro) = (lists_rects_of(t, "new"), lists_rects_of(t, "old"))
  assert_eq(rn, ro, msg="\{at}: drawn new \{Repr(rn)} old \{Repr(ro)}")
  let (an, ao) = (lists_alphas(t, "new"), lists_alphas(t, "old"))
  for i, a in an {
    // (the tree's bar (@ui.tree_scroll_bar) fading after the wheel is one in 255 more or less opaque than the old view's
    // at some moments, its fade worked out its own way: within that)
    assert_true((a - ao[i]).abs() <= 1, msg="\{at}: alphas new \{Repr(an)} old \{Repr(ao)}")
  }
}

///|
/// How far the node's list (of `n` rows) is scrolled, by where its first row drawn stands against where row 0's words
/// stood at rest at its top (`first_y`).
fn lists_scrolled(t : @ui.Tester, n : Int, first_y : Double) -> Double {
  let new = lists_words_of(t, "new")
  for i in 0..<n {
    match new.get(i.to_string()) {
      Some(w) => return lists_row_top(i) - (w.1 - first_y)
      None => ()
    }
  }
  0.0
}

///|
test "panel_list_node: at rest, its rows where the old list's are, those that meet its room alone made" {
  for platform in [0, 2] {
    let (t, old_made, new_made) = lists_tester(60, platform~)
    t.run_for(@ui.move_most_ms)
    lists_same_words(t, "at rest, platform \{platform}")
    let meeting = lists_meeting(60, 0.0, lists_room)
    assert_eq(meeting, 8)
    assert_true(new_made.val <= meeting, msg="platform \{platform}: \{new_made.val} made, \{meeting} meet its room")
    assert_eq(new_made.val, old_made.length(), msg="platform \{platform}: made")
    lists_same_rects(t, "at rest, platform \{platform}")
  }
}

///|
test "panel_list_node: the wheel over each at the same moment, the same at each moment after, no more made than meet its room" {
  let (t, _, new_made) = lists_tester(60)
  t.run_for(@ui.move_most_ms)
  let first_y = lists_words_of(t, "new").get("0").unwrap().1
  t.wheel(100.0, 150.0, 400.0)
  t.wheel(100.0 + lists_apart, 150.0, 400.0)
  let from = t.time()
  for ms in [0.0, 50.0, 100.0, 200.0, 400.0, 800.0] {
    t.run_for(from + ms - t.time())
    lists_same_words(t, "\{ms} after the wheel")
    lists_same_rects(t, "\{ms} after the wheel")
    // (no more made than meet its room; not as many as the old list built: it builds the rows along the wheel's way too,
    // 18 as the wheel is turned where 8 show)
    let meeting = lists_meeting(60, lists_scrolled(t, 60, first_y), lists_room)
    assert_true(new_made.val <= meeting, msg="\{ms}: \{new_made.val} made, \{meeting} meet its room")
    assert_true(new_made.val >= 1, msg="\{ms}: none made")
  }
  assert_true(lists_scrolled(t, 60, first_y) > 0.0, msg="scrolled")
}

///|
/// Drags the column `side` up by `by` with a finger from its middle, then where its words stand at moments after it is
/// let go: each moment's, by its row.
fn lists_flung(t : @ui.Tester, side : String, by : Double) -> Array[Map[String, (Double, Double, Double)]] {
  let x = if side == "old" { 100.0 } else { 100.0 + lists_apart }
  t.drag(x, 250.0, x, 250.0 - by)
  let from = t.time()
  let out = []
  for ms in [0.0, 100.0, 300.0, 600.0, 1200.0] {
    t.run_for(from + ms - t.time())
    out.push(lists_words_of(t, side))
  }
  out
}

///|
test "panel_list_node: dragged and let go with a finger, where its rows are at each moment after as the old list's" {
  let (t, _, new_made) = lists_tester(60, platform=2)
  t.run_for(@ui.move_most_ms)
  let first_y = lists_words_of(t, "new").get("0").unwrap().1
  let old = lists_flung(t, "old", 200.0)
  let new = lists_flung(t, "new", 200.0)
  for i, o in old {
    let n = new[i]
    let keys_old = o.keys().collect()
    keys_old.sort()
    let keys_new = n.keys().collect()
    keys_new.sort()
    assert_eq(keys_new, keys_old, msg="moment \{i}: rows drawn new \{Repr(keys_new)} old \{Repr(keys_old)}")
    for k, ov in o {
      let nv = n.get(k).unwrap()
      // (the node's scroll put on the window's pixels as it is flung (half a point at 2), the old one's anywhere between
      // them: within one)
      assert_true((nv.1 - ov.1).abs() <= 0.5 && (nv.2 - ov.2).abs() < 0.01, msg="moment \{i}: row \{k} old \{Repr(ov)} new \{Repr(nv)}")
    }
  }
  let meeting = lists_meeting(60, lists_scrolled(t, 60, first_y), lists_room)
  assert_true(new_made.val <= meeting && new_made.val >= 1, msg="\{new_made.val} made, \{meeting} meet its room")
}

///|
test "capped_node: as tall as what it holds under its most, its words under it where the old one's are" {
  let (t, _, _) = lists_tester(3, capped=true)
  t.run_for(@ui.move_most_ms)
  lists_same_words(t, "short")
  let end = lists_words_of(t, "new").get("end").unwrap()
  assert_true(end.1 >= lists_row_top(3) - 0.01 && end.1 < lists_room, msg="its words under it: \{Repr(end)}")
}

///|
test "capped_node: past its most, kept to it, scrolled by the wheel as the old one is at each moment" {
  for platform in [0, 2] {
    let (t, _, _) = lists_tester(20, capped=true, platform~)
    t.run_for(@ui.move_most_ms)
    lists_same_words(t, "at rest, platform \{platform}")
    lists_same_rects(t, "capped at rest, platform \{platform}")
    let end = lists_words_of(t, "new").get("end").unwrap()
    assert_true((end.1 - lists_room).abs() < 0.01, msg="its words under its most: \{Repr(end)}")
  }
  let (t, _, _) = lists_tester(20, capped=true)
  t.run_for(@ui.move_most_ms)
  t.wheel(100.0, 150.0, 200.0)
  t.wheel(100.0 + lists_apart, 150.0, 200.0)
  let from = t.time()
  for ms in [0.0, 50.0, 100.0, 200.0, 400.0, 800.0] {
    t.run_for(from + ms - t.time())
    lists_same_words(t, "\{ms} after the wheel")
    lists_same_rects(t, "\{ms} after the wheel")
  }
}
