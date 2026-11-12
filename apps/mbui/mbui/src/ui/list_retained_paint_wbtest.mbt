// A list's rows are identified by the keys supplied to ListRows. A row that merely moves within the viewport keeps
// its drawing: it is still presented and hit at its new place without asking its paint callbacks to draw it again.

///|
fn row_paint_status(item : Int) -> String {
  for _, rn in kept_nodes {
    if rn.item == item {
      let drawing = match rn.drawing {
        Some(d) => "valid=\{d.valid} stale=\{d.watch.is_stale()} x=\{d.x} y=\{d.y} clip=\{Repr(d.clip)}"
        None => "no drawing"
      }
      return "ok=\{rn.ok} why=\{rn.why} key=\{Repr(rn.row_key)} base=\{rn.base} count=\{rn.n} pool=\{rn.in_pool} built=\{rn.built_frame}: \{drawing}"
    }
  }
  "row not kept"
}

///|
/// What row `item` keeps as drawn: whether it is kept, painted whole, and where it was painted (its y).
fn row_kept_drawing(item : Int) -> (Bool, Bool, Double)? {
  for _, rn in kept_nodes {
    if rn.item == item {
      return match rn.drawing {
        Some(d) => Some((d.valid, d.whole, d.y))
        None => None
      }
    }
  }
  None
}

///|
/// Row `item`'s drawing's band and how far it was kept drawn, at their foot.
fn row_kept_reach(item : Int) -> (Double, Double)? {
  for _, rn in kept_nodes {
    if rn.item == item {
      return match rn.drawing {
        Some(d) if d.band.length() == 4 && d.reach.length() == 4 => Some((d.band[3], d.reach[3]))
        _ => None
      }
    }
  }
  None
}

///|
test "scrolling moves a keyed row's drawing and target without painting the row again" {
  let painted = Ref(0)
  let pressed : Array[Int] = []
  let rows : ListRows[Int] = ListRows::new()
  let t = Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      let item = items[k]
      let id = c.id("button/\{item}")
      c.on_press(id, fn() {
        pressed.push(item)
      })
      let n = c.box(id~, h=Px(40.0), bg=0x224466FFL, fn() {  })
      if item == 2 {
        c.bg_by(n, fn() {
          painted.val += 1
          0xCC6633FFL
        })
      }
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.frame_at(at + 16.0)
  let before_row = t.row(2).unwrap()
  let before_paint = painted.val
  let before_status = row_paint_status(2)
  assert_true(before_paint > 0, msg="the row must have been drawn before the scroll")
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  let after_row = t.row(2).unwrap()
  assert_true(after_row.1 < before_row.1, msg="the row must actually move: \{Repr(before_row)} -> \{Repr(after_row)}")
  let drawn = t.drawn_rects().filter(fn(r) { r.4 == 0xCC6633FFL })
  assert_true(drawn.iter().any(fn(r) { (r.1 - after_row.1).abs() < 0.01 }), msg="the row is drawn where it moved: \{Repr(drawn)} vs \{Repr(after_row)}")
  let after_paint = painted.val
  let after_status = row_paint_status(2)
  t.tap_once(100.0, after_row.1 + 20.0)
  assert_eq(pressed, [2], msg="the target must move with the drawing")
  assert_eq(after_paint, before_paint, msg="a retained row need not generate its drawing again while scrolling: \{before_status} -> \{after_status}")
}

///|
test "a retained row repaints when a value read only by its paint changes" {
  let ink = @signals.signal(0xCC6633FFL)
  let rows : ListRows[Int] = ListRows::new()
  let t = Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      let item = items[k]
      let n = c.box(h=Px(40.0), bg=0x224466FFL, fn() {  })
      if item == 2 {
        c.bg_by(n, fn() { ink.get() })
      }
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.frame_at(at + 16.0)
  ink.set(0x229944FFL)
  t.frame_at(at + 32.0)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x229944FFL }), msg="a changed paint value must be shown")
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 33.0)
  t.frame_at(at + 48.0)
  let row = t.row(2).unwrap()
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x229944FFL && (r.1 - row.1).abs() < 0.01 }), msg="the new value follows the row as it scrolls")
}

///|
fn row_drawing_frames(keep : Bool) -> Array[Array[Array[Double]]] {
  let ink = @signals.signal(0xCC6633FFL)
  let rows : ListRows[Int] = ListRows::new()
  let t = Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      let item = items[k]
      let b = c.box(h=Px(40.0), bg=0x224466FFL, fn() {
        c.text("row \{item}", wrap=false) |> ignore
      })
      if item == 2 {
        c.bg_by(b, fn() { ink.get() })
      }
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.drawn_again(keep)
  t.draw()
  let at = t.time()
  t.frame_at(at + 16.0)
  let frames = [t.drawn_instances_keyed()]
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  frames.push(t.drawn_instances_keyed())
  ink.set(0x229944FFL)
  t.frame_at(at + 48.0)
  frames.push(t.drawn_instances_keyed())
  t.wheel_told(100.0, 100.0, 0.0, -10.0, 0, at + 49.0)
  t.frame_at(at + 64.0)
  frames.push(t.drawn_instances_keyed())
  t.drawn_again(true)
  frames
}

///|
test "keyed row drawings match drawing each frame through scrolling and a paint change" {
  let retained = row_drawing_frames(true)
  let built = row_drawing_frames(false)
  assert_eq(retained.length(), built.length())
  for f in 0..<retained.length() {
    let a = retained[f]
    let b = built[f]
    assert_eq(a.length(), b.length(), msg="frame \{f}")
    for i in 0..<a.length() {
      for j in 0..<a[i].length() {
        assert_true((a[i][j] - b[i][j]).abs() < 0.000001, msg="frame \{f}, instance \{i}, value \{j}: retained \{a[i][j]}, rebuilt \{b[i][j]}")
      }
    }
  }
}

///|
test "a new key at an existing list position does not reuse the previous row" {
  let ids = @signals.signal(Array::makei(30, fn(i) { i }))
  let rows : ListRows[Int] = ListRows::new()
  let t = Tester::new(fn(c) {
    let now = ids.get()
    let (items, _) = rows.rows(c, now.map(fn(i) { "row/" + i.to_string() }), now, fn(_) { "" }, watched=false)
    c.list("rows", items.length(), 40.0, fn(k) {
      c.box(h=Px(40.0), fn() { c.text("row \{items[k]}", wrap=false) |> ignore }) |> ignore
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.set_rows_on_pixels(true)
  t.draw()
  assert_true(t.find("row 2") is Some(_))
  let changed = ids.get().copy()
  changed[2] = 42
  ids.set(changed)
  t.draw()
  assert_true(t.find("row 42") is Some(_), msg="the new keyed row must be shown")
  assert_true(t.find("row 2") is None, msg="the old keyed row must not be shown at the new key")
}

///|
test "a row inside the list whose words reach past it is drawn again as the lines left out come into view" {
  let rows : ListRows[Int] = ListRows::new()
  let t = Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      let item = items[k]
      // (a box that does not cut what it holds: row 3's lines go on below it, past the list's foot)
      c.box(h=Px(40.0), bg=0x224466FFL, fn() {
        // (narrow, its words wrapped onto lines that go on below the row)
        c.box(w=Px(50.0), fn() {
          c.text(if item == 3 { "one two three four five six seven eight nine" } else { "row \{item}" }, wrap=true) |> ignore
        }) |> ignore
      }) |> ignore
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  // (each frame painted alone compared with it built whole: the Tester fails where they differ)
  t.check_looks(true)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.frame_at(at + 16.0)
  let before = t.row(3).unwrap()
  assert_true(before.1 + 40.0 <= 160.001, msg="row 3 is wholly in view: \{Repr(before)}")
  t.wheel_told(100.0, 100.0, 0.0, 20.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  t.frame_at(at + 48.0)
  let after = t.row(3).unwrap()
  assert_true(after.1 < before.1, msg="row 3 moved up: \{Repr(before)} -> \{Repr(after)}")
  assert_true(after.1 + 40.0 <= 160.001, msg="row 3 is still wholly in view, its lines below it coming in: \{Repr(after)}")
}

///|
test "a row cut by the list's edge keeps its drawing, what is past the edge left out as a paint there leaves it" {
  let painted = Ref(0)
  let rows : ListRows[Int] = ListRows::new()
  let t = Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 60.0, fn(k) {
      let item = items[k]
      let n = c.box(h=Px(60.0), bg=0x224466FFL, fn() {
        c.text("first line \{item} second line third line", wrap=true) |> ignore
      })
      if item == 0 {
        c.bg_by(n, fn() {
          painted.val += 1
          0xCC6633FFL
        })
      }
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.frame_at(at + 16.0)
  let before = t.row(0).unwrap()
  let paints = painted.val
  t.wheel_told(100.0, 100.0, 0.0, 25.0, 0, at + 17.0)
  t.frame_at(at + 32.0)
  t.frame_at(at + 48.0)
  let after = t.row(0).unwrap()
  assert_true(after.1 < 0.0 && after.1 + 60.0 > 0.0, msg="row 0 is cut by the list's top: \{Repr(before)} -> \{Repr(after)}")
  // (kept as it is cut: painted whole once as it comes to the edge, kept as drawn wholly inside before; then drawn
  // from that as it goes on being cut)
  assert_eq(painted.val, paints + 1, msg="the row is painted once more as the list's edge first cuts it")
  let cut_paints = painted.val
  t.wheel_told(100.0, 100.0, 0.0, 10.0, 0, at + 49.0)
  t.frame_at(at + 64.0)
  t.frame_at(at + 80.0)
  let later = t.row(0).unwrap()
  assert_true(later.1 < after.1 && later.1 + 60.0 > 0.0, msg="row 0 moved on, still cut: \{Repr(after)} -> \{Repr(later)}")
  assert_eq(painted.val, cut_paints, msg="the cut row is drawn from what it kept")
}

///|
test "rows cut by the list's edges, drawn from what they kept, draw what a paint of them there draws" {
  let rows : ListRows[Int] = ListRows::new()
  let pressed : Array[Int] = []
  let t = Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 60.0, fn(k) {
      let item = items[k]
      let id = c.id("row/\{item}")
      c.on_press(id, fn() {
        pressed.push(item)
      })
      c.box(id~, h=Px(60.0), bg=0x224466FFL, fn() {
        c.text("first line \{item} second line third line", wrap=true) |> ignore
        c.box(w=Px(20.0), h=Px(10.0), bg=0xCC6633FFL, fn() {  }) |> ignore
      }) |> ignore
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  // (each frame painted alone compared with it built whole: the Tester fails where they differ)
  t.check_looks(true)
  t.set_rows_on_pixels(true)
  t.draw()
  let mut at = t.time()
  for _ in 0..<6 {
    t.wheel_told(100.0, 100.0, 0.0, 13.0, 0, at + 1.0)
    t.frame_at(at + 16.0)
    t.frame_at(at + 32.0)
    at = t.time()
  }
  let top = t.row(t.visible().0).unwrap()
  t.tap_once(100.0, dmax(top.1, 0.0) + 1.0)
  assert_eq(pressed, [t.visible().0], msg="the row cut at the top is pressed where it shows")
}

///|
/// Rows each with a round box and a square one that cut what they hold (words and a box past their edges), `corner`: a
/// box that cuts too in the round one's corner, cut by its curve (an outer of its own); row 0's round box counting its
/// paints in `painted`.
fn own_clips_rows(painted : Ref[Int], corner : Bool) -> Tester {
  let rows : ListRows[Int] = ListRows::new()
  Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 70.0, fn(k) {
      let item = items[k]
      c.box(h=Px(70.0), bg=0x224466FFL, fn() {
        let round = c.box(w=Px(120.0), h=Px(50.0), radius=12.0, clip=true, bg=0x335577FFL, fn() {
          if corner {
            // (3 in from its corner, not sharing it: the curve cuts into it, its outer)
            c.box(pad=3.0, fn() {
              c.box(w=Px(20.0), h=Px(20.0), clip=true, bg=0x77AA33FFL, fn() {
                c.box(w=Px(30.0), h=Px(30.0), bg=0xAA3377FFL, fn() {  }) |> ignore
              }) |> ignore
            }) |> ignore
          }
          c.text("round \{item} its second line its third line and on", wrap=true) |> ignore
          c.box(w=Px(200.0), h=Px(20.0), bg=0xCC6633FFL, fn() {  }) |> ignore
        })
        if item == 0 {
          c.bg_by(round, fn() {
            painted.val += 1
            0x335577FFL
          })
        }
        c.box(w=Px(120.0), h=Px(50.0), clip=true, bg=0x557733FFL, fn() {
          c.text("square \{item} its second line its third line and on", wrap=true) |> ignore
        }) |> ignore
      }) |> ignore
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
}

///|
/// `t` wheeled down 7 points at a time, `steps` times, a frame each way between.
fn own_clips_scroll(t : Tester, steps : Int) -> Unit {
  let mut at = t.time()
  for _ in 0..<steps {
    t.wheel_told(100.0, 100.0, 0.0, 7.0, 0, at + 1.0)
    t.frame_at(at + 16.0)
    t.frame_at(at + 32.0)
    at = t.time()
  }
}

///|
test "a row's own clips cut by the list's top, round and square, drawn from what it kept as a paint there draws them" {
  let painted = Ref(0)
  let t = own_clips_rows(painted, false)
  // (each frame painted alone compared with it built whole: the Tester fails where they differ)
  t.check_looks(true)
  t.set_rows_on_pixels(true)
  t.draw()
  own_clips_scroll(t, 12)
  assert_true(t.visible().0 >= 1, msg="the list scrolled past its first row")
}

///|
test "a row's own clips cut by the list's top are drawn from what it kept" {
  let painted = Ref(0)
  let t = own_clips_rows(painted, false)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  // (row 0 cut by the top from the first step: painted whole once there)
  own_clips_scroll(t, 2)
  let row = t.row(0).unwrap()
  assert_true(row.1 < 0.0, msg="row 0 is cut by the list's top: \{Repr(row)}")
  let paints = painted.val
  own_clips_scroll(t, 4)
  let later = t.row(0).unwrap()
  assert_true(later.1 < row.1 && later.1 + 70.0 > 0.0, msg="row 0 moved on, still cut: \{Repr(row)} -> \{Repr(later)}")
  assert_eq(painted.val, paints, msg="the cut row, its own clips cut, is drawn from what it kept")
  let kept = row_kept_drawing(0)
  assert_true(kept is Some((true, true, _)), msg="kept as painted whole: \{Repr(kept)}")
}

///|
test "a row with a clip of its own in another's curve, cut by the list's edge, is painted as it is, as a paint there" {
  let painted = Ref(0)
  let t = own_clips_rows(painted, true)
  t.check_looks(true)
  t.set_rows_on_pixels(true)
  t.draw()
  own_clips_scroll(t, 12)
  assert_true(t.visible().0 >= 1, msg="the list scrolled past its first row")
}

///|
test "a row with a clip of its own in another's curve is not kept as drawn while the list's edge cuts it" {
  let painted = Ref(0)
  let t = own_clips_rows(painted, true)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  own_clips_scroll(t, 2)
  let paints = painted.val
  own_clips_scroll(t, 4)
  assert_true(t.row(0).unwrap().1 < 0.0)
  assert_true(painted.val > paints, msg="painted again while it is cut")
  match row_kept_drawing(0) {
    Some((valid, _, _)) => assert_false(valid, msg="not kept as drawn while the list's edge cuts it")
    None => ()
  }
}

///|
/// A list whose first row is far taller than how far a row is painted whole past the list's clip (half the clip again:
/// row_whole_rect): thirty lines of words, then a box that cuts what it holds at its foot; the row counting its paints.
fn tall_row_list(painted : Ref[Int], alike? : Bool = false) -> Tester {
  let rows : ListRows[Int] = ListRows::new()
  // (`alike`: its lines alike, and with every letter its foot has, so what of them lies past the list's clip is drawn
  // with glyphs its first lines asked for; else each its own, glyphs past the clip not asked for till they show,
  // rec_glyph_early)
  let lines = if alike {
    Array::make(30, "a line of the tall row, and below that at its foot")
  } else {
    Array::makei(30, fn(l) { "line \{l} of the tall row" })
  }
  Tester::new(fn(c) {
    let ids = Array::makei(20, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      let item = items[k]
      if item == 0 {
        let n = c.box(bg=0x224466FFL, fn() {
          for line in lines {
            c.text(line, wrap=false) |> ignore
          }
          c.box(w=Px(120.0), h=Px(40.0), radius=10.0, clip=true, bg=0x335577FFL, fn() {
            c.text("at its foot", wrap=false) |> ignore
            c.text("and below that", wrap=false) |> ignore
          }) |> ignore
        })
        c.bg_by(n, fn() {
          painted.val += 1
          0x224466FFL
        })
      } else {
        c.box(h=Px(40.0), bg=0x446622FFL, fn() { c.text("row \{item}", wrap=false) |> ignore }) |> ignore
      }
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
}

///|
test "a row past how far it is painted whole draws what comes into view as a paint there draws it" {
  let painted = Ref(0)
  let t = tall_row_list(painted)
  // (each frame painted alone compared with it built whole, the row's words and its foot coming into view)
  t.check_looks(true)
  t.set_rows_on_pixels(true)
  t.draw()
  let row = t.row(0).unwrap()
  assert_true(row.3 > 160.0 * 2.0 + 160.0, msg="the row reaches past how far it is painted whole: \{Repr(row)}")
  // (its lines past the list's clip have glyphs not yet asked for: not drawn there, so it is kept drawn only short of
  // them, rec_reach)
  let kept = row_kept_drawing(0)
  assert_true(kept is Some((true, true, _)), msg="kept painted whole: \{Repr(kept)}")
  let reach = row_kept_reach(0)
  assert_true(reach is Some((b, r)) && r < b, msg="kept short of its lines with glyphs not asked for: \{Repr(reach)}")
  own_clips_scroll(t, 80)
  let later = t.row(0).unwrap()
  assert_true(later.1 + later.3 < 160.0, msg="its foot came into view: \{Repr(later)}")
}

///|
test "a row past how far it is painted whole is drawn from what it kept while the list's clip is inside that" {
  let painted = Ref(0)
  let t = tall_row_list(painted, alike=true)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let first = painted.val
  // (7 points a step: 35 in, inside the half clip, 80, painted whole past it)
  let was = row_kept_drawing(0)
  assert_true(was is Some((true, true, _)), msg="painted whole: \{Repr(was)}")
  own_clips_scroll(t, 5)
  assert_eq(painted.val, first, msg="drawn from what it kept")
  assert_eq(row_kept_drawing(0), was, msg="the same kept, not painted whole again")
  own_clips_scroll(t, 12)
  let again = painted.val
  let now = row_kept_drawing(0)
  // (painted whole again where the list's clip went past how far it was, not painted as it is: kept, whole, from
  // another place)
  assert_true(again > first && again <= first + 2, msg="painted again once the clip went past how far it was: \{first} -> \{again}")
  match (was, now) {
    (Some((_, _, y0)), Some((true, true, y1))) => assert_true(y1 < y0, msg="painted whole again further on: \{Repr(was)} -> \{Repr(now)}")
    _ => fail("kept as painted whole again: \{Repr(was)} -> \{Repr(now)}")
  }
}

///|
/// Row `item`'s targets as kept with what it drew: whether they are kept, and where the row was as they were found.
fn row_kept_targets(item : Int) -> (Bool, Double)? {
  for _, rn in kept_nodes {
    if rn.item == item {
      return match rn.drawing {
        Some(d) => Some((d.hits_valid, d.hits_y))
        None => None
      }
    }
  }
  None
}

///|
test "a scrolled row's targets are said again from what it kept, and pressed where it shows, cut by the list's edge" {
  let rows : ListRows[Int] = ListRows::new()
  let pressed : Array[Int] = []
  let t = Tester::new(fn(c) {
    let ids = Array::makei(30, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 60.0, fn(k) {
      let item = items[k]
      let id = c.id("row/\{item}")
      c.on_press(id, fn() {
        pressed.push(item)
      })
      c.box(id~, h=Px(60.0), bg=0x224466FFL, fn() { c.text("row \{item}", wrap=false) |> ignore }) |> ignore
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.frame_at(at + 16.0)
  t.frame_at(at + 32.0)
  let found = row_kept_targets(1)
  assert_true(found is Some((true, _)), msg="row 1's targets kept: \{Repr(found)}")
  // (moved up 25: row 0 cut by the top, row 1 moved; their targets said again from what was kept, not found again)
  let said : Array[Int] = []
  row_targets_again.val = Some(said)
  t.wheel_told(100.0, 100.0, 0.0, 25.0, 0, at + 33.0)
  t.frame_at(at + 48.0)
  t.frame_at(at + 64.0)
  t.frame_at(at + 80.0)
  let top = t.row(0).unwrap()
  assert_true(top.1 < 0.0 && top.1 + 60.0 > 0.0, msg="row 0 cut by the top: \{Repr(top)}")
  assert_true(said.contains(1), msg="row 1's targets said again from what it kept: \{Repr(said)}")
  assert_eq(row_kept_targets(1), found, msg="row 1's targets said again from where they were found")
  // (row 0, cut by the top: found again whole once, then said again from that as it goes on being cut)
  let cut = row_kept_targets(0)
  assert_true(cut is Some((true, _)), msg="row 0's targets kept as it is cut: \{Repr(cut)}")
  said.clear()
  t.wheel_told(100.0, 100.0, 0.0, 10.0, 0, at + 81.0)
  t.frame_at(at + 96.0)
  t.frame_at(at + 112.0)
  assert_true(t.row(0).unwrap().1 + 60.0 > 0.0, msg="row 0 still in view")
  assert_true(said.contains(0), msg="row 0's targets said again, cut: \{Repr(said)}")
  assert_true(said.contains(1), msg="row 1's targets said again: \{Repr(said)}")
  assert_eq(row_kept_targets(0), cut, msg="row 0's targets said again from where they were found, cut")
  row_targets_again.val = None
  t.tap_once(100.0, 2.0)
  t.tap_once(100.0, t.row(1).unwrap().1 + 2.0)
  assert_eq(pressed, [0, 1], msg="pressed where they show, row 0 in what the top leaves of it")
}

///|
/// A list of kept rows in a layer over a box that counts its presses; the layer passes a finger on while `pass` says
/// so, and row 0 passes it on of its own while `row_passes` does.
fn passing_rows(
  pass : @signals.Signal[Bool],
  row_passes : Bool,
  pressed : Array[Int],
  under : Ref[Int],
  first : Ref[Int],
) -> Tester {
  let rows : ListRows[Int] = ListRows::new()
  Tester::new(fn(c) {
    let base = c.id("under")
    c.on_press(base, fn() {
      under.val += 1
    })
    c.box(id=base, w=Px(300.0), h=Px(160.0), fn() {  }) |> ignore
    let o = c.overlay("rows-over", fn() {
      c.box(w=Px(300.0), h=Px(160.0), fn() {
        let ids = Array::makei(30, fn(i) { i })
        let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
        c.list("rows", items.length(), 40.0, fn(k) {
          let item = items[k]
          let id = c.id("row/\{item}")
          if item == 0 {
            first.val = id
          }
          c.on_press(id, fn() {
            pressed.push(item)
          })
          let b = c.box(id~, h=Px(40.0), bg=0x224466FFL, fn() { c.text("row \{item}", wrap=false) |> ignore })
          if row_passes && item == 0 {
            c.passes(b)
          }
        }, rows_read=true, sized=rows.sized())
        |> ignore
      })
      |> ignore
    })
    if pass.get() {
      c.passes(o.node)
    }
  }, w=300.0, h=160.0)
}

///|
test "a kept row's targets in a layer that comes to pass a finger on pass it on, not said again" {
  let pass = @signals.signal(false)
  let pressed : Array[Int] = []
  let under = Ref(0)
  let first = Ref(0)
  let t = passing_rows(pass, false, pressed, under, first)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  t.frame_at(t.time() + 16.0)
  t.frame_at(t.time() + 16.0)
  t.tap_once(100.0, 20.0)
  assert_eq((pressed, under.val), ([0], 0), msg="row 0 pressed while its layer holds the finger")
  // (moved up 10: its targets found as it moves, and kept)
  let at = t.time()
  t.wheel_told(100.0, 100.0, 0.0, 10.0, 0, at + 1.0)
  t.frame_at(at + 16.0)
  t.frame_at(at + 32.0)
  t.frame_at(at + 48.0)
  let kept = row_kept_targets(0)
  assert_true(kept is Some((true, _)), msg="row 0's targets kept to be said again: \{Repr(kept)}")
  let said : Array[Int] = []
  row_targets_again.val = Some(said)
  pass.set(true)
  t.frame_at(t.time() + 16.0)
  row_targets_again.val = None
  let c = g()
  assert_true(c.hit_ids.contains(first.val), msg="row 0's target found")
  let passes = c.passes.contains(first.val)
  t.tap_once(100.0, 20.0)
  assert_eq((pressed, under.val), ([0], 1), msg="the box under the layer pressed through row 0: pressed \{Repr(pressed)}, under \{under.val}, said again \{Repr(said)}")
  assert_true(passes, msg="row 0's target passes the finger on")
}

///|
test "a kept row that passes a finger on of its own keeps none of its targets to say again" {
  let pass = @signals.signal(false)
  let pressed : Array[Int] = []
  let under = Ref(0)
  let first = Ref(0)
  let t = passing_rows(pass, true, pressed, under, first)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.frame_at(at + 16.0)
  t.frame_at(at + 32.0)
  // (moved up 10: its targets found again as it moves, row 1's said again)
  let said : Array[Int] = []
  row_targets_again.val = Some(said)
  t.wheel_told(100.0, 100.0, 0.0, 10.0, 0, at + 33.0)
  t.frame_at(at + 48.0)
  t.frame_at(at + 64.0)
  t.frame_at(at + 80.0)
  row_targets_again.val = None
  assert_true(!said.contains(0) && said.contains(1), msg="row 1's said again, row 0's not: \{Repr(said)}")
  let c = g()
  assert_true(c.passes.contains(first.val), msg="row 0's target passes the finger on")
  let top = t.row(0).unwrap().1
  t.tap_once(100.0, top + 20.0)
  t.tap_once(100.0, t.row(1).unwrap().1 + 20.0)
  assert_eq((pressed, under.val), ([1], 1), msg="row 0 pressed through to the box under, row 1 pressed: pressed \{Repr(pressed)}, under \{under.val}")
}

///|
test "a kept row's node marked to pass a finger on from another row's build passes it on, its targets not said again" {
  let turn = @signals.signal(false)
  let rows : ListRows[Int] = ListRows::new()
  let first_index = Ref(-1)
  let first_id = Ref(0)
  let first_builds = Ref(0)
  let marked = Ref(false)
  let under = Ref(0)
  let pressed : Array[Int] = []
  let t = Tester::new(fn(c) {
    let back = c.id("under")
    c.on_press(back, fn() {
      under.val += 1
    })
    c.box(id=back, w=Px(300.0), h=Px(160.0), fn() {  }) |> ignore
    c.overlay("rows-over", fn() {
      c.box(w=Px(300.0), h=Px(160.0), fn() {
        let ids = Array::makei(30, fn(i) { i })
        let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
        c.list("rows", items.length(), 40.0, fn(k) {
          let item = items[k]
          let id = c.id("row/\{item}")
          c.on_press(id, fn() {
            pressed.push(item)
          })
          if item == 0 {
            first_index.val = c.box(id~, h=Px(40.0), bg=0x224466FFL, fn() { c.text("row 0", wrap=false) |> ignore })
            first_id.val = id
            first_builds.val += 1
          } else {
            // (row 0's node, kept from when it was built and still the same one: marked by another row's build)
            if item == 1 && turn.get() && first_index.val >= 0 && c.node_id(first_index.val) == first_id.val {
              marked.val = true
              c.passes(first_index.val)
            }
            c.box(id~, h=Px(40.0), bg=0x224466FFL, fn() { c.text("row \{item}", wrap=false) |> ignore }) |> ignore
          }
        }, rows_read=true, sized=rows.sized())
        |> ignore
      })
      |> ignore
    })
    |> ignore
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  let at = t.time()
  t.frame_at(at + 16.0)
  t.frame_at(at + 32.0)
  t.wheel_told(100.0, 100.0, 0.0, 10.0, 0, at + 33.0)
  t.frame_at(at + 48.0)
  t.frame_at(at + 64.0)
  t.frame_at(at + 80.0)
  let kept = row_kept_targets(0)
  assert_true(kept is Some((true, _)), msg="row 0's targets kept to be said again: \{Repr(kept)}")
  let before = first_builds.val
  let said : Array[Int] = []
  row_targets_again.val = Some(said)
  turn.set(true)
  t.frame_at(at + 96.0)
  row_targets_again.val = None
  let c = g()
  let passes = c.passes.contains(first_id.val)
  assert_true(marked.val, msg="row 1 marked row 0's node")
  assert_eq(first_builds.val, before, msg="row 0 not built again")
  assert_true(c.hit_ids.contains(first_id.val), msg="row 0's target found")
  t.tap_once(100.0, 20.0)
  assert_eq((pressed, under.val), ([], 1), msg="the box under pressed through row 0: pressed \{Repr(pressed)}, under \{under.val}, said again \{Repr(said)}")
  assert_true(passes, msg="row 0's target passes the finger on")
}

///|
/// A list whose row 0 is 40 lines of rich words, its paint counted: alike but its 15th to 18th, in letters none of the
/// others has (their glyphs first asked for as they show); the other rows short.
fn cold_rich_list(painted : Ref[Int]) -> Tester {
  let rows : ListRows[Int] = ListRows::new()
  Tester::new(fn(c) {
    let ids = Array::makei(20, fn(i) { i })
    let (items, _) = rows.rows(c, ids.map(fn(i) { "row/" + i.to_string() }), ids, fn(_) { "" })
    c.list("rows", items.length(), 40.0, fn(k) {
      let item = items[k]
      if item == 0 {
        let n = c.box(bg=0x224466FFL, fn() {
          for l in 0..<40 {
            let words = if l >= 14 && l < 18 { "jumpy quiz vex" } else { "a line of the tall row" }
            c.rich([@text.plain(words)], key="line/\{l}", wrap=false) |> ignore
          }
        })
        c.bg_by(n, fn() {
          painted.val += 1
          0x224466FFL
        })
      } else {
        c.box(h=Px(40.0), bg=0x446622FFL, fn() { c.text("row \{item}", wrap=false) |> ignore }) |> ignore
      }
    }, rows_read=true, sized=rows.sized()) |> ignore
  }, w=300.0, h=160.0)
}

///|
/// Row `item`'s drawing's band and how far it was kept drawn, at their top.
fn row_kept_reach_top(item : Int) -> (Double, Double)? {
  for _, rn in kept_nodes {
    if rn.item == item {
      return match rn.drawing {
        Some(d) if d.band.length() == 4 && d.reach.length() == 4 => Some((d.band[1], d.reach[1]))
        _ => None
      }
    }
  }
  None
}

///|
/// Jumped in one step so that row 0's 18th line ends 40 above the list's top (its lines above never shown, those
/// below alike), then moved back up `steps` times by 7.
fn cold_rich_back(t : Tester, steps : Int) -> Unit {
  let mut at = t.time()
  let line = t.row(0).unwrap().3 / 40.0
  t.wheel_told(100.0, 100.0, 0.0, (18.0 * line + 40.0).round(), 0, at + 1.0)
  t.frame_at(at + 16.0)
  t.frame_at(at + 32.0)
  at = t.time()
  for _ in 0..<steps {
    t.wheel_told(100.0, 100.0, 0.0, -7.0, 0, at + 1.0)
    t.frame_at(at + 16.0)
    t.frame_at(at + 32.0)
    at = t.time()
  }
}

///|
test "a rich row cut by the top with glyphs above not yet asked for is drawn from what it kept short of them, painted again as they come" {
  let painted = Ref(0)
  let t = cold_rich_list(painted)
  t.check_looks(false)
  t.set_rows_on_pixels(true)
  t.draw()
  cold_rich_back(t, 0)
  let top = t.row(0).unwrap()
  assert_true(top.1 < -100.0 && top.1 + top.3 > 160.0, msg="row 0 cut by both edges: \{Repr(top)}")
  let kept = row_kept_drawing(0)
  assert_true(kept is Some((true, true, _)), msg="kept painted whole: \{Repr(kept)}")
  let reach = row_kept_reach_top(0)
  assert_true(reach is Some((b, r)) && r > b, msg="kept short of its lines above with glyphs not asked for: \{Repr(reach)}")
  let (_, r) = reach.unwrap()
  let (_, _, y0) = kept.unwrap()
  // (moved back up while the list's clip, its top at 0, stays inside how far it was kept, moved as the row is: drawn
  // from what it kept, not painted)
  let first = painted.val
  let mut at = t.time()
  let mut moved = 0
  while moved < 30 && t.row(0).unwrap().1 + 7.0 - y0 + r <= 0.0 {
    t.wheel_told(100.0, 100.0, 0.0, -7.0, 0, at + 1.0)
    t.frame_at(at + 16.0)
    t.frame_at(at + 32.0)
    at = t.time()
    moved = moved + 1
  }
  let inside = t.row(0).unwrap().1
  assert_true(moved >= 2 && inside - top.1 >= 14.0, msg="moved back up inside how far it was kept: \{moved} steps, \{top.1} -> \{inside}, reach \{r} from \{y0}")
  assert_true(inside - y0 + r <= 0.0, msg="the list's clip still inside how far it was kept")
  assert_eq(painted.val, first, msg="drawn from what it kept while inside how far it was kept")
  assert_eq(row_kept_drawing(0), kept, msg="the same kept, from where it was painted")
  // (on past it: painted again, its lines coming into view asked for as they show)
  for _ in 0..<12 {
    t.wheel_told(100.0, 100.0, 0.0, -7.0, 0, at + 1.0)
    t.frame_at(at + 16.0)
    t.frame_at(at + 32.0)
    at = t.time()
  }
  let past = t.row(0).unwrap().1
  assert_true(past - y0 + r > 0.0, msg="the list's clip went past how far it was kept: \{past} from \{y0}, reach \{r}")
  assert_true(painted.val > first, msg="painted again once the list's clip went past how far it was kept")
}

///|
test "a rich row cut by the top with glyphs above not yet asked for draws what comes into view as a paint there draws it" {
  let painted = Ref(0)
  let t = cold_rich_list(painted)
  // (each frame painted alone compared with it built whole, its lines above coming into view)
  t.check_looks(true)
  t.set_rows_on_pixels(true)
  t.draw()
  cold_rich_back(t, 40)
}
