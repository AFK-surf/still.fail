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
          c.clicked(b) |> ignore
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
test "reachable: picked words over an empty old frame, but not under either kind of button" {
  let cover = @signals.signal(0)
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0, platform=2)
  set_view_app(fn(root) {
    old(root, fn(c) { }).height(Is(Some(200.0))) |> ignore
    root.box(fn(p) {
      p.over(Is(true)).width(Is(Some(300.0))) |> ignore
      words_picked(p)
      p.box(fn(w) { w.words_runs(Is([plain("words to pick")])) |> ignore }) |> ignore
    }) |> ignore
    root.show(fn() { cover.get() == 1 }, fn(p) {
      p.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(100.0))).on_press(fn() { }) |> ignore
    })
    root.show(fn() { cover.get() == 2 }, fn(p) {
      p.over(Is(true)).width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
      old(p, fn(c) {
        let id = c.id("cover")
        c.clicked(id) |> ignore
        c.box(id~, w=Px(300.0), h=Px(100.0), fn() { c.text("cover") |> ignore }) |> ignore
      }).grow(Is(1.0)) |> ignore
    })
  })
  t.draw()
  assert_false(t.reachable("words to pick").is_empty())
  for k in [1, 2] {
    cover.set(k)
    t.draw()
    assert_true(t.reachable("words to pick").is_empty(), msg="cover \{k} takes the press")
  }
}

///|
test "locate: a colon in a paragraph and a word on a long line are found at that word, as in an old rich paragraph" {
  let text = "placeRows: a long line whose later words run well past the window's right edge, with more words after them"
  let t = Tester::new(fn(_) { }, w=300.0, h=200.0)
  set_view_app(fn(root) {
    old(root, fn(c) { c.rich([span(text)], size=15.0, line=22.0, wrap=false) |> ignore })
    .height(Is(Some(60.0))) |> ignore
    root.box(fn(p) {
      p.width(Is(Some(900.0)))
      .words_runs(Is([span(text)]), look={ size: 15.0, line: 22.0, weight: 400, wrap: false, tracking: @view.letters_own })
      |> ignore
    }) |> ignore
  })
  t.draw()
  for query in ["placeRows:", "placeRows", "a long"] {
    let old = on_screen_nodes(t.ctx(), query)
    let now = tree_on_screen(t.ctx(), query)
    assert_eq(old.length(), 1)
    assert_eq(now.length(), 1, msg=query)
    assert_eq((now[0].0, now[0].1 - 60.0), (old[0].0, old[0].1), msg=query)
  }
}
