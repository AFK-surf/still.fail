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
