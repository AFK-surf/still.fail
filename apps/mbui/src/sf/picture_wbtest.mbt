///|
test "a station emoji wider than its slot stays whole and centred" {
  // The fake host's pair is wider than the slot, as a single Segoe UI Emoji is
  // on Windows. The mark must not inherit a column's text ellipsis.
  let emoji = "🚀🚀"
  let t = @ui.Tester::new(fn(c) {
    c.box(w=Px(100.0), align=ACenter, fn() {
      c.box(w=Px(28.0), h=Px(28.0), align=ACenter, justify=JCenter, fn() {
        station_mark(c, emoji, "", 28.0, theme().p.text)
      }) |> ignore
    }) |> ignore
  })
  let runs = t.text_runs()
  assert_eq(runs.map(fn(r) { r.text }), [emoji])
  let mark = runs[0]
  assert_true(mark.x1 - mark.x0 > 28.0)
  assert_true(((mark.x0 + mark.x1) / 2.0 - 50.0).abs() < 1.0)
  t.set_font_scale(1.5)
  t.frame()
  let larger = t.text_runs()
  assert_eq(larger.map(fn(r) { r.text }), [emoji])
  assert_true(larger[0].x1 - larger[0].x0 > mark.x1 - mark.x0)
  assert_true(((larger[0].x0 + larger[0].x1) / 2.0 - 50.0).abs() < 1.0)
}

///|
test "a station emoji stands where the app's own face sets it, whatever face its words are in" {
  // (the fake face reaches 0.8 and 0.2 of its size, not Inter's 0.97 and 0.24: as a face chosen in its place does)
  let wide = Ref(true)
  let t = @ui.Tester::new(fn(c) {
    @ui.set_web_lines(wide.val)
    c.box(w=Px(28.0), h=Px(28.0), align=ACenter, justify=JCenter, fn() {
      station_mark(c, "🏠", "", 28.0, theme().p.text)
    }) |> ignore
  })
  // 25.2 in lines of 28: Inter's ascent and descent 24 and 6, the baseline 23; the fake face's 20 and 5 would set it
  // at 21
  assert_eq(t.text_runs().map(fn(r) { r.base }), [23.0])
  // set as Android sets lines (the phone's pages), as before: the words' face's
  wide.val = false
  t.frame()
  assert_eq(t.text_runs().map(fn(r) { r.base }), [@ui.line_baseline(28.0, size=25.2)])
  @ui.set_web_lines(false)
}
