// A node of the window's tree's words on one line cut short where even their ellipsis has not the room in its box
// (View::ellipsis_past): cut to its box by default; said so, the ellipsis drawn past it, as an old view's `w=Cut` words
// are; what holds it that clips cutting it either way; how it is drawn only, the same node told otherwise drawn so again.

///|
/// Words 4 wide in a row (`clip`: in a box 10 wide that clips them), their ellipsis drawn past them as `past` says:
/// the window's tree.
fn past_words(past : @signals.Signal[Bool], clip : Bool) -> (Tester, @view.View?) {
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0)
  let words : Ref[@view.View?] = Ref(None)
  set_view_app(fn(root) {
    root.box(fn(r) {
      r.row(Is(true)).width(Is(Some(if clip { 10.0 } else { 300.0 }))).clips(Is(clip)) |> ignore
      r.box(fn(v) {
        v
        .width(Is(Some(4.0)))
        .words(Is("abcdef"), look={ size: 13.0, weight: 400, line: 18.0, wrap: false, tracking: @view.letters_own, balance: false, max_lines: 0 })
        .ellipsis_past(By(fn() { past.get() }))
        |> ignore
        words.val = Some(v)
      })
      |> ignore
    })
    |> ignore
  })
  t.draw()
  (t, words.val)
}

///|
/// Each glyph drawn: where it is (x, y, w, h) and how far right it is cut to.
fn glyphs_cut(t : Tester) -> Array[(Double, Double, Double, Double, Double)] {
  t.drawn_instances().filter(fn(a) { a[5] == 1.0 }).map(fn(a) { (a[0], a[1], a[2], a[3], a[18]) })
}

///|
test "words whose ellipsis has not the room in their box: cut to it; said to, drawn past it, nothing else of them changed; told otherwise, cut again" {
  let past = @signals.signal(false, same=fn(a, b) { a == b })
  let (t, words) = past_words(past, false)
  let v = words.unwrap()
  let cut = glyphs_cut(t)
  let (rect, said) = (v.rect(), t.words())
  past.set(true)
  t.draw()
  let drawn_past = glyphs_cut(t)
  past.set(false)
  t.draw()
  let again = glyphs_cut(t)
  assert_true(cut.length() > 0, msg="the ellipsis drawn")
  // (the same glyphs where they were, cut to the box's right, 4; past it, cut nowhere nearer than the window)
  assert_eq(drawn_past.map(fn(g) { (g.0, g.1, g.2, g.3) }), cut.map(fn(g) { (g.0, g.1, g.2, g.3) }))
  assert_true(cut.iter().all(fn(g) { g.4 <= 4.0 + 0.01 }), msg="cut to its box: \{Repr(cut)}")
  assert_true(drawn_past.iter().all(fn(g) { g.4 > 4.0 + 1.0 && g.0 + g.2 <= g.4 }), msg="drawn past it: \{Repr(drawn_past)}")
  assert_eq(again, cut, msg="told otherwise, cut again")
  // (laid out and read as ever)
  assert_eq(v.rect(), rect)
  assert_eq(t.words(), said)
}

///|
test "words drawn past their box where their ellipsis has not the room, in a box that clips them: cut by that box still" {
  let past = @signals.signal(true, same=fn(a, b) { a == b })
  let (t, _) = past_words(past, true)
  let g = glyphs_cut(t)
  assert_true(g.length() > 0 && g.iter().all(fn(x) { x.4 <= 10.0 + 0.01 }), msg="cut by what holds it: \{Repr(g)}")
  past.set(false)
  t.draw()
  assert_true(glyphs_cut(t).iter().all(fn(x) { x.4 <= 4.0 + 0.01 }), msg="and to its own box, said not to")
}
