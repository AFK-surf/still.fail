// What a node lends what it holds (View::lends, View::lent), and what its parts that show something span across
// (View::shown_across).

///|
test "lent: what a node lends found by what it holds, made with it or shown later, the nearest lender's; none outside it; let go with it" {
  let kind : @view.Lent[String] = @view.Lent::new()
  let shown = @signals.signal(false, same=fn(a, b) { a == b })
  let found : Array[String?] = []
  let outer : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(a) {
        outer.val = Some(a)
        a.lends(kind, "page") |> ignore
        a.box(fn(b) {
          found.push(b.lent(kind))
          b.box(fn(c) {
            c.lends(kind, "card") |> ignore
            c.show(fn() { shown.get() }, fn(d) { d.box(fn(e) { found.push(e.lent(kind)) }) |> ignore })
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
      root.box(fn(z) { found.push(z.lent(kind)) }) |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  assert_eq(found, [Some("page"), None])
  shown.set(true)
  t.frame(400.0, 300.0) |> ignore
  assert_eq(found, [Some("page"), None, Some("card")])
  t.dispose()
  assert_eq(outer.val.unwrap().lent(kind), None)
}

///|
test "shown across: the words and drawings in it within its box, none laid out nowhere or clear" {
  let gone = @signals.signal(false, same=fn(a, b) { a == b })
  let page : Ref[@view.View?] = Ref(None)
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(p) {
        page.val = Some(p)
        p.width(Is(Some(300.0))).height(Is(Some(100.0))) |> ignore
        p.box(fn(row) {
          row.row(Is(true)).padding(Is((20.0, 0.0, 0.0, 0.0))) |> ignore
          // (a ground alone: nothing shown)
          row.box(fn(g) { g.width(Is(Some(30.0))).height(Is(Some(10.0))).ground(Is(0x3366CCFFL)) |> ignore }) |> ignore
          row.box(fn(w) {
            w.words(Is("Join"), look={ size: 15.0, weight: 400, line: 20.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 })
            |> ignore
          })
          |> ignore
          row.box(fn(w) {
            w
            .laid_nowhere(By(fn() { gone.get() }))
            .words(Is("Wide words"), look={ size: 15.0, weight: 400, line: 20.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 })
            |> ignore
          })
          |> ignore
          row.box(fn(w) {
            w
            .alpha(Is(0.0))
            .words(Is("Clear"), look={ size: 15.0, weight: 400, line: 20.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 })
            |> ignore
          })
          |> ignore
        })
        |> ignore
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let (l, r) = page.val.unwrap().shown_across().unwrap()
  assert_eq(l, 50.0)
  let wide = r
  gone.set(true)
  t.frame(400.0, 300.0) |> ignore
  let (l2, r2) = page.val.unwrap().shown_across().unwrap()
  assert_eq(l2, 50.0)
  assert_true(r2 < wide, msg="\{r2} < \{wide}")
}

///|
test "shown across as an event finds it: words come to show and read at once, no frame between, as after a frame" {
  let more = @signals.signal(false, same=fn(a, b) { a == b })
  let page : Ref[@view.View?] = Ref(None)
  let look : @view.WordsLook = { size: 15.0, weight: 400, line: 20.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 }
  let t = @view.Tree::new(
    fn(root) {
      root.box(fn(p) {
        page.val = Some(p)
        p.width(Is(Some(300.0))).height(Is(Some(100.0))).row(Is(true)) |> ignore
        p.box(fn(w) { w.words(Is("Join"), look~) |> ignore }) |> ignore
        p.show(fn() { more.get() }, fn(w) { w.words(Is("and more words"), look~) |> ignore })
      })
      |> ignore
    },
    time=fn() { 0.0 },
  )
  t.frame(400.0, 300.0) |> ignore
  let before = page.val.unwrap().shown_across()
  more.set(true)
  let at_once = page.val.unwrap().shown_across()
  t.frame(400.0, 300.0) |> ignore
  let framed = page.val.unwrap().shown_across()
  assert_eq(at_once, framed)
  assert_true(at_once != before, msg="\{Repr(at_once)} as \{Repr(before)}")
}
