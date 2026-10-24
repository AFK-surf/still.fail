///|
test "a press says the keys held as it went down, whatever is held or let go of after" {
  let seen : Ref[@ui.Press?] = Ref::new(None)
  let t = @ui.Tester::new(
    fn(c) {
      let p = c.press()
      if p.down || p.lifted {
        seen.val = Some(p)
      }
      c.box(w=Fill(1.0), h=Fill(1.0), fn() { c.text("here", size=10.0) |> ignore }) |> ignore
    },
    w=200.0,
    h=200.0,
  )
  t.draw()
  // ⌘ held as it goes down, let go while it is down: still a press with ⌘
  t.hold_mods(@ui.mod_cmd)
  t.press_at(50.0, 50.0)
  t.draw()
  assert_eq(seen.val.map(fn(p) { p.mods }), Some(@ui.mod_cmd))
  t.hold_mods(0)
  t.move(50.0, 120.0)
  t.draw()
  assert_eq(seen.val.map(fn(p) { p.mods }), Some(@ui.mod_cmd))
  t.release(50.0, 120.0)
  t.draw()
  assert_eq(seen.val.map(fn(p) { p.mods }), Some(@ui.mod_cmd))
  // none held as it goes down, ⌥ pressed after: a press with none
  t.press_at(50.0, 50.0)
  t.draw()
  t.hold_mods(@ui.mod_alt)
  t.move(50.0, 120.0)
  t.draw()
  assert_eq(seen.val.map(fn(p) { p.mods }), Some(0))
}
