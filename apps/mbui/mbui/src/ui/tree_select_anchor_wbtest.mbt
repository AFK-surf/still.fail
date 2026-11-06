///|
test "selection keeps the words already picked as an anchored list scrolls beyond them" {
  let height = @signals.signal(300.0)
  let t = Tester::new(fn(_) {}, w=400.0, h=400.0)
  t.check_looks(false)
  let scroll = @view.Scroll::list()
  set_view_app(fn(root) {
    root.box(fn(page) {
      page.height(By(fn() { Some(height.get()) })).width(Is(Some(300.0))) |> ignore
      words_picked(page)
      page.scrolls_anchored(scroll, fn() { Array::makei(40, fn(i) { i }) }, est=22.0, from_end=false, ahead=0.0, fn(row, i) {
        row.box(fn(n) {
          n.words_runs(Is([plain("第 \{i} 段 "), bold("hello")]), ink=0x333333FFL, look={ size: 15.0, weight: 400, line: 22.0, wrap: true, tracking: @view.letters_own, balance: false }) |> ignore
        }) |> ignore
      }) |> ignore
    }) |> ignore
  })
  t.draw()
  t.drawn_now()
  finger(0, 2.0, 11.0)
  t.frame_at(t.time() + 16.0)
  finger(1, 60.0, 250.0)
  t.frame_at(t.time() + 16.0)
  height.set(200.0)
  t.frame_at(t.time() + 16.0)
  let mut was = t.ctx().selected_text()
  for _ in 0..<10 {
    t.frame_at(t.time() + 16.0)
    t.frame_at(t.time() + 16.0)
    let now = t.ctx().selected_text()
    assert_true(now.length() > was.length() && now.has_prefix(was), msg="selection lost text: \{was} -> \{now}")
    was = now
  }
  finger(2, 60.0, 250.0)
  t.frame_at(t.time() + 16.0)
}
