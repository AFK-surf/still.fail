// Tester::find: the centre of words where they are laid out, an old view's text or a node of the window's tree's, as
// they are made, however faded they are drawn this frame (made transparent, shown, going out); none once let go of.
// Whether they are seen is the glyphs' to say (Tester::glyphs_seen, glyph_clips), not this.

///|
test "find: an old view's text and the tree's words, made transparent, then shown, then going out, then let go of: found each time but the last, the old's and the tree's alike" {
  let (open, shown) = (@signals.signal(true), @signals.signal(false))
  let t = Tester::new(fn(_c) {  }, w=400.0, h=300.0, platform=0)
  set_view_app(fn(root) {
    old(root, fn(c) {
      if open.get() {
        let b = c.box(w=Px(120.0), h=Px(40.0), fn() { c.text("旧的字") |> ignore })
        c.look(b, { alpha: if shown.get() { 1.0 } else { 0.0 }, dx: 0.0, dy: 0.0, sx: 1.0, sy: 1.0, ox: 0.5, oy: 0.5, rot: 0.0, circle: 0.0, words: 1.0 })
      }
    })
    .height(Is(Some(60.0)))
    |> ignore
    root.show(fn() { open.get() }, fn(l) {
      l.box(fn(w) { w.words(Is("树的字")).alpha(By(fn() { if shown.get() { 1.0 } else { 0.0 } })) |> ignore }) |> ignore
    }, leave=find_leave_ms)
  })
  t.draw()
  let both = fn() { (t.find("旧的字") is Some(_), t.find("树的字") is Some(_)) }
  let made = both()
  shown.set(true)
  t.draw()
  let seen = both()
  open.set(false)
  t.draw()
  // (the old view's text let go of as it is no more built; the tree's going out over find_leave_ms, then let go of)
  let going = t.find("树的字") is Some(_)
  t.run_for(find_leave_ms)
  assert_eq((made, seen, going, both()), ((true, true), (true, true), true, (false, false)))
}

///|
let find_leave_ms : Double = 100.0
