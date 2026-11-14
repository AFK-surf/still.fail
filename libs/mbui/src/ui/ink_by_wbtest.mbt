// Ctx::ink_by: what a node holds (its words' glyphs, its lines and shapes) drawn in an ink worked out as it is
// painted, its grounds as they are; what the ink reads paints the frame again as it changes, nothing built.

///|
test "ink_by: words and a line drawn in the ink worked out as they are painted, the ground as it is; a new ink painted, nothing built" {
  let ink = @signals.signal(0xCC6633FFL)
  let t = Tester::new(fn(c) {
    let b = c.box(w=Px(200.0), h=Px(60.0), bg=0x224466FFL, fn() {
      c.text("words", color=0x000000FFL, wrap=false) |> ignore
      c.lines([line(arc(20.0, 20.0, 10.0, from=0.0, sweep=3.0), width=2.0, color=0x000000FFL)], w=Px(40.0), h=Px(40.0))
      |> ignore
    })
    c.ink_by(b, fn() { ink.get() })
  }, w=300.0, h=160.0)
  t.check_looks(false)
  t.draw()
  // (r, g, b, a of each instance of `kind`, 0 … 1 each)
  let inks = fn(kinds : Array[Double]) {
    t.drawn_instances().filter(fn(i) { kinds.contains(i[5]) }).map(fn(i) { [i[8], i[9], i[10], i[11]] })
  }
  let as_drawn = fn(c : Int64) { [24, 16, 8, 0].map(fn(s) { ((c >> s) & 0xFFL).to_double() / 255.0 }) }
  let words = [1.0, 7.0]
  assert_true(inks(words).length() > 0 && inks(words).iter().all(fn(g) { g == as_drawn(0xCC6633FFL) }), msg="\{Repr(inks(words))}")
  assert_true(inks([10.0]).length() > 0 && inks([10.0]).iter().all(fn(l) { l == as_drawn(0xCC6633FFL) }), msg="\{Repr(inks([10.0]))}")
  // (its ground its own)
  assert_true(t.drawn_rects().iter().any(fn(r) { r.4 == 0x224466FFL }), msg="\{Repr(t.drawn_rects())}")
  ink.set(0x229944FFL)
  t.frame()
  assert_eq(t.built_why(), "")
  assert_true(inks(words + [10.0]).iter().all(fn(g) { g == as_drawn(0x229944FFL) }), msg="\{Repr(inks(words + [10.0]))}")
}
