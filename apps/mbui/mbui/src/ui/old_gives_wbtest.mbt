// An old view as tall as what it holds asks, laid out in the height its node is given (old's `gives`): a list in it as
// tall as its rows (Ctx::gives_way), giving way where the node is held shorter (its window short of room), scrolling in
// itself there to its last row, nothing of what is under it cut off. What it asks never the height it was given: opened
// in a short window and grown, the same as opened in the tall one; its rows fewer and more again, as tall as each asks.
// Moved: painted alone, nothing built.

///|
/// A window 400×`h` whose tree holds an old view held to the window less 100, moved by `at`, that gives way: a line 30
/// high, a list of `rows` rows 30 high as tall as all of them and giving way, a foot 30 high. Its builds in `built`.
fn gives_tester(
  h : Double,
  rows : @signals.Signal[Int],
  at : @signals.Signal[(Double, Double)],
  built : Ref[Int],
  ids : Map[String, @view.View],
) -> Tester {
  let t = Tester::new(fn(_c) {  }, w=400.0, h~)
  set_view_app(fn(root) {
    root.box(fn(col) {
      col.width(Is(Some(400.0))) |> ignore
      let o = old(col, natural=true, gives=true, fn(c) {
        built.val = built.val + 1
        c.box(w=Fill(1.0), h=Fill(1.0), fn() {
          c.box(w=Fill(1.0), h=Px(30.0), fn() { c.text("头", wrap=false) |> ignore }) |> ignore
          let n = rows.get()
          let list = c.box(style=style(w=Full, h=Fixed(30.0 * n.to_double())), fn() {
            c.list("行", n, 30.0, fn(i) { c.box(w=Fill(1.0), h=Px(30.0), fn() { c.text("行\{i}", wrap=false) |> ignore }) |> ignore }) |> ignore
          })
          c.gives_way(list)
          c.box(w=Fill(1.0), h=Px(30.0), fn() { c.text("脚", wrap=false) |> ignore }) |> ignore
        })
        |> ignore
      })
      o.max_height(By(fn() { Some(o.window().1 - 100.0) })).offset(By(fn() { at.get() })) |> ignore
      ids["old"] = o
    })
    |> ignore
  })
  t.frame()
  t
}

///|
/// How tall the old view is laid out, where its foot is drawn, its last row (by its words) after the wheel down its
/// list as far as it goes, and whether that row is drawn whole above the foot.
fn gives_said(t : Tester, ids : Map[String, @view.View], rows : Int) -> String {
  let at = fn(s : String) { t.words().filter(fn(x) { x.0 == s }).map(fn(x) { x.2 }).last() }
  let h = ids["old"].laid_size().1
  let foot = at("脚")
  t.wheel(200.0, 60.0, 30.0 * rows.to_double() + 600.0)
  t.run_for(move_most_ms)
  let last = at("行\{rows - 1}")
  let whole = match (last, at("脚")) {
    (Some(y), Some(f)) => y + 30.0 <= f + 0.01
    _ => false
  }
  t.wheel(200.0, 60.0, -(30.0 * rows.to_double() + 600.0))
  t.run_for(move_most_ms)
  "h \{h} foot \{foot} last \{last} whole \{whole}"
}

///|
test "old gives: as tall as what it holds asks while the window has the room; held shorter, its list giving way and scrolling to its last row above its foot; each frame as built whole" {
  let out = []
  for n in [3, 40] {
    let (rows, at, built, ids) = (@signals.signal(n), @signals.signal((0.0, 0.0)), Ref(0), Map::new())
    let t = gives_tester(600.0, rows, at, built, ids)
    out.push(gives_said(t, ids, n))
  }
  assert_eq(out, [
    "h 150 foot Some(120) last Some(90) whole true",
    "h 500 foot Some(470) last Some(440) whole true",
  ])
}

///|
test "old gives: opened in a short window and grown, the same as opened in the tall one; its rows more then fewer, as tall as each asks" {
  // (opened in the tall one, first)
  let (rows2, at2, built2, ids2) = (@signals.signal(40), @signals.signal((0.0, 0.0)), Ref(0), Map::new())
  let direct = gives_said(gives_tester(600.0, rows2, at2, built2, ids2), ids2, 40)
  let (rows, at, built, ids) = (@signals.signal(40), @signals.signal((0.0, 0.0)), Ref(0), Map::new())
  let t = gives_tester(300.0, rows, at, built, ids)
  let short = gives_said(t, ids, 40)
  t.resize(400.0, 600.0)
  t.frame()
  let grown = gives_said(t, ids, 40)
  rows.set(3)
  t.frame()
  let fewer = gives_said(t, ids, 3)
  rows.set(40)
  t.frame()
  let more = gives_said(t, ids, 40)
  assert_eq((grown == direct, [short, grown, fewer, more]), (true, [
    "h 200 foot Some(170) last Some(140) whole true",
    "h 500 foot Some(470) last Some(440) whole true",
    "h 150 foot Some(120) last Some(90) whole true",
    "h 500 foot Some(470) last Some(440) whole true",
  ]))
}

///|
test "old gives: moved, painted alone: nothing built nor laid out, as tall" {
  let (rows, at, built, ids) = (@signals.signal(40), @signals.signal((0.0, 0.0)), Ref(0), Map::new())
  let t = gives_tester(600.0, rows, at, built, ids)
  // (laid out the same twice: what comes after it may be painted alone, as old_natural_wbtest has it)
  t.clock_frame()
  t.clock_frame()
  // (painted alone: nothing built nor laid out, the Tester's own check building it whole after it and comparing, as
  // ever: what that builds not counted)
  let was = paints_alone.val
  at.set((7.0, 3.0))
  t.clock_frame()
  assert_eq((paints_alone.val - was, ids["old"].laid_size().1), (1, 500.0))
}
