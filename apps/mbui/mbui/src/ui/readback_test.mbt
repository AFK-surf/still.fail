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
