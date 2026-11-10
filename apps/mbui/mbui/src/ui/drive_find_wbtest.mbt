// What a scripted run's steps find on screen (on_screen: Tester::locate) and press (reachable): an old view's words and
// the tree's alike, as they are made however faded (made transparent, shown), a row called by its words found once, by
// its words; going out (drawn only, pressed no more)
// and let go of, neither.

///|
test "locate and reachable: an old view's words and the tree's, made transparent, shown: found and reached; going out, let go of: neither, alike" {
  let (open, shown, going) = (@signals.signal(true), @signals.signal(false), @signals.signal(false))
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    old(root, fn(c) {
      if open.get() {
        // (going out: still drawn, pressed no more, as kit's menus are, inert, on their way out)
        c.overlay("old", inert=going.get(), fn() {
          let b = c.box(left=0.0, top=0.0, w=Px(120.0), h=Px(40.0), fn() { c.text("旧的字") |> ignore })
          c.takes_presses(b)
          c.look(b, { alpha: if shown.get() { 1.0 } else { 0.0 }, dx: 0.0, dy: 0.0, sx: 1.0, sy: 1.0, ox: 0.5, oy: 0.5, rot: 0.0, circle: 0.0, words: 1.0 })
        })
        |> ignore
      }
    })
    .height(Is(Some(300.0)))
    |> ignore
    root.show(fn() { open.get() && !going.get() }, fn(l) {
      l.over(Is(true)) |> ignore
      // (a row called by its words, its words in it: found once, by its words, as an old row read out so is)
      l.box(fn(r) {
        r
        .offset(Is((200.0, 0.0)))
        .says(Is(Some(@view.said(MenuItem, label="树的字"))))
        .alpha(By(fn() { if shown.get() { 1.0 } else { 0.0 } }))
        .presses(Is(true))
        .on_press(fn() {  })
        |> ignore
        r.box(fn(w) { w.words(Is("树的字")) |> ignore }) |> ignore
      })
      |> ignore
    }, leave=drive_find_leave_ms)
  })
  t.draw()
  let both = fn() {
    (
      (t.locate("旧的字").length() > 0, t.locate("树的字").length() > 0),
      (t.reachable("旧的字").length() > 0, t.reachable("树的字").length() > 0),
    )
  }
  let made = both()
  shown.set(true)
  t.draw()
  let seen = both()
  let once = (t.locate("旧的字").length(), t.locate("树的字").length(), t.reachable("树的字").length())
  going.set(true)
  t.draw()
  let out = both()
  open.set(false)
  t.run_for(drive_find_leave_ms)
  assert_eq(
    (made, seen, once, out, both()),
    (
      ((true, true), (true, true)),
      ((true, true), (true, true)),
      (1, 1, 1),
      ((false, false), (false, false)),
      ((false, false), (false, false)),
    ),
  )
}

///|
let drive_find_leave_ms : Double = 100.0

///|
test "img: a picture by its source, shapes by what they are called, as an old view's and the tree's alike: found, reached and pressed; a name it is not, neither" {
  let pressed = Ref(0)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0, images=[
    ("old/glyph/robot.png", 40, 40),
    ("tree/glyph/robot.png", 40, 40),
  ])
  set_view_app(fn(root) {
    old(root, fn(c) {
      c.box(left=0.0, top=0.0, w=Px(400.0), h=Px(60.0), fn() {
        c.image("old/glyph/robot.png", w=Px(40.0), h=Px(40.0)) |> ignore
      })
      |> ignore
    })
    .height(Is(Some(60.0)))
    |> ignore
    root.box(fn(row) {
      row.row(Is(true)).height(Is(Some(60.0))) |> ignore
      // (shapes called by a glyph's name, as a mark's are: pressed)
      row.box(fn(g) {
        g
        .width(Is(Some(40.0)))
        .height(Is(Some(40.0)))
        .shapes(Is([@paint.shape_of([([0.0, 0.0, 40.0, 0.0, 40.0, 40.0], true)], fill=0x000000FFL)]))
        .drawn_as(Is("sf/pic/glyph/rocket"))
        .presses(Is(true))
        .on_press(fn() { pressed.val += 1 })
        |> ignore
      })
      |> ignore
      // (a picture by its source)
      row.box(fn(p) {
        p.width(Is(Some(40.0))).height(Is(Some(40.0))).image(Is(Some(("tree/glyph/robot.png", "", 64)))) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  let rocket = t.reachable("img:glyph/rocket")
  let found = (
    t.locate("img:glyph/rocket").length(),
    rocket.length(),
    t.locate("img:old/glyph/robot").length(),
    t.locate("img:tree/glyph/robot").length(),
    t.locate("img:glyph/robot").length(),
    t.locate("img:glyph/rock").length(),
    t.locate("img:glyph/tiger").length(),
  )
  t.tap(rocket[0].0, rocket[0].1)
  assert_eq((found, pressed.val), ((1, 1, 1, 1, 2, 1, 0), 1))
}
