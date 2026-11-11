// A row that wraps (View::wraps, an old view's box's `flow` and its `line_gap`): what it holds goes on in another line
// where the row has not the room, the lines as far apart as said, along each line its gap; said none, one line, its
// gap both ways again; said either way after or before its gap, the same.

///|
/// Two boxes 60 by 20 in a row 100 wide, 10 apart along it, wrapping as `lines` says (said before its gap where
/// `first`); where each is drawn.
fn wraps_tree(lines : @signals.Signal[Double?], first? : Bool = false) -> () -> Array[(Double, Double)] {
  let ids : Array[@view.NodeId] = []
  let t = @view.Tree::new(
    fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(r) {
        r.width(Is(Some(100.0))).row(Is(true)) |> ignore
        if first {
          r.wraps(By(fn() { lines.get() })).gap(Is(10.0)) |> ignore
        } else {
          r.gap(Is(10.0)).wraps(By(fn() { lines.get() })) |> ignore
        }
        for _ in 0..<2 {
          r.box(fn(b) {
            ids.push(b.id())
            b.width(Is(Some(60.0))).height(Is(Some(20.0))).ground(Is(0x336699FFL)) |> ignore
          })
          |> ignore
        }
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  fn() {
    t.frame(390.0, 844.0) |> ignore
    ids.map(fn(id) {
      match t.drawn().search_by(fn(d) { d.id == id }) {
        Some(i) => (t.drawn()[i].x, t.drawn()[i].y)
        None => (-1.0, -1.0)
      }
    })
  }
}

///|
test "wraps: what has not the room on its line goes on the next, the lines as far apart as said; none, one line, its gap both ways" {
  for first in [false, true] {
    let lines = @signals.signal(Some(4.0))
    let at = wraps_tree(lines, first~)
    // (60 and 10 and 60 is more than 100: the second under the first, 20 and 4 down)
    assert_eq(at(), [(0.0, 0.0), (0.0, 24.0)], msg="wrapping, said first \{first}")
    lines.set(Some(0.0))
    assert_eq(at(), [(0.0, 0.0), (0.0, 20.0)], msg="its lines 0 apart, said first \{first}")
    // (one line: the second 10 after the first, given its room past the row's end)
    lines.set(None)
    assert_eq(at(), [(0.0, 0.0), (70.0, 0.0)], msg="one line, said first \{first}")
  }
}

///|
test "wraps: words that fit beside each other stay on one line, the first growing to the line's room; the second under it where they do not" {
  let width = @signals.signal(300.0)
  let ids : Array[@view.NodeId] = []
  let look : @view.WordsLook = { size: 15.0, weight: 400, line: 20.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
  let t = @view.Tree::new(
    fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(r) {
        r.width(By(fn() { Some(width.get()) })).row(Is(true)).gap(Is(12.0)).wraps(Is(Some(0.0))) |> ignore
        r.box(fn(a) {
          ids.push(a.id())
          a.grow(Is(1.0)).shrink(Is(1.0)).min_width(Is(Some(0.0))).words(Is("Studio"), look~) |> ignore
        })
        |> ignore
        r.box(fn(b) {
          b.row(Is(true)).gap(Is(6.0)) |> ignore
          b.box(fn(w) {
            ids.push(w.id())
            w.words(Is("全局记忆 · 项目记忆"), look~) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let at = fn() {
    t.frame(390.0, 844.0) |> ignore
    ids.map(fn(id) {
      match t.drawn().search_by(fn(d) { d.id == id }) {
        Some(i) => (t.drawn()[i].x, t.drawn()[i].y, t.drawn()[i].w)
        None => (-1.0, -1.0, -1.0)
      }
    })
  }
  let wide = at()
  assert_true(wide[1].1 == 0.0 && wide[1].0 > wide[0].0, msg="one line: \{Repr(wide)}")
  assert_true(wide[0].2 + 12.0 + wide[1].2 == 300.0, msg="the first grown to the line's room: \{Repr(wide)}")
  width.set(wide[1].2 + 20.0)
  let narrow = at()
  assert_true(narrow[1].1 > 0.0 && narrow[1].0 == 0.0, msg="the second under the first: \{Repr(narrow)}")
}

///|
test "wraps: words exactly as wide as the line beside each other stay on it, what says the second in a row with a slot not shown" {
  let width = @signals.signal(1000.0)
  let grows = @signals.signal(0.0)
  let ids : Array[@view.NodeId] = []
  let look : @view.WordsLook = { size: 27.5, weight: 400, line: 35.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
  let t = @view.Tree::new(
    fn(root) {
      root.lines_up(Is(Some(Start))) |> ignore
      root.box(fn(r) {
        r.width(By(fn() { Some(width.get()) })).row(Is(true)).gap(Is(12.0)).wraps(Is(Some(0.0))).lines_up(Is(Some(Middle))) |> ignore
        r.box(fn(a) {
          ids.push(a.id())
          a.grow(By(fn() { grows.get() })).shrink(Is(1.0)).min_width(Is(Some(0.0))).words(Is("Studio"), look~) |> ignore
        })
        |> ignore
        r.box(fn(b) {
          b.row(Is(true)).gap(Is(6.0)).lines_up(Is(Some(Middle))) |> ignore
          b.show(fn() { false }, fn(d) { d.width(Is(Some(7.0))).height(Is(Some(7.0))) |> ignore })
          b.box(fn(w) {
            ids.push(w.id())
            w.words(Is("全局记忆 · 项目记忆"), look~) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  let at = fn() {
    t.frame(1200.0, 844.0) |> ignore
    ids.map(fn(id) {
      match t.drawn().search_by(fn(d) { d.id == id }) {
        Some(i) => (t.drawn()[i].x, t.drawn()[i].y, t.drawn()[i].w)
        None => (-1.0, -1.0, -1.0)
      }
    })
  }
  // (each as wide as its words, not grown: the line as wide as both and the gap)
  let free = at()
  let first_w = free[0].2
  grows.set(1.0)
  width.set(first_w + 12.0 + free[1].2)
  let exact = at()
  assert_true(exact[1].1 == exact[0].1, msg="one line at \{first_w} + 12 + \{free[1].2}: \{Repr(exact)} (free \{Repr(free)})")
}
