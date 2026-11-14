// Whether words show cut short (View::words_cut_now) as an old view's box says it (Ctx::shows_cut): one line ended in
// an ellipsis, said one of its shorter ways, lines left off; the box holding them with them; whole, none.

///|
/// The words of squeeze_wbtest's case, too long for a row of 100.
let cut_long : String = "words longer than the row has room for"

///|
test "words cut short in nodes are said so as an old view says them (Ctx::shows_cut): one line with an ellipsis, wrapped lines left off, what holds them; whole, none" {
  // (the old view's, as squeeze_wbtest has it)
  let width = @signals.signal(100.0)
  let old : Ref[(Bool, Bool, Bool)] = Ref((false, false, false))
  let t = Tester::new(
    fn(c) {
      let (x, y, z) = (c.id("x"), c.id("y"), c.id("z"))
      c.box(dir=Column, w=Px(width.get()), fn() {
        c.box(dir=Row, id=x, taps=false, fn() { c.text(cut_long, w=Cut, wrap=false) |> ignore }) |> ignore
        c.box(dir=Row, id=y, taps=false, fn() { c.text("short", wrap=false) |> ignore }) |> ignore
        c.box(id=z, taps=false, fn() { c.text(cut_long, max_lines=1) |> ignore }) |> ignore
      })
      |> ignore
      old.val = (c.shows_cut(x), c.shows_cut(y), c.shows_cut(z))
    },
    w=800.0,
    h=200.0,
  )
  t.draw()
  t.frame()
  let old_narrow = old.val
  // (with the room for all of it: none cut)
  width.set(700.0)
  t.frame()
  t.frame()
  let old_wide = old.val
  // (the same in nodes, in a window of its own: a row of one line said to be cut, one of short words, wrapped words
  // laid out one line tall)
  let nodes : Map[String, @view.View] = Map([])
  let node_width = @signals.signal(100.0)
  let one = { ..@view.words_plain, wrap: false }
  let n = Tester::new(fn(_c) {  }, w=800.0, h=200.0)
  n.check_looks(false)
  set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(col) {
      nodes["col"] = col
      col.width(By(fn() { Some(node_width.get()) })) |> ignore
      col.box(fn(x) {
        nodes["x"] = x
        x.row(Is(true)) |> ignore
        x.box(fn(w) { w.cuts(Is(true)).words(Is(cut_long)).words_look(Is(one)) |> ignore }) |> ignore
      })
      |> ignore
      col.box(fn(y) {
        nodes["y"] = y
        y.row(Is(true)) |> ignore
        y.box(fn(w) { w.words(Is("short")).words_look(Is(one)) |> ignore }) |> ignore
      })
      |> ignore
      col.box(fn(z) {
        nodes["z"] = z
        z.box(fn(w) { w.height(Is(Some(22.0))).words(Is(cut_long)) |> ignore }) |> ignore
      })
      |> ignore
    })
    |> ignore
  })
  n.draw()
  let said = fn() { (nodes["x"].words_cut_now(), nodes["y"].words_cut_now(), nodes["z"].words_cut_now()) }
  assert_eq((old_narrow, said(), nodes["col"].words_cut_now()), ((true, false, true), (true, false, true), true))
  node_width.set(700.0)
  n.draw()
  assert_eq((old_wide, said(), nodes["col"].words_cut_now()), ((false, false, false), (false, false, false), false))
}

///|
test "words on one line said a shorter way where theirs have not the room are cut short, the shorter one whole or not; with the room, not" {
  let room = @signals.signal(1000.0)
  let row : Ref[@view.View?] = Ref(None)
  let t = Tester::new(fn(_c) {  }, w=400.0, h=200.0)
  t.check_looks(false)
  set_view_app(fn(root) {
    root.lines_up(Is(Some(Start))) |> ignore
    root.box(fn(r) {
      row.val = Some(r)
      r.row(Is(true)).width(By(fn() { Some(room.get()) })) |> ignore
      r.box(fn(w) { w.words(Is("一二三四五六")).words_look(Is({ ..@view.words_plain, wrap: false })).shorter(Is(["一二"])) |> ignore })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  assert_false(row.val.unwrap().words_cut_now())
  room.set(60.0)
  t.draw()
  assert_true(row.val.unwrap().words_cut_now(), msg="its shorter one said")
  assert_true(t.rect_of("一二") is Some(_), msg="the shorter one drawn")
}
