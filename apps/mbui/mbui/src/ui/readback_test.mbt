// What the view reads of the layout as it builds, read back (readback.mbt): a box's laid rect, a list's rows.

///|
test "a box sized by another's laid height follows it in the frame it changes, not a frame late" {
  let tall = Ref::new(40.0)
  let seen : Array[(Double, Double)] = []
  let t = @ui.Tester::new(
    fn(c) {
      let a = c.id("a")
      let h = match c.laid_rect(a) {
        Some((_, _, _, h)) => h
        None => 0.0
      }
      c.column(fn() {
        c.box(w=Px(50.0), h=Px(tall.val), id=a, fn() {  }) |> ignore
        c.box(w=Px(50.0), h=Px(h), fn() {  }) |> ignore
        c.text("below", wrap=false) |> ignore
      })
      |> ignore
      seen.push((tall.val, h))
    },
    w=200.0,
    h=300.0,
  )
  assert_eq(seen[seen.length() - 1], (40.0, 40.0))
  tall.val = 70.0
  // one frame, the one that takes the change: built again in it from the box as laid out now
  t.frame()
  assert_eq(seen[seen.length() - 1], (70.0, 70.0))
  // and drawn so: what is under the second box is under 70 + 70
  let (_, y, _, _) = t.rect_of("below").unwrap()
  assert_eq(y, 140.0)
  t.assert_idle()
}

///|
test "a row's height read as the view builds is this frame's, in the frame it changes" {
  let tall = Ref::new(40.0)
  let t = @ui.Tester::new(
    fn(c) {
      let h = c.list_row_height("rows", 0)
      c.column(fn() {
        c.text("row 0: \{h}", wrap=false) |> ignore
        c.list("rows", 3, 40.0, fn(i) {
          c.box(w=Fill(1.0), h=Px(if i == 0 { tall.val } else { 40.0 }), fn() {  }) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=300.0,
  )
  assert_true(t.rect_of("row 0: Some(40)") is Some(_))
  tall.val = 90.0
  t.frame()
  assert_true(t.rect_of("row 0: Some(90)") is Some(_))
  t.assert_idle()
}

///|
test "panic a box sized by its own laid width never holds still, and says which" {
  let t = @ui.Tester::new(
    fn(c) {
      let a = c.id("a")
      let w = match c.laid_rect(a) {
        Some((_, _, w, _)) => w + 10.0
        None => 10.0
      }
      c.box(w=Px(w), h=Px(10.0), id=a, fn() {  }) |> ignore
    },
    w=500.0,
    h=100.0,
  )
  t.draw()
}

///|
test "words read before they are first laid out are there in the frame that lays them out" {
  let read : Array[Bool] = []
  let t = @ui.Tester::new(
    fn(c) {
      read.push(c.words_of("w") is Some(_))
      let b = c.column(w=Px(100.0), fn() { c.rich([@ui.plain("hello")], size=10.0) |> ignore })
      c.words(b, "w")
    },
    w=300.0,
    h=100.0,
  )
  // the first frame: none as it first built, there as it was built again
  assert_eq(read, [false, true])
  t.assert_idle()
}

///|
test "a list in a scope of its own is read back by the id it has there" {
  let tall = Ref::new(40.0)
  let t = @ui.Tester::new(
    fn(c) {
      c.scope(7, fn() {
        // (where it is read too: read back by the same id, still once laid out)
        ignore(c.list_place("rows"))
        let h = c.list_row_height("rows", 0)
        c.column(fn() {
          c.text("row 0: \{h}", wrap=false) |> ignore
          c.list("rows", 3, 40.0, fn(i) {
            c.box(w=Fill(1.0), h=Px(if i == 0 { tall.val } else { 40.0 }), fn() {  }) |> ignore
          })
          |> ignore
        })
        |> ignore
      })
    },
    w=200.0,
    h=300.0,
  )
  // laid out in the first frame, read back there: not a frame late, and still from then on
  assert_true(t.rect_of("row 0: Some(40)") is Some(_))
  tall.val = 90.0
  t.frame()
  assert_true(t.rect_of("row 0: Some(90)") is Some(_))
  t.assert_idle()
}

///|
test "a box sized by another's laid size is built once a frame while that box only moves, again as it grows" {
  let x = Ref::new(0.0)
  let tall = Ref::new(40.0)
  let builds = Ref::new(0)
  let t = @ui.Tester::new(
    fn(c) {
      builds.val += 1
      let a = c.id("a")
      let h = match c.laid_size(a) {
        Some((_, h)) => h
        None => 0.0
      }
      c.box(pl=x.val, fn() {
        c.column(fn() {
          c.box(w=Px(50.0), h=Px(tall.val), id=a, fn() {  }) |> ignore
          c.box(w=Px(50.0), h=Px(h), fn() {  }) |> ignore
          c.text("below", wrap=false) |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=300.0,
  )
  // moved (as a page slides): one build a frame, the size read as it was
  builds.val = 0
  x.val = 30.0
  t.frame()
  assert_eq(builds.val, 1)
  // grown: built again in that frame, from its size now
  builds.val = 0
  tall.val = 70.0
  t.frame()
  assert_eq(builds.val, 2)
  let (_, y, _, _) = t.rect_of("below").unwrap()
  assert_eq(y, 140.0)
  t.assert_idle()
}

///|
test "a tap taken into state in the build that sees it holds when the frame is built again for a read back" {
  let open = Ref::new(false)
  let t = @ui.Tester::new(
    fn(c) {
      let b = c.id("button")
      // what the tap says, kept as it is seen (the next builds of the frame see no tap)
      if c.clicked(b) {
        open.val = !open.val
      }
      let a = c.id("panel")
      let h = match c.laid_size(a) {
        Some((_, h)) => h
        None => 0.0
      }
      c.column(fn() {
        c.box(w=Px(100.0), h=Px(40.0), id=b, fn() {  }) |> ignore
        // opened, the panel is taller: read back in the frame the tap is taken in
        c.box(w=Px(100.0), h=Px(if open.val { 80.0 } else { 20.0 }), id=a, fn() {  }) |> ignore
        c.box(w=Px(100.0), h=Px(h), fn() {  }) |> ignore
        c.text("below", wrap=false) |> ignore
      })
      |> ignore
    },
    w=300.0,
    h=400.0,
  )
  t.tap(50.0, 20.0)
  // taken once (not undone by the frame's next build), and that build placed by the panel as the tap made it: the
  // third box is as tall as the panel opened, in the frame that took the tap
  assert_true(open.val)
  let (_, y, _, _) = t.rect_of("below").unwrap()
  assert_eq(y, 40.0 + 80.0 + 80.0)
  t.assert_idle()
}

///|
/// The builds of each frame, by its number.
fn builds_a_frame(seen : Map[Int, Int], c : @ui.Ctx) -> Unit {
  let f = c.frame_number()
  seen[f] = seen.get(f).unwrap_or(0) + 1
}

///|
test "a list dragged that the view reads nothing of is built once a frame" {
  let seen : Map[Int, Int] = {}
  let t = @ui.Tester::new(
    fn(c) {
      builds_a_frame(seen, c)
      c.list("rows", 60, 40.0, fn(_) { c.box(w=Fill(1.0), h=Px(40.0), fn() {  }) |> ignore }) |> ignore
    },
    w=200.0,
    h=300.0,
  )
  // (its builds counted: the Tester's own builds of a frame again, to check it by, left out)
  t.check_looks(false)
  seen.clear()
  // rows come into view and leave it at every other step of the drag
  t.drag(100.0, 280.0, 100.0, 20.0, steps=13)
  assert_true(t.visible().0 > 0)
  for f, n in seen {
    assert_eq((f, n), (f, 1))
  }
}

///|
test "a list's rows in view read as the view builds are this frame's, built again as they change" {
  let t = @ui.Tester::new(
    fn(c) {
      let first = match c.list_info("rows") {
        Some(i) => i.first
        None => -1
      }
      c.column(h=Fill(1.0), fn() {
        c.text("first \{first}", wrap=false) |> ignore
        c.list("rows", 60, 40.0, fn(_) { c.box(w=Fill(1.0), h=Px(40.0), fn() {  }) |> ignore }) |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=300.0,
  )
  t.drag(100.0, 280.0, 100.0, 20.0, steps=13)
  // what is drawn says the row the list shows first in that very frame, not the one the frame before showed
  let first = t.visible().0
  assert_true(first > 0)
  assert_true(t.rect_of("first \{first}") is Some(_))
}

///|
test "what is built from a list's end alone is built again as it gets there, not at every step before" {
  let seen : Map[Int, Int] = {}
  let t = @ui.Tester::new(
    fn(c) {
      builds_a_frame(seen, c)
      let end = match c.list_info_as("rows", fn(i) { i.map(fn(i) { i.at_end }) }) {
        Some(i) => i.at_end
        None => false
      }
      c.column(h=Fill(1.0), fn() {
        c.text(if end { "at its end" } else { "on its way" }, wrap=false) |> ignore
        c.list("rows", 12, 40.0, fn(_) { c.box(w=Fill(1.0), h=Px(40.0), fn() {  }) |> ignore }) |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=300.0,
  )
  assert_true(t.rect_of("on its way") is Some(_))
  // (its builds counted: the Tester's own builds of a frame again, to check it by, left out)
  t.check_looks(false)
  seen.clear()
  // to its end in a drag, rows coming and going on the way: built again only in the frame it gets there, drawn
  // there as at its end
  t.drag(100.0, 280.0, 100.0, 20.0, steps=13)
  assert_true(t.at_end())
  assert_true(t.rect_of("at its end") is Some(_))
  assert_eq(seen.values().filter(fn(n) { n > 1 }).count(), 1)
}

///|
test "words kept on a row dragged that nothing reads are built once a frame" {
  let seen : Map[Int, Int] = {}
  let t = @ui.Tester::new(
    fn(c) {
      builds_a_frame(seen, c)
      c.list("rows", 60, 40.0, fn(i) {
        let b = c.box(w=Fill(1.0), h=Px(40.0), fn() { c.rich([@ui.plain("row \{i}")], size=10.0) |> ignore })
        // (as a message's under a finger is kept, for a long press to pick from)
        if i == 3 {
          c.words(b, "w")
        }
      })
      |> ignore
    },
    w=200.0,
    h=300.0,
  )
  // (its builds counted: the Tester's own builds of a frame again, to check it by, left out)
  t.check_looks(false)
  seen.clear()
  // the row moves with the list, in view all the way
  t.drag(100.0, 280.0, 100.0, 200.0, steps=4)
  assert_true(t.ctx().words_of("w") is Some(_))
  for f, n in seen {
    assert_eq((f, n), (f, 1))
  }
}

///|
test "what a box shows across: its innermost parts that show something, inside it, but those of a box named" {
  let seen : Array[(Double, Double)?] = []
  let t = @ui.Tester::new(
    fn(c) {
      let page = c.id("page")
      seen.push(c.shown_across(page, but="bar"))
      c.box(dir=Row, w=Px(300.0), h=Px(200.0), id=page, fn() {
        c.column(fn() {
          // its bar, across it whole: not counted
          c.box(w=Px(300.0), moves="bar", fn() { c.text("the bar across", wrap=false) |> ignore }) |> ignore
          // a ground reaching past what is in it: only the words in it count
          c.box(w=Px(260.0), h=Px(40.0), pl=40.0, bg=0x112233FFL, fn() { c.text("shown", wrap=false) |> ignore })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    w=400.0,
    h=300.0,
  )
  // the first frame asks before anything was laid out: none; the next, the words', from their left at 40
  assert_eq(seen[0], None)
  t.frame()
  let (x, _, w, _) = t.rect_of("shown").unwrap()
  assert_eq(seen[seen.length() - 1], Some((x, x + w)))
  assert_eq(x, 40.0)
}

///|
test "a box built tallest: never shorter than the tallest it has been while so, as tall as what it holds again once not" {
  let tall = Ref::new(40.0)
  let held = Ref::new(true)
  let t = @ui.Tester::new(
    fn(c) {
      c.column(fn() {
        c.box(id=c.id("held"), taps=false, tallest=held.val, fn() {
          c.box(w=Px(50.0), h=Px(tall.val), fn() {  }) |> ignore
        })
        |> ignore
        c.text("below", wrap=false) |> ignore
      })
      |> ignore
    },
    w=200.0,
    h=300.0,
  )
  let below = fn() { t.rect_of("below").unwrap().1 }
  assert_eq(below(), 40.0)
  // taller: grown in the frame it changes; shorter again: held
  tall.val = 70.0
  t.frame()
  assert_eq(below(), 70.0)
  tall.val = 20.0
  t.frame()
  assert_eq(below(), 70.0)
  t.frame()
  assert_eq(below(), 70.0)
  // let go: as what it holds, and held from there next time
  held.val = false
  t.frame()
  assert_eq(below(), 20.0)
  held.val = true
  tall.val = 30.0
  t.frame()
  assert_eq(below(), 30.0)
}
