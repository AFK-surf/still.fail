///|
test "after: true once its condition has held so long by the tester's clock; off, from nothing again; kept, paused" {
  let on = Ref(false)
  let keep = Ref(false)
  let done = Ref(false)
  let t = @ui.Tester::new(fn(c) { done.val = after(c, "d", on.val, 500.0, keep=keep.val) })
  on.val = true
  t.frame(ms=16.0)
  t.frame(ms=300.0)
  assert_false(done.val)
  t.frame(ms=200.0)
  assert_true(done.val)
  // off and on again: from nothing
  on.val = false
  t.frame()
  on.val = true
  t.frame()
  t.frame(ms=300.0)
  assert_false(done.val)
  // paused, kept: it goes on from where it was
  keep.val = true
  on.val = false
  t.frame(ms=1000.0)
  on.val = true
  t.frame()
  t.frame(ms=150.0)
  assert_false(done.val)
  t.frame(ms=60.0)
  assert_true(done.val)
}

///|
test "presence: shown comes in; not shown, built until its exit has played, then gone" {
  let shown = Ref(false)
  let p : Ref[Presence] = Ref({ built: false, shown: false, t: 0.0 })
  let t = @ui.Tester::new(fn(c) { p.val = presence(c, "x", shown.val) })
  assert_false(p.val.built)
  shown.val = true
  t.draw()
  assert_true(p.val.built && p.val.shown)
  t.run_for(presence_in_ms)
  assert_eq(p.val.t, 1.0)
  shown.val = false
  t.draw()
  // half its exit's time
  let mid_way = presence_out_ms / 2.0
  t.run_for(mid_way)
  assert_true(p.val.leaving())
  assert_true(p.val.t < 1.0)
  t.run_for(presence_out_ms - mid_way)
  assert_false(p.val.built)
  t.assert_idle()
}

///|
test "a button: pressed by a tap, by Enter, by Activate; disabled, by none of them" {
  let n = Ref(0)
  let disabled = Ref(false)
  let t = @ui.Tester::new(fn(c) {
    if button(c, "Go", disabled=disabled.val).clicked {
      n.val = n.val + 1
    }
  })
  t.click(Button, label="Go")
  t.tab()
  t.press("Enter")
  t.act(Button, Activate, label="Go")
  assert_eq(n.val, 3)
  disabled.val = true
  t.frame()
  assert_eq(t.get(Button, label="Go").disabled, true)
  t.click(Button, label="Go")
  t.press("Enter")
  assert_eq(n.val, 3)
}
