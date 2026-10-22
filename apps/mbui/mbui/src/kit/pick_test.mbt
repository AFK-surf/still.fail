// Picking a passage of words (pick.mbt) as a finger does it: held still, the word under it; sliding on, widened by
// words; a tap anywhere else, let go.

///|
test "held still on words: the word under the finger is picked; sliding on widens it by words; a tap elsewhere lets go" {
  let p = @kit.Pick::new()
  let t = @ui.Tester::new(
    fn(c) {
      // (words a box's rich paragraphs hold: Ctx::words)
      let box = c.box(fn() { c.rich([@ui.plain("alpha beta gamma delta")], wrap=false) |> ignore })
      c.words(box, "w", a=p.a, b=p.b, color=0x3B82F640L)
      if p.hold(c, "w", c.press().down) {
        c.take_press()
      }
      p.slide(c)
      p.tapped_away(c, []) |> ignore
    },
    w=400.0,
    h=200.0,
  )
  let (rx, ry, _, rh) = t.rect_of("alpha beta gamma delta").unwrap()
  let (x, y) = (rx + 4.0, ry + rh / 2.0)
  t.press_at(x, y)
  // not yet a long press's time
  t.run_for(@ui.long_press_ms / 2.0)
  assert_true(!p.of("w"))
  t.run_for(@ui.long_press_ms)
  assert_true(p.of("w"))
  assert_eq((p.a, p.b), (0, 5))
  // sliding on to the end: from the word first held to the word under the finger
  let (_, _, rw, _) = t.rect_of("alpha beta gamma delta").unwrap()
  t.move(rx + rw - 2.0, y)
  assert_eq((p.a, p.b), (0, 22))
  t.release(rx + rw - 2.0, y)
  t.draw()
  assert_true(p.of("w") && !p.widening)
  // a tap away from it lets go
  t.tap(300.0, 150.0)
  assert_true(!p.of("w"))
}
