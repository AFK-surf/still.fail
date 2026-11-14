// mbui's shots (shot.mbt): what a view builds drawn whole as one PNG, however long, never on the screen.

///|
fn png_be32(a : Array[Byte], at : Int) -> Int {
  (a[at].to_int() << 24) | (a[at + 1].to_int() << 16) | (a[at + 2].to_int() << 8) | a[at + 3].to_int()
}

///|
test "a shot six windows tall: one PNG of it all at the window's scale, taken in the frame it was asked in, none of it on the screen" {
  let take = Ref(false)
  let got : Ref[Bytes?] = Ref(None)
  let told = Ref(0)
  let t = @ui.Tester::new(
    fn(c) {
      c.box(w=Fill(1.0), h=Px(40.0), bg=0xFF0000FFL, fn() {  }) |> ignore
      if take.val {
        take.val = false
        c.take_shot("long", fn(png) {
          got.val = png
          told.val = told.val + 1
        })
      }
      c.shot("long", 150.0, fn() {
        for i in 0..<30 {
          c.box(w=Fill(1.0), h=Px(25.0), bg=0x336699FFL, fn() { c.text("row \{i}") |> ignore }) |> ignore
        }
      })
    },
    w=200.0,
    h=120.0,
    scale=2.0,
  )
  let before = t.instances()
  take.val = true
  t.draw()
  assert_eq(told.val, 1)
  let png = got.val.unwrap().to_array()
  assert_eq(png[1:4].to_owned(), [b'P', b'N', b'G'])
  // 150 × 750 points, two pixels a point
  assert_eq((png_be32(png, 16), png_be32(png, 20)), (300, 1500))
  // what the screen shows is as it was; the shot's words are nowhere once it is taken
  assert_eq(t.instances(), before)
  assert_true(t.find("row 3") is None)
  t.assert_idle()
}

///|
test "a shot whose view no longer builds it is let go, never told" {
  let take = Ref(false)
  let shown = Ref(true)
  let told = Ref(0)
  let t = @ui.Tester::new(
    fn(c) {
      if take.val {
        take.val = false
        c.take_shot("gone", fn(_) { told.val = told.val + 1 })
      }
      if shown.val {
        c.text("here") |> ignore
      }
    },
    w=200.0,
    h=120.0,
  )
  take.val = true
  t.draw()
  t.draw()
  assert_eq(told.val, 0)
  t.assert_idle()
  ignore(shown)
}

///|
/// What a picture made as nodes shows (take_picture's `make`): 30 rows 25 tall, each its words.
fn picture_rows(b : @view.View) -> Unit {
  for i in 0..<30 {
    b.box(fn(r) { r.height(Is(Some(25.0))).ground(Is(0x336699FFL)).words(Is("row \{i}")) |> ignore }) |> ignore
  }
}

///|
test "a picture made as nodes, asked at a cause: one PNG of all of it at its own scale, its words in order, the window's tree drawn as it was" {
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=120.0, scale=1.0)
  @ui.set_view_app(fn(root) {
    root.box(fn(b) { b.height(Is(Some(40.0))).ground(Is(0xFF0000FFL)).words(Is("here")) |> ignore }) |> ignore
  })
  t.draw()
  let before = t.instances()
  let got : Ref[Bytes?] = Ref(None)
  let told = Ref(0)
  @ui.take_picture("rows", 150.0, picture_rows, fn(png) {
    got.val = png
    told.val += 1
  }, scale=2.0)
  t.draw()
  assert_eq(told.val, 1)
  let png = got.val.unwrap().to_array()
  assert_eq(png[1:4].to_owned(), [b'P', b'N', b'G'])
  // 150 × 750 points, two pixels a point, whatever the window's
  assert_eq((png_be32(png, 16), png_be32(png, 20)), (300, 1500))
  let words = t.shots()
  assert_eq(words.length(), 1)
  assert_eq(words[0].length(), 30)
  assert_eq((words[0][0], words[0][29]), ("row 0", "row 29"))
  let ((w, h), drawn) = t.shot_drawn()[0]
  assert_eq((w, h), (300, 1500))
  // (each row its ground and its words' glyphs)
  assert_true(drawn.length() >= 60, msg="\{drawn.length()}")
  // what the screen shows is as it was; the picture's words are nowhere on it
  assert_eq(t.instances(), before)
  assert_true(t.find("row 3") is None)
  t.assert_idle()
}

///|
test "a picture made as nodes taken again under its key before it is: only the later told, of what the later made" {
  let t = @ui.Tester::new(fn(_c) {  }, w=200.0, h=120.0)
  @ui.set_view_app(fn(root) { root.box(fn(b) { b.words(Is("here")) |> ignore }) |> ignore })
  t.draw()
  let told : Array[String] = []
  @ui.take_picture("again", 100.0, picture_rows, fn(_) { told.push("first") })
  @ui.take_picture("again", 100.0, fn(b) { b.box(fn(r) { r.words(Is("the later")) |> ignore }) |> ignore }, fn(_) {
    told.push("second")
  })
  t.draw()
  t.draw()
  assert_eq(told, ["second"])
  assert_eq(t.shots(), [["the later"]])
}
